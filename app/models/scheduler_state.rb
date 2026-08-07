# One row per plug: how far the schedule tick has walked for it. Kept per plug
# so that a failed switch command only makes its own plug retry, instead of
# holding back every plug that already switched successfully.
#
# A missing row is not a special case — the job's Karenz bounds the lookback
# either way, so a plug that has never ticked looks exactly like one returning
# from an outage.
class SchedulerState < ApplicationRecord
  def self.last_tick_at(plug_id)
    find_by(plug_id: plug_id)&.last_tick_at
  end

  def self.advance!(plug_id, time)
    find_or_initialize_by(plug_id: plug_id).update!(last_tick_at: time)
  end
end
