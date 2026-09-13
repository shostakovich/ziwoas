class Ramp
  STOPS = {
    amber: %w[#fff8e1 #ffe9a8 #ffd166 #f7b733 #f59f00 #d97a00 #a85300],
    blue:  %w[#eef4fb #cde2fb #9ec5f4 #6da7ec #3987e5 #256abf #184f95],
    grey:  %w[#f8f9fa #e9ecef #ced4da #adb5bd #868e96 #495057 #343a40],
    diverging: %w[#256abf #6da7ec #cde2fb #f0efec #ffe9a8 #f7b733 #d97a00]
  }.freeze

  def self.fetch(name) = new(STOPS.fetch(name))

  def initialize(stops)
    @stops = stops
  end

  def color(fraction)
    position = fraction.clamp(0.0, 1.0) * (@stops.length - 1)
    index = [ position.floor, @stops.length - 2 ].min
    mix(@stops[index], @stops[index + 1], position - index)
  end

  def css_gradient = "linear-gradient(90deg, #{@stops.join(', ')})"

  private

  def mix(from, to, share)
    channels = rgb(from).zip(rgb(to)).map { |a, b| (a + (b - a) * share).round }
    format("#%02x%02x%02x", *channels)
  end

  def rgb(hex) = [ 1, 3, 5 ].map { |offset| hex[offset, 2].to_i(16) }
end
