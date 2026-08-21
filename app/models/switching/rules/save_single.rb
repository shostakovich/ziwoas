module Switching
  module Rules
    # Writes an Einzelschaltung: one rule, no group. The mirror of SaveWindow,
    # minus everything the pair needs.
    class SaveSingle
      def self.call(...) = new(...).call

      def initialize(plug_id:, attrs:, rule: nil)
        @plug_id = plug_id
        @attrs   = attrs
        @rule    = rule
      end

      def call
        rule = @rule || Switching::Rule.new
        rule.assign_attributes(
          plug_id:   @plug_id,
          action:    @attrs[:action],
          at_minute: Switching::Rule.minutes_from(@attrs[:at_minute_time]),
          days:      @attrs[:days]
        )
        rule.save!
        rule
      end
    end
  end
end
