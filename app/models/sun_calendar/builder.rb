module SunCalendar
  # Reads one calendar year out of the PV hours and the historic weather and
  # lays it out as the sun calendar's three strips and its daily bars. Every
  # source is flattened to [local time, value] pairs first, so the layout knows
  # nothing about where a number came from.
  class Builder
    WATTS_PER_KILOWATT = 1000.0
    # Strip maxima snap to this step so the legend reads as a round number.
    MAX_STEP = 50

    def initialize(timezone:, lat: nil, lon: nil)
      @zone = ActiveSupport::TimeZone[timezone]
      @lat = lat
      @lon = lon
    end

    def build(year)
      range = year_range(year)
      pv = pv_points(range)
      weather = weather_records(range)
      irradiance = weather_points(weather, &:solar_w_per_m2)
      cloud = weather_points(weather, &:cloud_cover)

      strips = {
        pv: strip(:pv, "PV-Leistung", "W", :amber, pv),
        irradiance: strip(:irradiance, "Einstrahlung", "W/m²", :blue, irradiance),
        cloud: Strip.new(key: :cloud, title: "Bewölkung", unit: "%", ramp: :grey, max: 100.0, values: cells(cloud))
      }
      days = days(year, pv, weather_points(weather, &:solar), cloud)
      lines = SunLines.new(zone: @zone.name, lat: @lat, lon: @lon).build(year)

      Year.new(
        year: year,
        days: days,
        hours: hour_range(strips.values, lines),
        strips: strips,
        max_kwh: days.filter_map(&:pv_kwh).max,
        lines: lines
      )
    end

    private

    def year_range(year)
      Date.new(year, 1, 1).in_time_zone(@zone)...Date.new(year + 1, 1, 1).in_time_zone(@zone)
    end

    def pv_points(range)
      Solakon::PvHour.where(started_at: range)
                     .order(:started_at)
                     .pluck(:started_at, :pv_power_w)
                     .map { |time, watts| [ time.in_time_zone(@zone), watts ] }
    end

    def weather_records(range)
      return [] if @lat.nil? || @lon.nil?

      WeatherRecord.historic
                   .for_location(@lat, @lon)
                   .where(timestamp: range)
                   .order(:timestamp)
                   .to_a
    end

    # [local time, value] pairs, skipping what the station left unmeasured.
    def weather_points(records)
      records.filter_map do |record|
        value = yield(record)
        next if value.nil?

        [ record.timestamp.in_time_zone(@zone), value ]
      end
    end

    # One cell per local clock hour. The autumn clock change repeats an hour;
    # its second reading wins the cell, while the day's totals keep both.
    def cells(points)
      points.to_h { |time, value| [ [ time.yday, time.hour ], value ] }
    end

    def strip(key, title, unit, ramp, points)
      values = cells(points)
      Strip.new(key: key, title: title, unit: unit, ramp: ramp, max: rounded_max(values), values: values)
    end

    def rounded_max(values)
      [ (values.values.max.to_f / MAX_STEP).ceil * MAX_STEP, MAX_STEP ].max.to_f
    end

    # Wide enough for every measured hour and for the sun lines, so neither
    # ends up drawn outside the strip.
    def hour_range(strips, lines)
      hours = strips.flat_map { |strip| strip.values.keys.map(&:last) }
      events = lines.rise + lines.set
      [ BASE_HOURS.first, *hours, *events.map { |_doy, hour| hour.floor } ].min..
        [ BASE_HOURS.last, *hours, *events.map { |_doy, hour| hour.ceil } ].max
    end

    def days(year, pv, solar, cloud)
      kwh = sum_by_day(pv).transform_values { |watt_hours| watt_hours / WATTS_PER_KILOWATT }
      irradiance = sum_by_day(solar)
      cloud_avg = average_by_day(cloud)

      (Date.new(year, 1, 1)..Date.new(year, 12, 31)).map do |date|
        Day.new(
          doy: date.yday,
          date: date,
          pv_kwh: kwh[date.yday],
          irradiance_kwh_per_m2: irradiance[date.yday],
          cloud_avg: cloud_avg[date.yday]
        )
      end
    end

    def sum_by_day(points) = by_day(points).transform_values(&:sum)

    def average_by_day(points)
      by_day(points).transform_values { |values| values.sum / values.length.to_f }
    end

    def by_day(points)
      points.each_with_object({}) { |(time, value), out| (out[time.yday] ||= []) << value }
    end
  end
end
