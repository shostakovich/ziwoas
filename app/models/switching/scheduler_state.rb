# One row per plug: how far the schedule tick has walked for it. Per plug, so
# that a failed switch command only makes its own plug retry instead of holding
# back the ones that already switched.
module Switching
  class SchedulerState < ApplicationRecord
    self.table_name = "scheduler_states"
    def self.last_tick_at(plug_id)
      find_by(plug_id: plug_id)&.last_tick_at
    end

    def self.advance!(plug_id, time)
      find_or_initialize_by(plug_id: plug_id).update!(last_tick_at: time)
    end
  end
end
