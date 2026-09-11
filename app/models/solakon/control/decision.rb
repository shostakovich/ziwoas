module Solakon
  module Control
    # What one tick decided: the mode it is in, the target in watts it wants
    # written, and whether it is trimming towards slight charging. Only a
    # decision the inverter actually accepted is worth remembering.
    Decision = Struct.new(:state, :target_w, :trim, keyword_init: true)
  end
end
