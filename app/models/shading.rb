# Where the garden stands between sun and panels: the yield ratio placed at the
# sun position it was measured at, the day's shape per month against what the
# sky offered, and the four panels beside each other.
module Shading
  # One hour seen from both sides: the inverter's mean PV power and the
  # station's irradiance, at the sun position of the hour's middle. Irradiance
  # and panels may be missing — the hour still carries its PV power.
  Hour = Data.define(:time, :pv_w, :irradiance_w_per_m2, :panels, :azimuth, :elevation) do
    def ratio = irradiance_w_per_m2.nil? || irradiance_w_per_m2.zero? ? nil : pv_w / irradiance_w_per_m2
    def date = time.to_date
    # False while no location is configured: then nobody knows where the sun
    # stood, and everything drawn over the sky stays away.
    def positioned? = !elevation.nil?
  end

  # One field of the sky: the median yield of the hours that fell into it,
  # as a share of the best hour ever observed.
  Bin = Data.define(:azimuth, :elevation, :share, :hours, :first_hour, :last_hour)

  # The sun's way across the sky on one date, with a dot every few hours.
  Dot = Data.define(:hour, :azimuth, :elevation)
  Path = Data.define(:label, :points, :dots)

  # A curve over the hours of the day; points are [hour, watts] and skip the
  # hours that were not measured. What the curve is called is the page's word,
  # not the model's.
  Curve = Data.define(:key, :points) do
    def empty? = points.empty?
    def max = points.map(&:last).max
  end

  module Curves
    def curve(key) = curves.find { |candidate| candidate.key == key }
    def hours = curves.flat_map { |curve| curve.points.map(&:first) }
    def max = curves.reject(&:empty?).map(&:max).max
  end

  # One month of the day's shape: measured, expected from irradiance, and the
  # cloudless sky, over the same hours.
  Profile = Data.define(:month, :days, :curves) { include Curves }

  # The four panels over the day, counted only over days on which all four
  # delivered.
  Panels = Data.define(:curves, :days, :since) do
    include Curves
    def empty? = curves.all?(&:empty?)
  end

  Map = Data.define(:bins, :paths, :bin_size)

  # extend self, not module_function: the two read the same from outside, but
  # module_function copies the body to the singleton, and a mutation of the
  # instance method never reaches the copy the callers use.
  extend self

  # The hours worth drawing: from the first hour something was produced or
  # offered to the last. The inverter reports through the night as well, and a
  # row of zeros on either side would squeeze the day into the middle of the
  # picture.
  def daylight(curves)
    hours = curves.flat_map { |curve| curve.points.reject { |_hour, value| value.zero? }.map(&:first) }
    hours.min..hours.max unless hours.empty?
  end

  def trim(curves)
    window = daylight(curves)

    curves.map do |curve|
      Curve.new(key: curve.key, points: window.nil? ? [] : curve.points.select { |hour, _| window.cover?(hour) })
    end
  end

  # The whole section: the map of sun positions, the months, the panels.
  Report = Data.define(:map, :profiles, :panels) do
    def empty? = map.bins.empty? && profiles.empty?
  end
end
