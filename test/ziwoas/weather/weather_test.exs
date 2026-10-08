defmodule Ziwoas.WeatherTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Weather
  alias Ziwoas.Weather.{Day, Record, Segment}

  @zone "Europe/Berlin"

  defp at(date, hour) do
    {:ok, naive} = NaiveDateTime.new(date, Time.new!(hour, 0, 0))
    naive |> DateTime.from_naive!(@zone) |> DateTime.shift_zone!("Etc/UTC")
  end

  defp record(attrs) do
    struct!(
      %Record{kind: :forecast, lat: 52.52, lon: 13.405, icon: "clear-day", daytime: "day"},
      attrs
    )
  end

  defp day(date, records), do: %Day{date: date, records: records, zone: @zone}

  defp segment(records, hours \\ 12..17//1),
    do: %Segment{label: :afternoon, hours: hours, records: records}

  describe "icons" do
    test "the base icon drops the daytime suffix; anything unknown is unknown" do
      assert Weather.base_icon("partly-cloudy-night") == "partly-cloudy"
      assert Weather.base_icon("rain") == "rain"
      assert Weather.base_icon("not-real") == "unknown"
      assert Weather.base_icon(nil) == "unknown"
    end

    test "the daytime comes from the icon's suffix, else from the sun" do
      berlin = Ziwoas.Location.new(@zone, lat: 52.52, lon: 13.405)
      noon = at(~D[2026-05-06], 12)
      midnight = at(~D[2026-05-06], 0)

      assert Weather.daytime_for("clear-night", noon, berlin) == "night"
      assert Weather.daytime_for("clear-day", midnight, berlin) == "day"
      assert Weather.daytime_for("rain", noon, berlin) == "day"
      assert Weather.daytime_for(nil, midnight, berlin) == "night"
    end
  end

  describe "Record" do
    test "solar W/m² per period" do
      assert Weather.solar_w_per_m2(record(kind: :current, solar: 0.05)) == 300.0
      assert Weather.solar_w_per_m2(record(kind: :forecast, solar: 0.3)) == 300.0
      assert Weather.solar_w_per_m2(record(kind: :historic, solar: 0.3)) == 300.0
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

    test "four segments in display order, by local hour" do
      date = ~D[2026-05-06]
      records = for h <- 0..23, do: record(timestamp: at(date, h), temperature: 10.0 + h)
      segments = Day.segments(day(date, records))

      assert Enum.map(segments, & &1.label) == [:night, :morning, :afternoon, :evening]
      assert Enum.map(segments, & &1.hours) == [0..5//1, 6..11//1, 12..17//1, 18..23//1]
      assert Enum.map(segments, &length(&1.records)) == [6, 6, 6, 6]
    end

    test "a 06:00 record is morning, and every segment exists without records" do
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

    test "the dominant daytime comes from the most severe record" do
      s =
        segment([
          record(icon: "clear-day"),
          record(icon: "thunderstorm", daytime: "night"),
          record(icon: "clear-night", daytime: "night")
        ])

      assert Segment.dominant_daytime(s) == "night"
    end

    test "complete with an hour per hour of its range" do
      assert Segment.complete?(segment(List.duplicate(record([]), 6)))
      refute Segment.complete?(segment(List.duplicate(record([]), 3)))
      refute Segment.complete?(segment([]))
    end
  end
end
