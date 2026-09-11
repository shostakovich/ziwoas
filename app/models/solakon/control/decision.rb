module Solakon
  module Control
    # What one tick decided: the mode it is in, the target in watts it wants
    # written, and whether it is trimming towards slight charging. Only a
    # decision the inverter actually accepted is worth remembering.
    class Decision < Dry::Struct
      attribute :state, Types::DecisionState
      attribute :target_w, Types::TargetW
      attribute :trim, Types::Strict::Bool
    end
  end
end
