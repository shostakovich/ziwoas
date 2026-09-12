module Solakon
  module Control
    class Stored < Dry::Struct
      attribute :decision_state, Types::DecisionState
      attribute :target_w, Types::TargetW
      attribute :trim, Types::Strict::Bool
      attribute :at, Types::Strict::Time

      def decision = Decision.new(state: decision_state, target_w: target_w, trim: trim)
    end
  end
end
