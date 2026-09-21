module Shading
  class Builder
    CALIBRATION_MIN_IRRADIANCE_W_PER_M2 = 300
    # "The best hour" as the 95th percentile rather than the single maximum: one
    # hour with an underreported irradiance would otherwise set the scale for
    # every field of the sky.
    BEST_HOUR_PERCENTILE = 0.95
    MIDDLE_OF_HOUR = 30.minutes

    def initialize(location:)
      @location = location
    end

    def build
      hours = hours()
      best_ratio = best_ratio(hours)

      Report.new(
        map: YieldMap.new(best_ratio: best_ratio).build(hours, paths),
        profiles: DailyProfiles.new(best_ratio: best_ratio).build(hours),
        panels: PanelCurves.new.build(hours)
      )
    end

    private

    def hours
      rows = Solakon::PvHour.order(:started_at).to_a
      irradiance = irradiance_by_time(rows.first&.started_at, rows.last&.started_at)

      rows.map do |row|
        position = @location.sun.position(row.started_at + MIDDLE_OF_HOUR)
        Hour.new(
          time: row.started_at.in_time_zone(zone),
          pv_w: row.pv_power_w,
          irradiance_w_per_m2: irradiance[row.started_at.to_i],
          panels: [ row.pv1_power_w, row.pv2_power_w, row.pv3_power_w, row.pv4_power_w ],
          azimuth: position&.azimuth,
          elevation: position&.elevation
        )
      end
    end

    # Irradiance keyed by the start of the hour it was summed over. The station
    # stamps a record with the end of its hour, so the hour that starts with
    # the last PV hour is stamped one hour later than that.
    def irradiance_by_time(from, to)
      return {} if from.nil?

      WeatherRecord.historic
                   .for_location(@location)
                   .where(timestamp: (from + 1.hour)..(to + 1.hour))
                   .each_with_object({}) do |record, out|
        value = record.solar_w_per_m2
        out[record.period_started_at.to_i] = value unless value.nil?
      end
    end

    def best_ratio(hours)
      ratios = hours.filter_map do |hour|
        hour.ratio if hour.irradiance_w_per_m2.to_f >= CALIBRATION_MIN_IRRADIANCE_W_PER_M2
      end
      return nil if ratios.empty?

      best = ratios.sort[(ratios.length * BEST_HOUR_PERCENTILE).floor]
      best if best.positive?
    end

    # The sun takes the same way every year, so the current one stands in for
    # however many years of hours the map holds.
    def paths = SunPaths.new(location: @location).build(Time.current.in_time_zone(zone).year)

    def zone = @location.timezone
  end
end
