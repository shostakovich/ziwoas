module SwitchRules
  # Writes a Zeitfenster: two rules, one group, one transaction. This service
  # carries the invariant "a group holds exactly two rules" — the database only
  # keeps the partial unique index on (group_id, action), which forbids a second
  # on rule but not a missing off rule, and SQLite would need a trigger for the
  # rest.
  #
  # Editing updates the two rules in place. Stable ids carry Edge#rule_id, the
  # row's DOM id, and the case "saved while the tick is running"; a window can
  # never change which half points which way anyway.
  class SaveWindow
    ISO_DAYS = 7

    def self.call(...) = new(...).call

    # +attrs+ is the output of SwitchRules::Contracts::Window. +group_id+ is nil
    # for a new window and the existing group when editing.
    def initialize(plug_id:, attrs:, group_id: nil)
      @plug_id  = plug_id
      @attrs    = attrs
      @group_id = group_id
    end

    # Returns the group id, so the caller can name the row it just wrote.
    def call
      on_minute  = SwitchRule.minutes_from(@attrs[:on_at_time])
      off_minute = SwitchRule.minutes_from(@attrs[:off_at_time])
      days       = @attrs[:days]
      group_id   = @group_id || SecureRandom.uuid

      SwitchRule.transaction do
        write(group_id, "on",  on_minute,  days)
        # An off time before the on time means the window runs past midnight:
        # the off rule then carries the weekdays shifted one day forward, so
        # "Mo–Fr 22:00 an / 06:00 aus" is stored as on Mo–Fr and off Di–Sa. The
        # shift happens once, here, and never again at runtime. (The migration
        # does the same in SwitchRules::WindowConversion; the two stay apart on
        # purpose, so a change to the form cannot reach the historical data.)
        write(group_id, "off", off_minute, past_midnight?(on_minute, off_minute) ? next_day(days) : days)
      end

      group_id
    end

    private

    # The times arrive from the contract and are always parseable; +to_i+ only
    # keeps an unparseable one from raising here, so that the Active Record
    # validation gets to have the last word — and the transaction rolls back.
    def past_midnight?(on_minute, off_minute) = off_minute.to_i < on_minute.to_i

    def next_day(days) = days.map { |d| d % ISO_DAYS + 1 }.sort

    def write(group_id, action, at_minute, days)
      rule = SwitchRule.find_or_initialize_by(group_id: group_id, action: action)
      rule.assign_attributes(plug_id: @plug_id, at_minute: at_minute, days: days)
      rule.save!
    end
  end
end
