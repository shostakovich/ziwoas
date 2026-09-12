module Solakon
  module Control
    class Decision < Dry::Struct
      attribute :state, Types::DecisionState
      attribute :target_w, Types::TargetW
      attribute :trim, Types::Strict::Bool
    end
  end
end
