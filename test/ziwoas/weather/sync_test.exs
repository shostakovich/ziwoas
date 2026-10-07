defmodule Ziwoas.Weather.SyncTest do
  use Ziwoas.DataCase

  import Ecto.Query

  alias Ziwoas.{Location, Repo}
  alias Ziwoas.Plugs.DailyTotal
  alias Ziwoas.Weather.{BrightskyClient, Record, Sync}

  @location %Location{timezone: "Europe/Berlin", lat: 52.52, lon: 13.405}
  @elsewhere %Location{timezone: "Europe/Berlin", lat: 48.14, lon: 11.58}

  setup do
    Ziwoas.TestClock.freeze("2026-05-04T10:00:00+02:00")
    :ok
  end

  defp hour(timestamp, extra \\ %{}),
    do:
      Map.merge(
        %{
          "timestamp" => timestamp,
          "source_id" => 7003,
          "icon" => "cloudy",
          "temperature" => 12.5
        },
        extra
      )

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

  defp records, do: Repo.all(from r in Record, order_by: [r.kind, r.lat, r.timestamp])

  defp insert!(kind, timestamp, location \\ @location, attrs \\ %{}) do
    %{kind: kind, lat: location.lat, lon: location.lon, timestamp: timestamp, daytime: "day"}
    |> Map.merge(attrs)
    |> Record.changeset()
    |> Repo.insert!()
  end

  describe "sync_today/2" do
    test "a known hour is updated in place, not duplicated" do
      stub_brightsky(%{"2026-05-04" => [hour("2026-05-04T10:00:00+00:00")]})
      Sync.sync_today(@location, ~D[2026-05-04])
      [first] = records()

      Ziwoas.TestClock.freeze("2026-05-04T11:00:00+02:00")

      stub_brightsky(%{
        "2026-05-04" => [
          hour("2026-05-04T10:00:00+00:00", %{"temperature" => 14.0, "icon" => "rain"}),
          hour("2026-05-04T11:00:00+00:00")
        ]
      })

      Sync.sync_today(@location, ~D[2026-05-04])

      assert [updated, added] = records()
      assert updated.id == first.id
      assert {updated.temperature, updated.icon} == {14.0, "rain"}
      assert updated.inserted_at == first.inserted_at
      assert DateTime.after?(updated.updated_at, first.updated_at)
      assert added.timestamp == ~U[2026-05-04 11:00:00.000000Z]
    end

    test "a value that disappears is cleared on update" do
      stub_brightsky(%{"2026-05-04" => [hour("2026-05-04T10:00:00+00:00")]})
      Sync.sync_today(@location, ~D[2026-05-04])

      stub_brightsky(%{
        "2026-05-04" => [hour("2026-05-04T10:00:00+00:00", %{"temperature" => nil})]
      })

      Sync.sync_today(@location, ~D[2026-05-04])

      assert [%Record{temperature: nil}] = records()
    end

    test "the same hour at another location is a row of its own" do
      stub_brightsky(%{"2026-05-04" => [hour("2026-05-04T10:00:00+00:00")]})

      Sync.sync_today(@location, ~D[2026-05-04])
      Sync.sync_today(@elsewhere, ~D[2026-05-04])

      assert [%{lat: 48.14}, %{lat: 52.52}] = records()
    end

    test "values are typed: integers as floats, whole floats rounded" do
      stub_brightsky(%{
        "2026-05-04" => [
          hour("2026-05-04T10:00:00+00:00", %{
            "temperature" => 12,
            "cloud_cover" => 62.6,
            "precipitation_probability" => 40
          })
        ]
      })

      Sync.sync_today(@location, ~D[2026-05-04])

      assert [
               %Record{
                 kind: "forecast",
                 temperature: 12.0,
                 cloud_cover: 63,
                 precipitation_probability: 40,
                 source_id: 7003
               }
             ] = records()
    end

    test "past the end of the range writes nothing" do
      stub_brightsky(%{})
      assert Sync.sync_today(@location, ~D[2026-05-04]) == :ok
      assert records() == []
    end
  end

  describe "sync_current/1" do
    test "replaces the location's current row and leaves other locations alone" do
      insert!("current", ~U[2026-05-04 07:50:00.000000Z], @elsewhere)
      insert!("current", ~U[2026-05-04 07:50:00.000000Z])

      stub_brightsky(%{"current" => hour("2026-05-04T08:00:00+00:00")})

      assert %Record{kind: "current", timestamp: ~U[2026-05-04 08:00:00.000000Z]} =
               Sync.sync_current(@location)

      assert [
               %{lat: 48.14, timestamp: ~U[2026-05-04 07:50:00.000000Z]},
               %{lat: 52.52, timestamp: ~U[2026-05-04 08:00:00.000000Z]}
             ] = records()
    end

    test "a failing Bright Sky keeps the old current row" do
      insert!("current", ~U[2026-05-04 07:50:00.000000Z])
      Req.Test.stub(BrightskyClient, &Plug.Conn.send_resp(&1, 400, ""))

      assert_raise BrightskyClient.Error, fn -> Sync.sync_current(@location) end
      assert [%{kind: "current"}] = records()
    end
  end

  describe "sync_historic_date/2" do
    test "an observed hour replaces exactly the forecast for that hour" do
      insert!("forecast", ~U[2026-05-03 09:00:00.000000Z])
      insert!("forecast", ~U[2026-05-03 10:00:00.000000Z])
      insert!("forecast", ~U[2026-05-03 10:00:00.000000Z], @elsewhere)

      stub_brightsky(%{"2026-05-03" => [hour("2026-05-03T10:00:00+00:00")]})
      Sync.sync_historic_date(@location, ~D[2026-05-03])

      assert Enum.map(records(), &{&1.kind, &1.lat, &1.timestamp}) == [
               {"forecast", 48.14, ~U[2026-05-03 10:00:00.000000Z]},
               {"forecast", 52.52, ~U[2026-05-03 09:00:00.000000Z]},
               {"historic", 52.52, ~U[2026-05-03 10:00:00.000000Z]}
             ]
    end

    test "syncing a day twice updates its historic hours" do
      stub_brightsky(%{"2026-05-03" => [hour("2026-05-03T10:00:00+00:00")]})
      Sync.sync_historic_date(@location, ~D[2026-05-03])

      stub_brightsky(%{
        "2026-05-03" => [hour("2026-05-03T10:00:00+00:00", %{"temperature" => 9.0})]
      })

      Sync.sync_historic_date(@location, ~D[2026-05-03])

      assert [%Record{kind: "historic", temperature: 9.0}] = records()
    end
  end

  describe "sync_forecast/3" do
    test "stops at the first day without hours" do
      stub_brightsky(%{
        "2026-05-05" => [hour("2026-05-05T10:00:00+00:00")],
        "2026-05-06" => []
      })

      Sync.sync_forecast(@location, ~D[2026-05-04])

      assert_received {:asked, "2026-05-05"}
      assert_received {:asked, "2026-05-06"}
      refute_received {:asked, "2026-05-07"}
      assert [%{kind: "forecast"}] = records()
    end

    test "asks for at most max_days" do
      days = for d <- 5..9, into: %{}, do: {"2026-05-0#{d}", [hour("2026-05-0#{d}T10:00:00Z")]}
      stub_brightsky(days)

      Sync.sync_forecast(@location, ~D[2026-05-04], 2)

      assert length(records()) == 2
      refute_received {:asked, "2026-05-07"}
    end
  end

  describe "backfill_historic_from_daily_totals/1" do
    # 2026-05-01 in Berlin (CEST) runs from 2026-04-30T22:00Z to 2026-05-01T22:00Z.
    defp historic_hours!(first_utc, count) do
      for i <- 0..(count - 1),
          do: insert!("historic", DateTime.add(first_utc, i * 3600, :second))
    end

    setup do
      Repo.insert!(%DailyTotal{plug_id: "bkw", date: "2026-05-01", energy_wh: 1000.0})
      stub_brightsky(%{"2026-05-01" => [hour("2026-05-01T10:00:00+00:00")]})
      :ok
    end

    test "a local day with 24 historic hours, the first at local midnight, is complete" do
      historic_hours!(~U[2026-04-30 22:00:00.000000Z], 24)

      Sync.backfill_historic_from_daily_totals(@location)

      refute_received {:asked, _}
    end

    test "an hour at the next local midnight belongs to the next day" do
      historic_hours!(~U[2026-04-30 23:00:00.000000Z], 24)

      Sync.backfill_historic_from_daily_totals(@location)

      assert_received {:asked, "2026-05-01"}
    end

    test "hours of another location do not count" do
      for i <- 0..23,
          do:
            insert!(
              "historic",
              DateTime.add(~U[2026-04-30 22:00:00.000000Z], i * 3600, :second),
              @elsewhere
            )

      Sync.backfill_historic_from_daily_totals(@location)

      assert_received {:asked, "2026-05-01"}
    end
  end
end
