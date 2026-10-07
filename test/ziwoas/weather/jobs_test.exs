defmodule Ziwoas.Weather.JobsTest do
  # PubSub topics are global, hence not async.
  use Ziwoas.DataCase

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Ziwoas.Plugs.DailyTotal
  alias Ziwoas.Repo
  alias Ziwoas.Weather.{BrightskyClient, CurrentJob, ForecastJob, HistoricJob, Record, TodayJob}

  @config Ziwoas.TestConfigs.located()

  setup do
    Ziwoas.TestClock.freeze("2026-05-04T10:00:00+02:00")
    Ziwoas.Weather.subscribe()
    :ok
  end

  defp context, do: [config: @config, at: Ziwoas.Clock.now()]

  defp hour(timestamp, extra \\ %{}),
    do: Map.merge(%{"timestamp" => timestamp, "source_id" => 7003, "icon" => "cloudy"}, extra)

  # Bright Sky with `bodies` by date ("current" for the observation), 404 otherwise;
  # tells the test each date it was asked for.
  defp stub_brightsky(bodies) do
    test = self()

    Req.Test.stub(BrightskyClient, fn conn ->
      date = URI.decode_query(conn.query_string)["date"] || "current"
      send(test, {:asked, date})

      case Map.fetch(bodies, date) do
        {:ok, body} -> Plug.Conn.send_resp(conn, 200, JSON.encode!(%{"weather" => body}))
        :error -> Plug.Conn.send_resp(conn, 404, "{}")
      end
    end)
  end

  defp kinds,
    do: Repo.all(from r in Record, order_by: [r.kind, r.timestamp], select: {r.kind, r.timestamp})

  describe "CurrentJob" do
    test "keeps one current row and tells the Wetter page" do
      stub_brightsky(%{"current" => hour("2026-05-04T10:00:00+00:00")})
      CurrentJob.perform(context())
      stub_brightsky(%{"current" => hour("2026-05-04T10:15:00+00:00")})
      CurrentJob.perform(context())

      assert kinds() == [{:current, ~U[2026-05-04 10:15:00.000000Z]}]
      assert_received {:synced, ~D[2026-05-04]}
    end
  end

  test "TodayJob writes today's hours as forecast" do
    stub_brightsky(%{"2026-05-04" => [hour("2026-05-04T10:00:00+00:00")]})

    TodayJob.perform(context())

    assert_received {:asked, "2026-05-04"}
    assert kinds() == [{:forecast, ~U[2026-05-04 10:00:00.000000Z]}]
    assert_received {:synced, ~D[2026-05-04]}
  end

  test "ForecastJob fetches the days after today until the range ends" do
    stub_brightsky(%{"2026-05-05" => [hour("2026-05-05T10:00:00+00:00")]})

    ForecastJob.perform(context())

    assert_received {:asked, "2026-05-05"}
    assert_received {:asked, "2026-05-06"}
    refute_received {:asked, "2026-05-07"}
    assert kinds() == [{:forecast, ~U[2026-05-05 10:00:00.000000Z]}]
    assert_received {:synced, ~D[2026-05-04]}
  end

  test "HistoricJob replaces yesterday's forecast and backfills the days with totals" do
    Repo.insert!(%Record{
      kind: :forecast,
      lat: 52.52,
      lon: 13.405,
      timestamp: ~U[2026-05-03 10:00:00.000000Z],
      daytime: "day",
      icon: "cloudy"
    })

    Repo.insert!(%DailyTotal{plug_id: "bkw", date: "2026-05-01", energy_wh: 1000.0})

    stub_brightsky(%{
      "2026-05-03" => [hour("2026-05-03T10:00:00+00:00")],
      "2026-05-01" => [hour("2026-05-01T10:00:00+00:00")]
    })

    HistoricJob.perform(context())

    assert kinds() == [
             {:historic, ~U[2026-05-01 10:00:00.000000Z]},
             {:historic, ~U[2026-05-03 10:00:00.000000Z]}
           ]

    assert_received {:synced, ~D[2026-05-04]}
  end

  test "a Bright Sky failure is logged and fails the job before the broadcast" do
    Req.Test.stub(BrightskyClient, &Plug.Conn.send_resp(&1, 500, ""))

    log =
      capture_log(fn ->
        assert CurrentJob.perform(context()) == {:error, {:http_status, 500}}
      end)

    assert log =~ "Bright Sky sync failed: {:http_status, 500}"
    refute_received {:synced, _}
  end

  test "HistoricJob stops at a failing yesterday" do
    Repo.insert!(%DailyTotal{plug_id: "bkw", date: "2026-05-01", energy_wh: 1000.0})
    Req.Test.stub(BrightskyClient, &Plug.Conn.send_resp(&1, 400, ""))

    capture_log(fn -> assert {:error, _} = HistoricJob.perform(context()) end)

    assert kinds() == []
    refute_received {:synced, _}
  end
end
