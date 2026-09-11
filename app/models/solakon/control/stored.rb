module Solakon
  module Control
    # What the row remembers from the last tick: the decision that was actually
    # written and when it was written. The "when" matters because the inverter
    # drops remote control on its own once its watchdog runs out — whether the
    # target still stands is the tick's judgement, not the row's.
    class Stored < Dry::Struct
      attribute :decision_state, Types::DecisionState
      attribute :target_w, Types::TargetW
      attribute :trim, Types::Strict::Bool
      attribute :at, Types::Strict::Time

      def decision = Decision.new(state: decision_state, target_w: target_w, trim: trim)
    end
  end
end
