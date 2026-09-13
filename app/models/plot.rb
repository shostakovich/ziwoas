# The frame the four sun charts are drawn in: a viewBox with margins and the
# two linear scales that put a pair of values onto it.
#
# The y domain's beginning lies at the foot of the plot, so hours that run
# downwards are a reversed range rather than a special case. Geometry leaves
# the frame rounded to one decimal, but `x` and `y` stay raw: a caller that
# goes on calculating with a coordinate would otherwise round twice.
class Plot
  Tick = Data.define(:value, :at)

  Rect = Data.define(:x, :y, :width, :height)

  # Whole numbers stay whole, so the markup carries no trailing zeros.
  def self.number(value)
    rounded = value.round(1)
    rounded == rounded.to_i ? rounded.to_i : rounded
  end

  def self.round_up(value, to:) = (value.to_f / to).ceil * to

  def self.round_down(value, to:) = (value.to_f / to).floor * to

  def initialize(width:, height:, margins:, x:, y:)
    @width = width
    @height = height
    @margins = margins
    @x_domain = x
    @y_domain = y
  end

  def view_box = "0 0 #{number(@width)} #{number(@height)}"

  def left = number(x_from)

  def right = number(x_to)

  def top = number(y_to)

  def bottom = number(y_from)

  def box = Rect.new(x: left, y: top, width: number(x_to - x_from), height: number(plot_height))

  def x(value) = x_from + share(value, @x_domain) * (x_to - x_from)

  def y(value) = y_from + share(value, @y_domain) * (y_to - y_from)

  def number(value) = self.class.number(value)

  def x_ticks(values) = values.map { |value| Tick.new(value: value, at: number(x(value))) }

  def y_ticks(values) = values.map { |value| Tick.new(value: value, at: number(y(value))) }

  def line(points) = points.map { |value, measure| "#{number(x(value))},#{number(y(measure))}" }.join(" ")

  # One line per unbroken run: a step in the x values wider than `gap` is a
  # stretch nobody measured, and a single line would bridge it with a shape no
  # data ever took. A repeated value is no step at all and stays inside its run.
  def polylines(points, gap: 1) = runs(points, gap).map { |run| line(run) }

  def areas(points, gap: 1)
    foot = @y_domain.begin

    runs(points, gap).map do |run|
      line([ [ run.first.first, foot ], *run, [ run.last.first, foot ] ])
    end
  end

  def columns(values)
    values.map do |value|
      from = x(value)
      to = [ x(value + 1), x_to ].min

      Rect.new(x: number(from), y: top, width: number(to - from), height: number(plot_height))
    end
  end

  def rect(x_range, y_range, inset: 0)
    xs = [ x(x_range.begin), x(x_range.end) ]
    ys = [ y(y_range.begin), y(y_range.end) ]

    Rect.new(x: number(xs.min), y: number(ys.min),
             width: number(xs.max - xs.min - inset), height: number(ys.max - ys.min - inset))
  end

  private

  def x_from = @margins.fetch(:left)

  def x_to = @width - @margins.fetch(:right)

  def y_from = @height - @margins.fetch(:bottom)

  def y_to = @margins.fetch(:top)

  def plot_height = y_from - y_to

  # A domain of a single value — one hour measured, or none — would divide by
  # zero; it sits at the beginning of its axis instead.
  def share(value, domain)
    span = domain.end - domain.begin

    (value - domain.begin) / (span.zero? ? 1.0 : span.to_f)
  end

  def runs(points, gap)
    points.slice_when { |(previous, _), (value, _)| value - previous > gap }.to_a
  end
end
