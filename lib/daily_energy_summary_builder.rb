require "date"
require "tzinfo"

class DailyEnergySummaryBuilder
  def initialize(plugs:, timezone:)
    @roster    = PlugRoster.wrap(plugs)
    @timezone  = timezone.is_a?(TZInfo::Timezone) ? timezone : TZInfo::Timezone.get(timezone)
  end

  def build(date_s)
    start_ts = @timezone.local_to_utc(Time.parse("#{date_s} 00:00:00")).to_i
    rows     = Sample5min.where(bucket_ts: start_ts...(start_ts + 86_400)).to_a

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
