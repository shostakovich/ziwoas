defmodule Ziwoas.Govee.LanTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Govee.Lan

  defp decoded(%{data: data}), do: JSON.decode!(data)

  describe "datagram/1" do
    test "commands go to the lamp's port 4003" do
      assert %{host: "10.0.0.5", port: 4003} = datagram = Lan.datagram({:turn, "10.0.0.5", true})
      assert decoded(datagram) == %{"msg" => %{"cmd" => "turn", "data" => %{"value" => 1}}}

      assert decoded(Lan.datagram({:turn, "10.0.0.5", false})) ==
               %{"msg" => %{"cmd" => "turn", "data" => %{"value" => 0}}}

      assert decoded(Lan.datagram({:brightness, "10.0.0.5", 40})) ==
               %{"msg" => %{"cmd" => "brightness", "data" => %{"value" => 40}}}

      assert decoded(Lan.datagram({:request_status, "10.0.0.5"})) ==
               %{"msg" => %{"cmd" => "devStatus", "data" => %{}}}
    end

    test "colour and white share colorwc, each zeroing the other" do
      assert decoded(Lan.datagram({:color, "10.0.0.5", %{r: 255, g: 0, b: 10}})) ==
               %{
                 "msg" => %{
                   "cmd" => "colorwc",
                   "data" => %{
                     "color" => %{"r" => 255, "g" => 0, "b" => 10},
                     "colorTemInKelvin" => 0
                   }
                 }
               }

      assert decoded(Lan.datagram({:color_temp, "10.0.0.5", 2700})) ==
               %{
                 "msg" => %{
                   "cmd" => "colorwc",
                   "data" => %{
                     "color" => %{"r" => 0, "g" => 0, "b" => 0},
                     "colorTemInKelvin" => 2700
                   }
                 }
               }
    end

    test "the scan goes to the multicast group" do
      assert %{host: "239.255.255.250", port: 4001} = scan = Lan.datagram(:discover)

      assert decoded(scan) == %{
               "msg" => %{"cmd" => "scan", "data" => %{"account_topic" => "reserve"}}
             }

      assert Lan.scan_group() == {239, 255, 255, 250}
      assert Lan.listen_port() == 4002
    end
  end

  describe "send_datagram/1" do
    # A UDP socket on localhost stands in for the lamp.
    setup do
      {:ok, lamp} = :gen_udp.open(0, [:binary, ip: {127, 0, 0, 1}, active: true])
      {:ok, port} = :inet.port(lamp)
      on_exit(fn -> :gen_udp.close(lamp) end)
      %{port: port}
    end

    test "sends the datagram from a throwaway socket", %{port: port} do
      datagram = %{Lan.datagram({:brightness, "127.0.0.1", 40}) | port: port}
      assert Lan.send_datagram(datagram) == :ok

      assert_receive {:udp, _socket, {127, 0, 0, 1}, _from, data}
      assert data == datagram.data
    end

    test "an address that does not parse is an error, nothing is sent", %{port: port} do
      assert Lan.send_datagram(%{host: "lamp.local", port: port, data: "x"}) == {:error, :einval}
      refute_receive {:udp, _, _, _, _}, 50
    end
  end

  defp reply(cmd, data), do: JSON.encode!(%{"msg" => %{"cmd" => cmd, "data" => data}})

  describe "parse_status/1" do
    test "a devStatus reply" do
      payload =
        reply("devStatus", %{
          "onOff" => 1,
          "brightness" => 80,
          "color" => %{"r" => 255, "g" => 100, "b" => 0},
          "colorTemInKelvin" => 0,
          "sku" => "H6008"
        })

      assert Lan.parse_status(payload) == %{
               on: true,
               brightness: 80,
               color_r: 255,
               color_g: 100,
               color_b: 0,
               color_temp_k: 0,
               sku: "H6008"
             }
    end

    test "missing readings are nil; onOff other than 1 is off" do
      assert Lan.parse_status(reply("devStatus", %{"onOff" => 0})) == %{
               on: false,
               brightness: nil,
               color_r: nil,
               color_g: nil,
               color_b: nil,
               color_temp_k: nil,
               sku: nil
             }

      assert %{on: false} = Lan.parse_status(reply("devStatus", %{"onOff" => "1"}))
    end

    test "broken packets are nil, never a crash" do
      for payload <- [
            "",
            "not json",
            "{\"msg\":",
            "[]",
            JSON.encode!(%{"msg" => "devStatus"}),
            JSON.encode!(%{"msg" => %{"data" => []}}),
            reply("devStatus", %{"brightness" => 50}),
            reply("devStatus", %{"onOff" => 1, "brightness" => 101}),
            reply("devStatus", %{"onOff" => 1, "color" => %{"r" => 300}}),
            reply("devStatus", %{"onOff" => 1, "colorTemInKelvin" => -1}),
            reply("devStatus", %{"onOff" => 1, "sku" => 6008}),
            <<0xFF, 0xFE>>
          ],
          do: assert(Lan.parse_status(payload) == nil, inspect(payload))
    end
  end

  describe "parse_scan/1" do
    test "a scan reply gives IP, MAC and SKU" do
      payload = reply("scan", %{"ip" => "10.0.0.5", "device" => "AA:BB", "sku" => "H6008"})
      assert Lan.parse_scan(payload) == %{ip: "10.0.0.5", mac: "AA:BB", sku: "H6008"}
    end

    test "without IP or MAC, or broken, it is nil" do
      assert Lan.parse_scan(reply("scan", %{"device" => "AA:BB"})) == nil
      assert Lan.parse_scan(reply("scan", %{"ip" => "10.0.0.5", "device" => nil})) == nil
      assert Lan.parse_scan("garbage") == nil
    end
  end

  describe "telemetry/1" do
    defp status(attrs),
      do:
        Map.merge(
          %{
            on: true,
            brightness: nil,
            color_r: nil,
            color_g: nil,
            color_b: nil,
            color_temp_k: nil
          },
          attrs
        )

    test "a positive colour temperature wins over the colour" do
      assert Lan.telemetry(
               status(%{brightness: 50, color_temp_k: 2700, color_r: 1, color_g: 2, color_b: 3})
             ) ==
               %{on: true, reachable: true, brightness: 50, color_temp_k: 2700}
    end

    test "else the colour, when the lamp sent one" do
      assert Lan.telemetry(status(%{color_temp_k: 0, color_r: 1, color_g: 2, color_b: 3})) ==
               %{on: true, reachable: true, color: %{r: 1, g: 2, b: 3}}

      assert Lan.telemetry(status(%{on: false})) == %{on: false, reachable: true}
    end
  end
end
