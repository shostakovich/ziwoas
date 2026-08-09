module SwitchRules
  # Writes a Zeitfenster: two rules, one group, one transaction. This service
  # carries the invariant "a group holds exactly two rules" — the partial unique
  # index on (group_id, action) forbids a second on rule but not a missing off
  # rule, and SQLite would need a trigger for the rest.
  class SaveWindow
    DAYS_PER_WEEK = 7

    def self.call(...) = new(...).call

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
        # An off time before the on time means the window runs past midnight, so
        # the off rule carries the weekdays shifted one day forward: "Mo–Fr 22:00
        # an / 06:00 aus" is stored as on Mo–Fr, off Di–Sa. The shift happens
        # once, here, never again at runtime. SwitchRules::WindowConversion
        # repeats it for the migration on purpose — a change to the form must not
        # reach historical data.
        write(group_id, "off", off_minute, past_midnight?(on_minute, off_minute) ? next_day(days) : days)
      end

      group_id
    end

    private

    # +to_i+ only keeps an unparseable time from raising here, so that the Active
    # Record validation gets the last word and the transaction rolls back.
    def past_midnight?(on_minute, off_minute) = off_minute.to_i < on_minute.to_i

    def next_day(days) = days.map { |d| d % DAYS_PER_WEEK + 1 }.sort

    def write(group_id, action, at_minute, days)
      rule = SwitchRule.find_or_initialize_by(group_id: group_id, action: action)
      rule.assign_attributes(plug_id: @plug_id, at_minute: at_minute, days: days)
      rule.save!
    end
  end
end
