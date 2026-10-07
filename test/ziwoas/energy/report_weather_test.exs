defmodule Ziwoas.Energy.ReportWeatherTest do
  use Ziwoas.DataCase

  alias Ziwoas.Energy.ReportWeather, as: WeatherLoader
  alias Ziwoas.{Location, Repo}
  alias Ziwoas.Weather.Record

  defp location(timezone \\ "Europe/Berlin"), do: Location.new(timezone, lat: 48.15, lon: 11.26)

  defp historic!(ts, attrs) do
    defaults = %{kind: :historic, timestamp: usec(ts), lat: 48.15, lon: 11.26}
    Repo.insert!(struct!(Record, Map.merge(defaults, Map.new(attrs))))
  end

  defp unix(ts), do: DateTime.to_unix(ts)

  test "daily aggregates solar and resolves dominant icon per local day" do
    historic!(~U[2026-05-01 06:00:00Z], solar: 0.10, icon: "clear-day", daytime: "day")
    historic!(~U[2026-05-01 12:00:00Z], solar: 0.50, icon: "partly-cloudy-day", daytime: "day")
    historic!(~U[2026-05-01 18:00:00Z], solar: 0.05, icon: "rain", daytime: "day")
    historic!(~U[2026-05-01 22:00:00Z], solar: 0.00, icon: "clear-night", daytime: "night")

    daily = WeatherLoader.daily(location(), ~D[2026-05-01], ~D[2026-05-01])

    assert Map.keys(daily) == [~D[2026-05-01]]
    assert_in_delta daily[~D[2026-05-01]].solar_kwh_per_m2, 0.65, 0.001
    # rain dominates day-only severity vs clear / partly-cloudy
    assert daily[~D[2026-05-01]].daytime == "day"
    assert daily[~D[2026-05-01]].icon == "rain"
  end

  test "daily skips days without records" do
    historic!(~U[2026-05-01 12:00:00Z], solar: 0.4, icon: "clear-day", daytime: "day")

    assert Map.keys(WeatherLoader.daily(location(), ~D[2026-04-30], ~D[2026-05-02])) == [
             ~D[2026-05-01]
           ]
  end

  test "hourly returns one entry per historic record in range" do
    historic!(~U[2026-05-01 10:00:00Z], solar: 0.40, icon: "clear-day", daytime: "day")
    historic!(~U[2026-05-01 11:00:00Z], solar: 0.55, icon: "clear-day", daytime: "day")

    hourly = WeatherLoader.hourly(location(), ~D[2026-05-01], ~D[2026-05-01])

    assert length(hourly) == 2
    assert hd(hourly).ts == unix(~U[2026-05-01 10:00:00Z])
    assert_in_delta hd(hourly).solar_w_per_m2, 400.0, 1.0e-9
    assert {hd(hourly).icon, hd(hourly).daytime} == {"clear-day", "day"}
  end

  test "a location without coordinates has no weather to report" do
    historic!(~U[2026-05-01 12:00:00Z], solar: 0.4, icon: "clear-day", daytime: "day")
    unlocated = Location.new("Europe/Berlin")

    assert WeatherLoader.daily(unlocated, ~D[2026-05-01], ~D[2026-05-01]) == %{}
    assert WeatherLoader.hourly(unlocated, ~D[2026-05-01], ~D[2026-05-01]) == []
  end

  test "reads the day off the location's own clock" do
    historic!(~U[2026-04-30 23:00:00Z], solar: 0.2, icon: "clear-day", daytime: "day")

    assert WeatherLoader.hourly(location("UTC"), ~D[2026-05-01], ~D[2026-05-01]) == []
  end

  test "daily groups by the configured timezone" do
    historic!(~U[2026-05-01 02:00:00Z], solar: 0.2, icon: "clear-day", daytime: "day")

    assert Map.keys(
             WeatherLoader.daily(location("America/New_York"), ~D[2026-04-30], ~D[2026-05-01])
           ) ==
             [~D[2026-04-30]]
  end

  test "historic range boundaries use the configured timezone" do
    historic!(~U[2026-05-01 03:00:00Z], solar: 0.2, icon: "clear-day", daytime: "day")

    assert WeatherLoader.hourly(location("America/New_York"), ~D[2026-05-01], ~D[2026-05-01]) ==
             []
  end

  test "the day's icon comes only from daytime records when some exist" do
    historic!(~U[2026-05-01 12:00:00Z], solar: 0.3, icon: "clear-day", daytime: "day")
    historic!(~U[2026-05-01 19:00:00Z], solar: 0.0, icon: "thunderstorm", daytime: "night")

    day = WeatherLoader.daily(location(), ~D[2026-05-01], ~D[2026-05-01])[~D[2026-05-01]]

    assert day.icon == "clear"
    assert day.daytime == "day"
  end

  test "the day's icon falls back to all records when none are marked daytime" do
    historic!(~U[2026-05-01 19:00:00Z], solar: 0.0, icon: "clear-night", daytime: "night")

    assert WeatherLoader.daily(location(), ~D[2026-05-01], ~D[2026-05-01])[~D[2026-05-01]].icon ==
             "clear"
  end

  test "excludes a record exactly at the local midnight after the end date" do
    historic!(~U[2026-05-02 00:00:00Z], solar: 0.1, icon: "clear-day", daytime: "day")
    historic!(~U[2026-05-01 23:00:00Z], solar: 0.2, icon: "clear-day", daytime: "day")

    assert [%{ts: ts}] = WeatherLoader.hourly(location("UTC"), ~D[2026-05-01], ~D[2026-05-01])
    assert ts == unix(~U[2026-05-01 23:00:00Z])
  end

  test "orders hourly records chronologically regardless of insertion order" do
    historic!(~U[2026-05-01 18:00:00Z], solar: 0.05, icon: "clear-day", daytime: "day")
    historic!(~U[2026-05-01 06:00:00Z], solar: 0.10, icon: "clear-day", daytime: "day")

    assert Enum.map(WeatherLoader.hourly(location(), ~D[2026-05-01], ~D[2026-05-01]), & &1.ts) ==
             [unix(~U[2026-05-01 06:00:00Z]), unix(~U[2026-05-01 18:00:00Z])]
  end

  test "counts only historic records of this location" do
    historic!(~U[2026-05-01 10:00:00Z], solar: 0.2, icon: "clear-day", daytime: "day")
    historic!(~U[2026-05-01 11:00:00Z], kind: :forecast, solar: 0.3, daytime: "day")
    historic!(~U[2026-05-01 12:00:00Z], lat: 52.52, solar: 0.3, daytime: "day")

    assert length(WeatherLoader.hourly(location(), ~D[2026-05-01], ~D[2026-05-01])) == 1
  end

  test "solar is nil rather than zero when every record's reading is missing" do
    historic!(~U[2026-05-01 10:00:00Z], solar: nil, icon: "clear-day", daytime: "day")

    assert WeatherLoader.daily(location(), ~D[2026-05-01], ~D[2026-05-01])[~D[2026-05-01]].solar_kwh_per_m2 ==
             nil
  end

  test "rounds the daily solar total to three decimals" do
    historic!(~U[2026-05-01 10:00:00Z], solar: 0.12345, icon: "clear-day", daytime: "day")
    historic!(~U[2026-05-02 10:00:00Z], solar: 0.0005, icon: "clear-day", daytime: "day")

    daily = WeatherLoader.daily(location(), ~D[2026-05-01], ~D[2026-05-02])

    assert daily[~D[2026-05-01]].solar_kwh_per_m2 == 0.123
    assert daily[~D[2026-05-02]].solar_kwh_per_m2 == 0.001
  end

  test "the hourly icon is the raw one, nil for none" do
    historic!(~U[2026-05-01 10:00:00Z], solar: 0.3, icon: "clear-day", daytime: "day")
    historic!(~U[2026-05-01 11:00:00Z], solar: 0.3, icon: nil, daytime: "day")

    assert Enum.map(WeatherLoader.hourly(location(), ~D[2026-05-01], ~D[2026-05-01]), & &1.icon) ==
             ["clear-day", nil]
  end
end
