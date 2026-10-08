defmodule Ziwoas.Sensors.PollJobTest do
  use Ziwoas.DataCase

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Ziwoas.{Repo, TestConfigs}
  alias Ziwoas.Sensors.{PollJob, Reading, SwitchBotClient}
  alias Ziwoas.Trmnl.Push

  @sensors """
  switchbot:
    token: t
    secret: s
  sensors:
    - id: A
      name: Wohnzimmer
      type: meter_pro_co2
      room: Wohnzimmer
    - id: B
      name: Balkon
      type: outdoor_meter
  trmnl:
    sensors_webhook_url: https://example.test/sensors
  """

  setup do
    Ziwoas.TestClock.freeze("2026-10-05T12:00:00.250000+02:00")
    Ziwoas.Sensors.subscribe()
    :ok
  end

  defp context, do: [config: TestConfigs.plugs(@sensors), at: Ziwoas.Clock.now()]

  defp stub_switchbot(status) do
    Req.Test.stub(SwitchBotClient, fn conn ->
      id = conn.path_info |> Enum.at(2)

      case status.(id) do
        code when is_integer(code) ->
          Plug.Conn.send_resp(conn, code, "")

        body ->
          Plug.Conn.send_resp(conn, 200, JSON.encode!(%{"statusCode" => 100, "body" => body}))
      end
    end)
  end

  defp stub_trmnl do
    test = self()

    Req.Test.stub(Push, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:pushed, conn.host, conn.request_path, body})
      Plug.Conn.send_resp(conn, 200, "")
    end)
  end

  defp readings, do: Repo.all(from r in Reading, order_by: r.device_id)

  defp status(id) do
    %{
      "temperature" => 20.0,
      "humidity" => 50,
      "CO2" => if(id == "A", do: 600),
      "battery" => 80,
      "version" => "V1"
    }
  end

  test "stores a reading per sensor, all at the same instant" do
    stub_switchbot(&status/1)
    stub_trmnl()

    PollJob.perform(context())

    assert [a, b] = readings()

    assert {a.device_id, a.co2, a.temperature, a.humidity, a.battery_pct} ==
             {"A", 600, 20.0, 50, 80}

    assert {b.device_id, b.co2, b.firmware_version} == {"B", nil, "V1"}
    assert a.taken_at == ~U[2026-10-05 10:00:00.250000Z]
    assert b.taken_at == a.taken_at
  end

  test "an Integer temperature becomes a Float, humidity keeps its decimal, battery is rounded" do
    stub_switchbot(fn _id -> %{"temperature" => 21, "humidity" => 52.7, "battery" => 99.4} end)
    stub_trmnl()

    PollJob.perform(context())

    assert [%{temperature: 21.0, humidity: 52.7, battery_pct: 99} | _] = readings()
  end

  test "a SEN66 is read over its port, not polled" do
    test = self()

    Req.Test.stub(SwitchBotClient, fn conn ->
      send(test, {:polled_device, Enum.at(conn.path_info, 2)})
      Plug.Conn.send_resp(conn, 200, JSON.encode!(%{"statusCode" => 100, "body" => status("B")}))
    end)

    stub_trmnl()

    sen66 = "  - { id: SEN, name: Raumluft, type: sen66, port: /dev/ttyACM0 }\ntrmnl:"
    config = TestConfigs.plugs(String.replace(@sensors, "trmnl:", sen66))

    PollJob.perform(config: config, at: Ziwoas.Clock.now())

    assert_received {:polled_device, "A"}
    assert_received {:polled_device, "B"}
    refute_received {:polled_device, "SEN"}
    assert Enum.map(readings(), & &1.device_id) == ["A", "B"]
  end

  test "a reading that does not cast is logged and skipped" do
    stub_switchbot(fn id ->
      if id == "A", do: %{status(id) | "temperature" => "warm"}, else: status(id)
    end)

    stub_trmnl()

    assert capture_log(fn -> PollJob.perform(context()) end) =~
             "SensorPoll[A]: invalid reading"

    assert [%{device_id: "B"}] = readings()
  end

  test "a failing sensor is logged and skipped" do
    stub_switchbot(fn id -> if id == "A", do: 500, else: status(id) end)
    stub_trmnl()

    assert capture_log(fn -> PollJob.perform(context()) end) =~
             "SensorPoll[A]: {:http_status, 500}"

    assert [%{device_id: "B"}] = readings()
  end

  test "tells the subscribers each reading and the poll, then pushes the TRMNL sensor widget" do
    stub_switchbot(&status/1)
    stub_trmnl()

    assert PollJob.perform(context()) == {:ok, :sent}

    now = Ziwoas.Clock.now()

    assert {:messages,
            [
              {:reading, %Reading{device_id: "A"}},
              {:reading, %Reading{device_id: "B"}},
              {:polled, ^now},
              {:pushed, "example.test", "/sensors", body}
            ]} = mailbox()

    assert %{"merge_variables" => %{"room" => "Wohnzimmer", "values" => %{"co2" => 600}}} =
             JSON.decode!(body)
  end

  test "a failed push keeps neither the readings nor the pages back" do
    stub_switchbot(&status/1)
    Req.Test.stub(Push, &Req.Test.transport_error(&1, :econnrefused))

    assert capture_log(fn ->
             assert {:error, %Req.TransportError{}} = PollJob.perform(context())
           end) =~ "TRMNL sensor push errored"

    assert length(readings()) == 2
    assert_received {:polled, _}
  end

  defp mailbox do
    send(self(), :end)
    {:messages, collect([])}
  end

  defp collect(acc) do
    receive do
      :end -> Enum.reverse(acc)
      message -> collect([message | acc])
    end
  end
end
