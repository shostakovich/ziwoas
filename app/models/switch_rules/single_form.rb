module SwitchRules
  # The Einzelschaltung counterpart of WindowForm: one time, one direction, and
  # the rule id once it exists.
  class SingleForm < Data.define(:id, :at_minute_time, :action, :days, :errors)
    def initialize(id: nil, at_minute_time: nil, action: "off", days: [], errors: [])
      super
    end

    def self.for_rule(rule, errors: [])
      new(id: rule.id, at_minute_time: rule.at_minute_time, action: rule.action,
          days: rule.days, errors: errors)
    end

    def persisted? = !id.nil?
  end
end
