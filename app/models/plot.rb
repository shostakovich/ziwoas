# The frame a chart is drawn in: a viewBox with margins around the drawing
# area, and the two linear scales that put a pair of values onto it. The four
# sun charts differ in their boxes and in what they draw, not in this geometry.
#
# The y domain's beginning lies at the foot of the plot, so a watt scale reads
# 0..max and the calendar's hours, which run downwards, read as a reversed
# range. Whatever the frame hands out as geometry carries one decimal; `x` and
# `y` stay raw, because a caller that goes on calculating with a coordinate
# would otherwise pile one rounding on the next.
class Plot
  # A gridline or an axis label: the value it stands for and the coordinate it
  # sits at.
  Tick = Data.define(:value, :at)

  Rect = Data.define(:x, :y, :width, :height)

  # SVG coordinates with one decimal: finer than any column these charts draw,
  # and whole numbers stay whole so the markup carries no trailing zeros.
  def self.number(value)
    rounded = value.round(1)
    rounded == rounded.to_i ? rounded.to_i : rounded
  end

  # An axis maximum and its grid step are read, not measured: rounded to whole
  # hundreds of watts or tens of degrees they land on numbers a person would
  # say out loud.
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

  # The drawing area itself, for the ground a chart paints under its data.
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

  # One filled shape per run, closed down to the foot of the y scale, for the
  # same reason the line is broken: a fill across a gap would show unmeasured
  # values as measured.
  def areas(points, gap: 1)
    foot = @y_domain.begin

    runs(points, gap).map do |run|
      line([ [ run.first.first, foot ], *run, [ run.last.first, foot ] ])
    end
  end

  # A full-height column per value, reaching to the next one and stopping at
  # the right edge: the invisible boxes a tooltip hangs on.
  def columns(values)
    values.map do |value|
      from = x(value)
      to = [ x(value + 1), x_to ].min

      Rect.new(x: number(from), y: top, width: number(to - from), height: number(plot_height))
    end
  end

  # The box two ranges cut out of the plot, whichever way the scales run.
  # `inset` takes a hair off the width and the height, so neighbouring boxes
  # stay apart.
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
