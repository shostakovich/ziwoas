module Solakon
  module Control
    # What the household is drawing, as far as the plugs can tell: the live
    # measured sum, which may be absent, and the guaranteed floor, which is
    # always a number — 0.0 when nothing was measured at all.
    class Load < Dry::Struct
      attribute :current_w, Types::MeasuredWatt
      attribute :floor_w, Types::Watt

      def effective_w
        current_w.nil? ? floor_w : current_w
      end
    end
  end
end
