defmodule Ziwoas.Sensors.PollJobTest do
  # test/jobs/sensor_poll_job_test.rb; PubSub topics are global, hence not async.
  use Ziwoas.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Ziwoas.{Ownership, Repo, TestConfigs}
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
    - id: B
      name: Balkon
      type: outdoor_meter
  trmnl:
    sensors_webhook_url: https://example.test/sensors
  """

  setup %{repo: repo} do
    Repo.put_writer(:main, repo)
    Repo.put_writer(:shadow, repo)
    Ownership.override(%{sensor_poll: :phoenix})
    Ziwoas.Clock.freeze("2026-10-05T12:00:00.250000+02:00")
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "sensors")
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "weather")
    on_exit(&Ownership.clear_override/0)
    :ok
  end

  defp context(config \\ TestConfigs.plugs(@sensors)),
    do: %{task: :sensor_poll, mode: Ownership.mode(:sensor_poll), config: config}

  # Each device answers `status.(id)`: a body map, or an HTTP status.
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

  test "casts as Rails: an Integer temperature to Float, a Float humidity to Integer" do
    stub_switchbot(fn _id -> %{"temperature" => 21, "humidity" => 52.7, "battery" => 99.9} end)
    stub_trmnl()

    PollJob.perform(context())

    assert [%{temperature: 21.0, humidity: 52, battery_pct: 99} | _] = readings()
  end

  test "a failing sensor is logged and skipped" do
    stub_switchbot(fn id -> if id == "A", do: 500, else: status(id) end)
    stub_trmnl()

    assert capture_log(fn -> PollJob.perform(context()) end) =~ "SensorPoll[A]: HTTP 500"
    assert [%{device_id: "B"}] = readings()
  end

  test "does nothing without SwitchBot credentials" do
    Req.Test.stub(SwitchBotClient, fn _conn -> flunk("asked SwitchBot") end)

    PollJob.perform(context(TestConfigs.plugs()))

    assert readings() == []
    refute_received {:sensors_updated}
  end

  test "as owner pushes the TRMNL sensor widget, then tells the pages" do
    stub_switchbot(&status/1)
    stub_trmnl()

    PollJob.perform(context())

    assert {:messages,
            [{:pushed, "example.test", "/sensors", body}, {:sensors_updated}, {:weather_updated}]} =
             mailbox()

    assert %{"merge_variables" => %{"sensors" => [%{"id" => "A"}, %{"id" => "B"}]}} =
             JSON.decode!(body)
  end

  test "a failed push keeps neither the readings nor the pages back" do
    stub_switchbot(&status/1)
    Req.Test.stub(Push, &Req.Test.transport_error(&1, :econnrefused))

    assert capture_log(fn -> PollJob.perform(context()) end) =~ "TRMNL sensor push errored"
    assert length(readings()) == 2
    assert_received {:sensors_updated}
    assert_received {:weather_updated}
  end

  test "in shadow mode reads the sensors but pushes and broadcasts nothing" do
    Ownership.override(%{sensor_poll: :shadow})
    stub_switchbot(&status/1)
    Req.Test.stub(Push, fn _conn -> flunk("pushed to TRMNL") end)

    PollJob.perform(context())

    assert length(readings()) == 2
    refute_received {:sensors_updated}
    refute_received {:weather_updated}
  end

  # The test's mailbox before it is read: what arrived, in order.
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
