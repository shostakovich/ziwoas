module SwitchRules
  # Writes an Einzelschaltung: one rule, no group. The mirror of SaveWindow,
  # minus everything the pair needs.
  class SaveSingle
    def self.call(...) = new(...).call

    # +attrs+ is the output of SwitchRules::Contracts::Single. +rule+ is nil for
    # a new Einzelschaltung and the existing record when editing.
    def initialize(plug_id:, attrs:, rule: nil)
      @plug_id = plug_id
      @attrs   = attrs
      @rule    = rule
    end

    def call
      rule = @rule || SwitchRule.new
      rule.assign_attributes(
        plug_id:   @plug_id,
        action:    @attrs[:action],
        at_minute: SwitchRule.minutes_from(@attrs[:at_minute_time]),
        days:      @attrs[:days]
      )
      rule.save!
      rule
    end
  end
end
