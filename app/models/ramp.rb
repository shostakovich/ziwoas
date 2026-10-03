# A colour ramp whose stops are CSS colours, usually custom properties that
# solakon.css defines per theme. Colours between two stops are written as
# color-mix() so the browser resolves them, and dark mode follows by itself.
class Ramp
  STOPS = {
    amber: %w[var(--ramp-amber-0) var(--ramp-amber-1) var(--ramp-amber-2)],
    blue: %w[var(--ramp-blue-0) var(--ramp-blue-1) var(--ramp-blue-2)],
    grey: %w[var(--ramp-grey-0) var(--ramp-grey-1)],
    diverging: %w[var(--ramp-low) var(--ramp-neutral) var(--ramp-high)]
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
    percent = (share * 100).round(1)
    return from if percent.zero?
    return to if percent == 100

    "color-mix(in oklab, #{to} #{format('%g', percent)}%, #{from})"
  end
end
