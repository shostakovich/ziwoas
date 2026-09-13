require "tzinfo"

# Loads weather context for the energy report. Operates on `historic`
# WeatherRecords for a given lat/lon and exposes per-day and per-hour
# aggregates suited for chart overlays.
#
#   loader = WeatherReportLoader.new(location: config.location)
#   loader.daily(start_date, end_date)   # => { "2026-05-01" => { solar_kwh_per_m2:, asset_name:, alt: }, ... }
#   loader.hourly(start_date, end_date)  # => [{ ts:, solar_w_per_m2:, asset_name:, alt: }, ...]
class WeatherReportLoader
  def initialize(location:)
    @location = location
    @zone = location.timezone
  end

  # Returns a Hash keyed by ISO date string with per-day weather summary.
  # Days without any historic records are omitted.
  def daily(start_date, end_date)
    records = historic_records_in_range(start_date, end_date)
    grouped = records.group_by { |r| local_date(r.timestamp) }

    grouped.each_with_object({}) do |(date, day_records), out|
      out[date.to_s] = {
        solar_kwh_per_m2: day_solar_kwh(day_records),
        asset_name:       day_asset_name(day_records),
        alt:              day_alt(day_records)
      }
    end
  end

  # Returns an Array of hourly points (one per local hour with data) for
  # the inclusive date range. Each point: { ts:, solar_w_per_m2:,
  # asset_name:, alt: }. `ts` is a UTC unix timestamp at the start of the
  # source's hour bucket.
  def hourly(start_date, end_date)
    records = historic_records_in_range(start_date, end_date)
    records.map do |r|
      {
        ts:              r.timestamp.to_i,
        solar_w_per_m2:  r.solar_w_per_m2,
        asset_name:      r.asset_name,
        alt:             r.icon.to_s
      }
    end
  end

  private

  def historic_records_in_range(start_date, end_date)
    start_ts = local_midnight(start_date)
    end_ts   = local_midnight(end_date + 1)
    WeatherRecord.historic
                 .for_location(@location)
                 .where(timestamp: start_ts...end_ts)
                 .order(:timestamp)
                 .to_a
  end

  def day_solar_kwh(records)
    values = records.filter_map(&:solar)
    return nil if values.empty?
    # `historic` solar is kWh/m² accumulated per 60-min source period —
    # summing yields the daily total in kWh/m².
    values.sum.round(3)
  end

  def day_asset_name(records)
    day_segment(records).asset_name
  end

  def day_alt(records)
    day_segment(records).dominant_icon
  end

  def day_segment(records)
    daytime_records = records.select { |r| r.daytime == "day" }
    pool = daytime_records.any? ? daytime_records : records
    WeatherSegment.new(label: "day", hour_range: 0..23, records: pool)
  end

  def local_date(timestamp)
    timestamp.in_time_zone(@zone).to_date
  end

  def local_midnight(date)
    date.in_time_zone(@zone)
  end
end
