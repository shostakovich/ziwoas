module Switching
  module Rules
    # What the Zeitfenster form partial renders from. A contract is not an
    # ActiveModel, so +form_with model:+ is out; new, a failed create, edit and a
    # failed update all hand the partial this one object instead.
    class WindowForm < Data.define(:group_id, :on_at_time, :off_at_time, :days, :errors)
      def initialize(group_id: nil, on_at_time: nil, off_at_time: nil, days: [], errors: [])
        super
      end

      # +days+ comes from the on rule alone: those are the weekdays a human typed,
      # and not reading the off rule's undoes the shift past midnight.
      def self.for_group(group_id, on:, off:, errors: [])
        new(group_id: group_id, on_at_time: on.at_minute_time,
            off_at_time: off.at_minute_time, days: on.days, errors: errors)
      end

      def persisted? = !group_id.nil?
      def id         = group_id
    end
  end
end
