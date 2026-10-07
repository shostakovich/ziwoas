defmodule Ziwoas.WeatherTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Weather
  alias Ziwoas.Weather.{Day, Icon, Record, Segment}

  @zone "Europe/Berlin"

  defp at(date, hour) do
    {:ok, naive} = NaiveDateTime.new(date, Time.new!(hour, 0, 0))
    naive |> DateTime.from_naive!(@zone) |> DateTime.shift_zone!("Etc/UTC")
  end

  defp record(attrs) do
    struct!(
      %Record{kind: "forecast", lat: 52.52, lon: 13.405, icon: "clear-day", daytime: "day"},
      attrs
    )
  end

  defp day(date, records), do: %Day{date: date, records: records, zone: @zone}

  defp segment(records, hours \\ 12..17//1),
    do: %Segment{label: "Nachmittag", hours: hours, records: records}

  describe "Icon" do
    test "maps Bright Sky day, night and neutral icons" do
      assert Icon.asset_name("clear-day", "day") == "weather_clear_day.webp"
      assert Icon.asset_name("clear-night", "night") == "weather_clear_night.webp"
      assert Icon.asset_name("partly-cloudy-day", "day") == "weather_partly_cloudy_day.webp"
      assert Icon.asset_name("partly-cloudy-night", "night") == "weather_partly_cloudy_night.webp"
      assert Icon.asset_name("rain", "day") == "weather_rain_day.webp"
      assert Icon.asset_name("rain", "night") == "weather_rain_night.webp"
    end

    test "falls back for unknown icons and normalises the daytime" do
      assert Icon.asset_name("not-real", "day") == "weather_unknown_day.webp"
      assert Icon.asset_name(nil, "night") == "weather_unknown_night.webp"
      assert Icon.asset_name("rain", "morning") == "weather_rain_day.webp"
    end
  end

  describe "Record" do
    test "asset name and solar W/m² per period" do
      assert Weather.asset_name(record(icon: "partly-cloudy-night", daytime: "night")) ==
               "weather_partly_cloudy_night.webp"

      assert Weather.solar_w_per_m2(record(kind: "current", solar: 0.05)) == 300.0
      assert Weather.solar_w_per_m2(record(kind: "forecast", solar: 0.3)) == 300.0
      assert Weather.solar_w_per_m2(record(kind: "historic", solar: 0.3)) == 300.0
      assert Weather.solar_w_per_m2(record(solar: nil)) == nil
    end
  end

  describe "Day" do
    test "min/max temperature, precipitation with nil as zero, solar peak" do
      date = ~D[2026-05-06]

      d =
        day(date, [
          record(timestamp: at(date, 6), temperature: 11.0, precipitation: 0.4, solar: 0.22),
          record(timestamp: at(date, 12), temperature: 17.0, precipitation: nil, solar: 0.48),
          record(timestamp: at(date, 18), temperature: 14.0, precipitation: 1.4)
        ])

      assert {Day.temp_min(d), Day.temp_max(d)} == {11.0, 17.0}
      assert_in_delta Day.precip_sum(d), 1.8, 0.001
      assert_in_delta Day.solar_peak_w_per_m2(d), 480.0, 1.0e-9
    end

    test "no solar values, no peak; no records, Integer 0 precipitation" do
      date = ~D[2026-05-06]
      assert Day.solar_peak_w_per_m2(day(date, [record(timestamp: at(date, 12))])) == nil
      assert Day.precip_sum(day(date, [])) === 0
    end

    test "German weekday and DD.MM. labels" do
      assert Day.weekday_label(day(~D[2026-05-04], [])) == "Montag"
      assert Day.weekday_label(day(~D[2026-05-03], [])) == "Sonntag"
      assert Day.date_label(day(~D[2026-05-04], [])) == "04.05."
      assert Day.date_label(day(~D[2026-03-31], [])) == "31.03."
    end

    test "four segments in display order, by local hour" do
      date = ~D[2026-05-06]
      records = for h <- 0..23, do: record(timestamp: at(date, h), temperature: 10.0 + h)
      segments = Day.segments(day(date, records))

      assert Enum.map(segments, & &1.label) == ~w[Nacht Vormittag Nachmittag Abend]
      assert Enum.map(segments, & &1.hours) == [0..5//1, 6..11//1, 12..17//1, 18..23//1]
      assert Enum.map(segments, &length(&1.records)) == [6, 6, 6, 6]
    end

    test "a 06:00 record is Vormittag, and every segment exists without records" do
      date = ~D[2026-05-06]

      segments =
        Day.segments(day(date, [record(timestamp: at(date, 5)), record(timestamp: at(date, 6))]))

      assert Enum.map(segments, &length(&1.records)) == [1, 1, 0, 0]
      assert Enum.map(Day.segments(day(date, [])), & &1.records) == [[], [], [], []]
    end
  end

  describe "Segment" do
    test "the dominant icon is the most severe one, the earliest on a tie, unknown when empty" do
      icons = ~w[clear-day partly-cloudy-day thunderstorm clear-day rain clear-day]
      assert Segment.dominant_icon(segment(Enum.map(icons, &record(icon: &1)))) == "thunderstorm"
      assert Segment.dominant_icon(segment([])) == "unknown"

      assert Segment.dominant_icon(segment(Enum.map(~w[rain clear-day rain], &record(icon: &1)))) ==
               "rain"
    end

    test "temperatures ignore nils, precipitation counts nil as zero" do
      s =
        segment([
          record(temperature: 11.0, precipitation: 0.4),
          record(temperature: nil),
          record(temperature: 17.0, precipitation: 1.4)
        ])

      assert {Segment.temp_min(s), Segment.temp_max(s)} == {11.0, 17.0}
      assert_in_delta Segment.precip_sum(s), 1.8, 0.001
    end

    test "average solar over the records that have one" do
      assert_in_delta Segment.avg_solar_w_per_m2(
                        segment([record(solar: 0.3), record(solar: nil), record(solar: 0.5)])
                      ),
                      400.0,
                      0.001

      assert Segment.avg_solar_w_per_m2(segment([record(solar: nil)])) == nil
    end

    test "all night only with records, all of them at night" do
      assert Segment.all_night?(segment([record(daytime: "night"), record(daytime: "night")]))
      refute Segment.all_night?(segment([record(daytime: "day"), record(daytime: "night")]))
      refute Segment.all_night?(segment([]))
    end

    test "the dominant daytime and asset come from the most severe record" do
      s =
        segment([
          record(icon: "clear-day"),
          record(icon: "thunderstorm", daytime: "night"),
          record(icon: "clear-night", daytime: "night")
        ])

      assert Segment.dominant_daytime(s) == "night"

      assert Segment.asset_name(
               segment([record(icon: "clear-day"), record(icon: "thunderstorm")])
             ) == "weather_thunderstorm_day.webp"
    end

    test "complete with an hour per hour of its range" do
      assert Segment.complete?(segment(List.duplicate(record([]), 6)))
      refute Segment.complete?(segment(List.duplicate(record([]), 3)))
      refute Segment.complete?(segment([]))
    end
  end
end
