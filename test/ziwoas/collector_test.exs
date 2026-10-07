defmodule Ziwoas.CollectorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ziwoas.{Collector, Config}

  @config Config.from_yaml!("""
          location:
            timezone: Europe/Berlin
          mqtt:
            host: broker
            port: 1883
            topic_prefix: shellies
          fritz_box:
            host: fritz.box
            user: u
            password: p
          fritz_poll:
            active_interval_seconds: 5
            idle_interval_seconds: 60
            idle_threshold_w: 10
            timeout_seconds: 2
          plugs:
            - id: bkw
              name: BKW
              role: producer
            - id: washer
              name: Waschmaschine
              role: consumer
              driver: fritz_dect
              ain: "08761 0500475"
          solakon:
            host: 192.168.8.166
            control_enabled: true
          govee:
            api_key: k
          """)

  @bare %{
    @config
    | solakon: nil,
      govee: nil,
      plugs: Enum.reject(@config.plugs, &(&1.driver == :fritz_dect))
  }

  defp ids(children) do
    Enum.map(children, fn
      %{id: id} -> id
      {module, opts} -> {module, Keyword.get(opts, :plug, %{id: nil}).id}
    end)
  end

  test "a full configuration starts every connection and device" do
    assert ids(Collector.children(@config)) == [
             {Ziwoas.Mqtt, "ziwoas-phoenix-ingest"},
             {Ziwoas.Solakon.Monitor, nil},
             {Ziwoas.Fritz.Bridge, "washer"},
             {Task.Supervisor, nil},
             {Ziwoas.Govee.Bridge, nil},
             {Ziwoas.Mqtt, "ziwoas-phoenix-command"}
           ]
  end

  test "the ingest connection carries the status handler, subscribed to its topic" do
    [ingest | _] = Collector.children(@bare)

    assert ingest.id == {Ziwoas.Mqtt, "ziwoas-phoenix-ingest"}
    {Tortoise311.Connection, :start_link, [opts]} = ingest.start

    assert opts[:subscriptions] == [{"shellies/+/status/switch:0", 0}]

    assert {Ziwoas.Collector.MqttRouter, [{Ziwoas.Plugs.ShellyStatusHandler, _}]} =
             opts[:handler]
  end

  test "without devices only the ingest and the command connection run" do
    assert ids(Collector.children(@bare)) == [
             {Ziwoas.Mqtt, "ziwoas-phoenix-ingest"},
             {Ziwoas.Mqtt, "ziwoas-phoenix-command"}
           ]
  end

  test "the Solakon monitor gets the inverter's address" do
    assert {Ziwoas.Solakon.Monitor, [host: "192.168.8.166", port: 502, unit_id: 1]} =
             Enum.find(Collector.children(@config), &match?({Ziwoas.Solakon.Monitor, _}, &1))
  end

  test "control without monitoring starts no monitor and says that no tick runs" do
    config = %{
      @bare
      | solakon: %{@config.solakon | monitoring_enabled: false, control_enabled: true}
    }

    log = capture_log(fn -> assert length(Collector.children(config)) == 2 end)

    assert log =~ "control_enabled, but monitoring_enabled is off"
  end

  test "each Fritz bridge polls its plug with the Fritz!Box's credentials" do
    assert {Ziwoas.Fritz.Bridge, opts} =
             Enum.find(Collector.children(@config), &match?({Ziwoas.Fritz.Bridge, _}, &1))

    assert opts[:plug].id == "washer"
    assert %Ziwoas.Fritz.DectClient{host: "fritz.box", user: "u", timeout_s: 2} = opts[:client]
  end

  test "a Govee config without an API key starts no bridge" do
    log =
      capture_log(fn ->
        config = %{@bare | govee: %{@config.govee | api_key: ""}}
        assert length(Collector.children(config)) == 2
      end)

    assert log =~ "missing govee.api_key"
  end
end
