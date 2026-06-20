# The household-load inputs the controller needs, in one place. current_w is the
# live measured sum (nil when no fresh sample); floor_w is the export-safe 24h
# minimum; night_base_w is the expected overnight base load.
LoadEstimate = Struct.new(:current_w, :floor_w, :night_base_w, keyword_init: true) do
  def effective_w
    (current_w || floor_w).to_f
  end
end
