require "date"

class DailyEnergySummaryBuilder
  def initialize(plugs:, timezone:)
    @roster    = Plugs::Roster.wrap(plugs)
    @zone      = ActiveSupport::TimeZone[timezone]
  end

  def build(date_s)
    midnight = Date.parse(date_s).in_time_zone(@zone)
    rows     = Plugs::Sample5min.where(bucket_ts: midnight.to_i...(midnight + 1.day).to_i).to_a

    produced_wh, consumed_wh = metered_energy_wh(rows)

    {
      produced_wh:      produced_wh,
      consumed_wh:      consumed_wh,
      self_consumed_wh: PowerSeries.from_5min(rows, plugs: @roster)
                                   .self_consumed_wh(produced_wh: produced_wh, consumed_wh: consumed_wh)
    }
  end

  private

  def metered_energy_wh(rows)
    produced_wh = 0.0
    consumed_wh = 0.0

    rows.each do |row|
      case @roster.role_of(row.plug_id)
      when :producer then produced_wh += row.energy_delta_wh
      when :consumer then consumed_wh += row.energy_delta_wh
      end
    end

    [ produced_wh, consumed_wh ]
  end
end
