module Switching
  module Rules
    module Contracts
      # The Zeitfenster form: two times and one set of weekdays. The day shift past
      # midnight stays with SaveWindow — it is a property of how the pair is
      # stored, not of what the human typed.
      class Window < Dry::Validation::Contract
        params do
          required(:on_at_time).maybe(:string)
          required(:off_at_time).maybe(:string)
          required(:days).value(:array).each(:integer)
        end

        rule(:on_at_time) do
          key.failure(MESSAGES[:time]) unless Switching::Rule.minutes_from(value)
        end

        rule(:off_at_time) do
          key.failure(MESSAGES[:time]) unless Switching::Rule.minutes_from(value)
        end

        rule(:off_at_time) do
          on  = Switching::Rule.minutes_from(values[:on_at_time])
          off = Switching::Rule.minutes_from(value)
          key.failure(MESSAGES[:same]) if on && off && on == off
        end

        rule(:days) do
          key.failure(MESSAGES[:days]) unless Contracts.weekdays?(value)
        end
      end
    end
  end
end
