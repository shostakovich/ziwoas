require "sun_calc"

module Shading
  # Reads every PV hour ever aggregated, joins the station's irradiance onto it
  # and places it where the sun stood. The scale everything else hangs on is the
  # best hour the array ever had: the ratio of its PV power to the irradiance of
  # the same hour. It is read from the data, never configured, so a new module
  # or a cleaned panel recalibrates the page by itself.
  class Builder
    # Below this the sky is too dim for a ratio to say anything about the array.
    CALIBRATION_MIN_IRRADIANCE_W_PER_M2 = 300
    # "The best hour" as the 95th percentile rather than the single maximum: one
    # hour with an underreported irradiance would otherwise set the scale for
    # every field of the sky.
    BEST_HOUR_PERCENTILE = 0.95
    # The sun position of the hour's middle stands for the whole hour.
    MIDDLE_OF_HOUR = 30.minutes

    def initialize(timezone:, lat: nil, lon: nil)
      @zone = ActiveSupport::TimeZone[timezone]
      @lat = lat
      @lon = lon
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
        position = position(row.started_at)
        Hour.new(
          time: row.started_at.in_time_zone(@zone),
          pv_w: row.pv_power_w,
          irradiance_w_per_m2: irradiance[row.started_at.to_i],
          panels: [ row.pv1_power_w, row.pv2_power_w, row.pv3_power_w, row.pv4_power_w ],
          azimuth: position&.azimuth,
          elevation: position&.elevation
        )
      end
    end

    # Only the hours the inverter also reported can ever meet a PV hour, so the
    # station's whole history never has to be read.
    def irradiance_by_time(from, to)
      return {} if @lat.nil? || @lon.nil? || from.nil?

      WeatherRecord.historic
                   .for_location(@lat, @lon)
                   .where(timestamp: from..to)
                   .each_with_object({}) do |record, out|
        value = record.solar_w_per_m2
        out[record.timestamp.to_i] = value unless value.nil?
      end
    end

    def position(time)
      return nil if @lat.nil? || @lon.nil?

      SunCalc.position(time: time + MIDDLE_OF_HOUR, lat: @lat, lon: @lon)
    end

    def best_ratio(hours)
      ratios = hours.filter_map do |hour|
        hour.ratio if hour.irradiance_w_per_m2.to_f >= CALIBRATION_MIN_IRRADIANCE_W_PER_M2
      end
      return nil if ratios.empty?

      # An array that produced nothing under a bright sky has no best hour:
      # zero is not a scale, and everything measured against it is undefined.
      best = ratios.sort[(ratios.length * BEST_HOUR_PERCENTILE).floor]
      best if best.positive?
    end

    # The sun takes the same way every year, so the current one stands in for
    # however many years of hours the map holds.
    def paths
      SunPaths.new(zone: @zone.name, lat: @lat, lon: @lon).build(Time.current.in_time_zone(@zone).year)
    end
  end
end
