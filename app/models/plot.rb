# Geometry is rounded to one decimal; `x` and `y` stay raw, so callers calculating on don't round twice.
class Plot
  Tick = Data.define(:value, :at)

  Rect = Data.define(:x, :y, :width, :height)

  Hit = Data.define(:rect, :title)

  Label = Data.define(:x, :y, :text, :zero) do
    def initialize(x:, y:, text:, zero: false) = super
  end

  Scale = Data.define(:step, :top)

  def self.number(value)
    rounded = value.round(1)
    rounded == rounded.to_i ? rounded.to_i : rounded
  end

  def self.round_up(value, to:) = (value.to_f / to).ceil * to

  def self.round_down(value, to:) = (value.to_f / to).floor * to

  def self.nice_scale(peak, steps:, max_steps:)
    step = steps.find { |candidate| peak <= candidate * max_steps } ||
           round_up(peak.fdiv(max_steps), to: steps.last)

    Scale.new(step: step, top: [ round_up(peak, to: step), step ].max)
  end

  def self.extent(values) = values.empty? ? (0..0) : Range.new(*values.minmax)

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

  def x(value) = x_from + share(value, @x_domain) * (x_to - x_from)

  def y(value) = y_from + share(value, @y_domain) * (y_to - y_from)

  def number(value) = self.class.number(value)

  def x_ticks(values) = values.map { |value| Tick.new(value: value, at: number(x(value))) }

  def y_ticks(values) = values.map { |value| Tick.new(value: value, at: number(y(value))) }

  def grid_lines(values) = y_ticks(values).reject { |tick| tick.value.zero? }.map(&:at)

  def value_labels(values, gap:)
    y_ticks(values).map { |tick| Label.new(x: left - gap, y: tick.at, text: tick.value.to_s, zero: tick.value.zero?) }
  end

  def line(points) = points.map { |value, measure| "#{number(x(value))},#{number(y(measure))}" }.join(" ")

  # A step wider than `gap` was never measured; one line would bridge it with a shape no data took.
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

  def hits(values, titles) = columns(values).zip(titles).map { |rect, title| Hit.new(rect: rect, title: title) }

  # Edges are rounded before the size: rounding corner and size apart leaves hairline slits.
  def rect(x_range, y_range, inset: 0)
    xs = [ x(x_range.begin), x(x_range.end) ].map { |value| number(value) }
    ys = [ y(y_range.begin), y(y_range.end) ].map { |value| number(value) }

    Rect.new(x: xs.min, y: ys.min, width: number(xs.max - xs.min - inset), height: number(ys.max - ys.min - inset))
  end

  private

  def x_from = @margins.fetch(:left)

  def x_to = @width - @margins.fetch(:right)

  def y_from = @height - @margins.fetch(:bottom)

  def y_to = @margins.fetch(:top)

  def plot_height = y_from - y_to

  def share(value, domain)
    span = domain.end - domain.begin

    (value - domain.begin) / (span.zero? ? 1.0 : span.to_f)
  end

  def runs(points, gap)
    points.slice_when { |(previous, _), (value, _)| value - previous > gap }.to_a
  end
end
