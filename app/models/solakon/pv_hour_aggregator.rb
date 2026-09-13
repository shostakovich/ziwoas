module Solakon
  # Condenses the 30-second readings and the 2-minute snapshots into one PvHour
  # per clock hour. Days are local calendar days, so the clock-change days come
  # out with 23 and 25 hours.
  class PvHourAggregator
    HOUR_START_SQL = "CAST(strftime('%s', taken_at) AS INTEGER) / 3600 * 3600".freeze
    PANEL_COLUMNS = Snapshot::PANELS.map { |idx| :"pv#{idx}_power_w" }.freeze
    NO_PANELS = PANEL_COLUMNS.to_h { |column| [ column, nil ] }.freeze

    def aggregate_day(date)
      day = date.in_time_zone.beginning_of_day
      range = day...(day + 1.day)
      panels = panel_means(range)

      rows = reading_means(range).filter_map do |epoch, pv_power_w, reading_count|
        next if reading_count < PvHour::MIN_READINGS

        { started_at: Time.zone.at(epoch), pv_power_w: pv_power_w, reading_count: reading_count }
          .merge(panels.fetch(epoch, NO_PANELS))
      end

      PvHour.transaction do
        PvHour.where(started_at: range).delete_all
        PvHour.insert_all(rows) if rows.any?
      end
    end

    # Every finished day since the first reading that has no hour yet.
    def run_once(today: Date.current)
      first_reading_at = Reading.minimum(:taken_at)
      return if first_reading_at.nil?

      filled = PvHour.pluck(:started_at).to_set { |started_at| started_at.in_time_zone.to_date }
      (first_reading_at.in_time_zone.to_date..(today - 1)).each do |date|
        aggregate_day(date) unless filled.include?(date)
      end
    end

    private

    def reading_means(range)
      Reading.where(taken_at: range)
             .group(Arel.sql(HOUR_START_SQL))
             .pluck(Arel.sql(HOUR_START_SQL), Arel.sql("AVG(pv_power_w)"), Arel.sql("COUNT(*)"))
    end

    def panel_means(range)
      Snapshot.where(taken_at: range)
              .group(Arel.sql(HOUR_START_SQL))
              .pluck(Arel.sql(HOUR_START_SQL), *PANEL_COLUMNS.map { |column| Arel.sql("AVG(#{column})") })
              .to_h { |epoch, *means| [ epoch, PANEL_COLUMNS.zip(means).to_h ] }
    end
  end
end
