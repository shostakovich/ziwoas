module Solakon
  class PvHourAggregator
    PANEL_COLUMNS = Snapshot::PANELS.map { |idx| :"pv#{idx}_power_w" }.freeze
    NO_PANELS = PANEL_COLUMNS.index_with(nil).freeze

    def initialize(timezone:)
      @zone = timezone
    end

    def aggregate_day(date)
      day = date.in_time_zone(@zone)
      range = day...(day + 1.day)
      panels = panel_means(range, day.utc_offset)

      rows = reading_means(range, day.utc_offset).filter_map do |epoch, pv_power_w, reading_count|
        next if reading_count < PvHour::MIN_READINGS

        { started_at: @zone.at(epoch), pv_power_w: pv_power_w, reading_count: reading_count }
          .merge(panels.fetch(epoch, NO_PANELS))
      end

      PvHour.transaction do
        PvHour.where(started_at: range).delete_all
        PvHour.insert_all(rows)
      end
    end

    def run_once(today: Date.current)
      first_reading_at = Reading.minimum(:taken_at)
      return if first_reading_at.nil?

      filled = PvHour.pluck(:started_at).to_set { |started_at| started_at.in_time_zone(@zone).to_date }
      (first_reading_at.in_time_zone(@zone).to_date..(today - 1)).each do |date|
        aggregate_day(date) unless filled.include?(date)
      end
    end

    private

    def reading_means(range, utc_offset)
      hour_start = hour_start_sql(utc_offset)
      Reading.where(taken_at: range)
             .group(hour_start)
             .pluck(hour_start, Arel.sql("AVG(pv_power_w)"), Arel.sql("COUNT(*)"))
    end

    def panel_means(range, utc_offset)
      hour_start = hour_start_sql(utc_offset)
      Snapshot.where(taken_at: range)
              .group(hour_start)
              .pluck(hour_start, *PANEL_COLUMNS.map { |column| Arel.sql("AVG(#{column})") })
              .to_h { |epoch, *means| [ epoch, PANEL_COLUMNS.zip(means).to_h ] }
    end

    # Epoch of the local clock hour a row falls into. Shifting by the day's UTC
    # offset keeps the buckets on local hours in zones like Asia/Kolkata, whose
    # offset is not a whole hour.
    def hour_start_sql(utc_offset)
      Arel.sql(PvHour.sanitize_sql_array(
        [ "(CAST(strftime('%s', taken_at) AS INTEGER) + ?) / 3600 * 3600 - ?", utc_offset, utc_offset ]
      ))
    end
  end
end
