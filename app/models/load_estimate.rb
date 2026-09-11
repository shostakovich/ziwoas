# The household-load inputs the controller needs. current_w is the live measured
# sum (nil when no fresh sample); floor_w is the export-safe 24h minimum.
LoadEstimate = Struct.new(:current_w, :floor_w, keyword_init: true) do
  def effective_w
    current_w.nil? ? floor_w.to_f : current_w.to_f
  end
end
