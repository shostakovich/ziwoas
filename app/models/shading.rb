module Shading
  Hour = Data.define(:time, :pv_w, :irradiance_w_per_m2, :panels, :azimuth, :elevation) do
    def ratio = irradiance_w_per_m2.nil? || irradiance_w_per_m2.zero? ? nil : pv_w / irradiance_w_per_m2
    def date = time.to_date
    def positioned? = !elevation.nil?
  end

  Bin = Data.define(:azimuth, :elevation, :share, :hours, :first_hour, :last_hour)

  Dot = Data.define(:hour, :azimuth, :elevation)
  Path = Data.define(:label, :points, :dots)

  # Points are [hour, watts]; an unmeasured hour is absent, not zero.
  Curve = Data.define(:key, :points) do
    def empty? = points.empty?
    def max = points.map(&:last).max
  end

  module Curves
    def curve(key) = curves.find { |candidate| candidate.key == key }
    def hours = curves.flat_map { |curve| curve.points.map(&:first) }
    def max = curves.reject(&:empty?).map(&:max).max
  end

  Profile = Data.define(:month, :days, :curves) { include Curves }

  Panels = Data.define(:curves, :days, :since) do
    include Curves
    def empty? = curves.all?(&:empty?)
  end

  Map = Data.define(:bins, :paths, :bin_size)

  # extend self, not module_function: the two read the same from outside, but
  # module_function copies the body to the singleton, and a mutation of the
  # instance method never reaches the copy the callers use.
  extend self

  # The inverter reports through the night as well; keeping those zeros would
  # squeeze the day into the middle of the picture.
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

  Report = Data.define(:map, :profiles, :panels) do
    def empty? = map.bins.empty? && profiles.empty?
  end
end
