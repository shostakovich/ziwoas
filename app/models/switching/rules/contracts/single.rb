module Switching
  module Rules
    module Contracts
      # The Einzelschaltung form: one time, one direction, one set of weekdays.
      # The direction is explicit here — that is the whole point of the form.
      class Single < Dry::Validation::Contract
        params do
          required(:at_minute_time).maybe(:string)
          required(:action).maybe(:string)
          required(:days).value(:array).each(:integer)
        end

        rule(:at_minute_time) do
          key.failure(MESSAGES[:time]) unless Switching::Rule.minutes_from(value)
        end

        rule(:action) do
          key.failure(MESSAGES[:action]) unless Switching::Rule::ACTIONS.include?(value)
        end

        rule(:days) do
          key.failure(MESSAGES[:days]) unless Contracts.weekdays?(value)
        end
      end
    end
  end
end
