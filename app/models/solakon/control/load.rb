module Solakon
  module Control
    class Load < Dry::Struct
      attribute :current_w, Types::MeasuredWatt
      attribute :floor_w, Types::Watt

      def effective_w
        current_w.nil? ? floor_w : current_w
      end
    end
  end
end
