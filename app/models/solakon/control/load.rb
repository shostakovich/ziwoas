module Solakon
  module Control
    # What the household is drawing, as far as the plugs can tell: the live
    # measured sum and the guaranteed floor to fall back on when there is none.
    class Load < Dry::Struct
      attribute :current_w, Types::Watt
      attribute :floor_w, Types::Watt

      def effective_w
        current_w.nil? ? floor_w.to_f : current_w.to_f
      end
    end
  end
end
