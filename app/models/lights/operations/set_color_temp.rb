module Lights
  module Operations
    class SetColorTemp < Base
      def call(light:, params:, mqtt_config:)
        attrs  = step coerce { Params::ColorTemp.new(kelvin: params[:temp_k]) }
        kelvin = attrs.kelvin.clamp(light.color_temp_range)
        step via_commander { Govees::Commander.set_color_temp(light, kelvin: kelvin, mqtt_config: mqtt_config) }
        Results::NoContent.new
      end
    end
  end
end
