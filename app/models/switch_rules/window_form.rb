module SwitchRules
  # What the Zeitfenster form partial renders from. A contract is not an
  # ActiveModel, so +form_with model:+ is out; this is the one object that new,
  # a failed create, edit and a failed update all hand to the same partial —
  # fields in, errors out.
  class WindowForm < Data.define(:group_id, :on_at_time, :off_at_time, :days, :errors)
    def initialize(group_id: nil, on_at_time: nil, off_at_time: nil, days: [], errors: [])
      super
    end

    # An existing window is addressed by its group, never by a rule id.
    def self.for_group(group_id, on:, off:, errors: [])
      new(group_id: group_id, on_at_time: on.at_minute_time,
          # The on rule carries the weekdays a human typed; the off rule's are
          # the same set, shifted a day forward when the window runs past
          # midnight. Undoing the shift is a matter of not reading them.
          off_at_time: off.at_minute_time, days: on.days, errors: errors)
    end

    def persisted? = !group_id.nil?
    def id         = group_id
  end
end
