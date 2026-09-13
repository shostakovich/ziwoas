module SunCalendar
  class Builder
    WATTS_PER_KILOWATT = 1000.0
    MAX_STEP = 50

    def initialize(location:, producer_ids: [])
      @location = location
      @zone = location.timezone
      @producer_ids = producer_ids.to_a
    end

    def latest_year
      Solakon::PvHour.maximum(:started_at)&.in_time_zone(@zone)&.year || Time.current.in_time_zone(@zone).year
    end

    def build(year)
      range = year_range(year)
      pv = pv_points(range)
      seam = seam_date(pv)
      plug = plug_points(range, seam)
      weather = weather_records(range)
      irradiance = weather_points(weather, &:solar_w_per_m2)
      cloud = weather_points(weather, &:cloud_cover)

      strips = {
        pv: strip(:pv, "PV-Leistung", "W", :amber, plug + pv),
        irradiance: strip(:irradiance, "Einstrahlung", "W/m²", :blue, irradiance),
        cloud: Strip.new(key: :cloud, title: "Bewölkung", unit: "%", ramp: :grey, max: 100.0, values: cells(cloud))
      }
      days = days(year, plug + pv, weather_points(weather, &:solar), cloud)
      lines = SunLines.new(location: @location).build(year)

      Year.new(
        year: year,
        days: days,
        hours: hour_range(strips.values, lines),
        strips: strips,
        max_kwh: days.filter_map(&:pv_kwh).max,
        lines: lines,
        seam: plug.any? ? seam : nil
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

    def seam_date(pv) = pv.first&.first&.to_date

    def plug_points(range, seam)
      return [] if @producer_ids.empty?

      buckets = Plugs::Sample5min
                .where(plug_id: @producer_ids, bucket_ts: range.begin.to_i...range.end.to_i)
                .pluck(:bucket_ts, :energy_delta_wh)

      totals = buckets.each_with_object(Hash.new(0.0)) do |(bucket_ts, energy_wh), out|
        time = Time.at(bucket_ts).in_time_zone(@zone)
        next if seam && time.to_date >= seam

        out[time.beginning_of_hour] += energy_wh
      end

      totals.sort_by(&:first)
    end

    def weather_records(range)
      WeatherRecord.historic
                   .for_location(@location)
                   .where(timestamp: range)
                   .order(:timestamp)
                   .to_a
    end

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
