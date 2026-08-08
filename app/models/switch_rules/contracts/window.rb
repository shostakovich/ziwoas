module SwitchRules
  module Contracts
    # The Zeitfenster form: two times and one set of weekdays. What comes out is
    # what SwitchRules::SaveWindow needs — the day shift past midnight is the
    # service's job, because it is a property of how the pair is stored, not of
    # what the human typed.
    class Window < Dry::Validation::Contract
      params do
        required(:on_at_time).maybe(:string)
        required(:off_at_time).maybe(:string)
        required(:days).value(:array).each(:integer)
      end

      rule(:on_at_time) do
        key.failure(MESSAGES[:time]) unless SwitchRule.minutes_from(value)
      end

      rule(:off_at_time) do
        key.failure(MESSAGES[:time]) unless SwitchRule.minutes_from(value)
      end

      # A window whose two times are equal has no duration; the successor of the
      # old on_and_off_differ validation.
      rule(:off_at_time) do
        on  = SwitchRule.minutes_from(values[:on_at_time])
        off = SwitchRule.minutes_from(value)
        key.failure(MESSAGES[:same]) if on && off && on == off
      end

      rule(:days) do
        key.failure(MESSAGES[:days]) unless Contracts.weekdays?(value)
      end
    end
  end
end
