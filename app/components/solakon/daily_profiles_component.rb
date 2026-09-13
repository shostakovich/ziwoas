module Solakon
  # Small multiples, one per month: what the array made over the day, what the
  # measured irradiance promised, and what a cloudless sky would have offered.
  # All months share one pair of axes, so the shape of June can be held against
  # the shape of September.
  class DailyProfilesComponent < ApplicationComponent
    WIDTH = 300
    HEIGHT = 150
    # Wide enough for a four-digit watt label once the phone's media query
    # enlarges the type inside the viewBox.
    LEFT = 40
    # Room at the right edge for the last hour's label.
    RIGHT = 14
    TOP = 10
    BOTTOM = 22
    GRID_STEP_W = 100
    MAX_GRID_LINES = 3
    DENSE_HOUR_STEP = 3
    SPARSE_HOUR_STEP = 6
    KEYS = { measured: "PV gemessen", expected: "Erwartet aus Einstrahlung", theory: "Wolkenloser Himmel" }.freeze

    Series = Data.define(:key, :segments)
    Hit = Data.define(:x, :width, :title)
    Label = Data.define(:x, :y, :text)
    Multiple = Data.define(:month, :label, :days, :series, :areas, :hits)

    def initialize(profiles:)
      @profiles = profiles
    end

    def empty? = @profiles.empty?

    def view_box = "0 0 #{WIDTH} #{HEIGHT}"

    def plot_top = TOP

    def plot_height = HEIGHT - TOP - BOTTOM

    def multiples
      @profiles.map do |profile|
        Multiple.new(
          month: profile.month,
          label: MONTHS[profile.month - 1],
          days: profile.days,
          series: drawing_order.map { |key| Series.new(key: key, segments: segments(profile.curve(key))) },
          areas: areas(profile.curve(:measured)),
          hits: hits(profile)
        )
      end
    end

    def grid
      grid_step.step(max_w - 1, grid_step).map do |watts|
        Label.new(x: LEFT - 4, y: number(y(watts)), text: watts.to_s)
      end
    end

    def plot_left = LEFT

    def plot_right = WIDTH - RIGHT

    def baseline_y = number(y(0))

    def hour_labels(density)
      step = density == :sparse ? SPARSE_HOUR_STEP : DENSE_HOUR_STEP

      hours.first.step(hours.last, step).map do |hour|
        Label.new(x: number(x(hour)), y: HEIGHT - 6, text: hour.to_s)
      end
    end

    def legend = KEYS

    def note
      "Einstrahlung und wolkenloser Himmel sind mit dem Wirkungsgrad der besten Stunde auf " \
        "Anlagenleistung umgerechnet. Der Abstand zwischen der gemessenen und der erwarteten Linie " \
        "ist der Anteil, den Abschattung, Ausrichtung oder Drosselung kosten."
    end

    private

    # The measured line is drawn last so it lies over the two it is read
    # against.
    def drawing_order = KEYS.keys.reverse

    # One polyline per unbroken run of hours: an hour the station left out must
    # not be bridged by a line nobody measured.
    def segments(curve)
      runs(curve).map { |run| run.map { |hour, watts| "#{number(x(hour))},#{number(y(watts))}" }.join(" ") }
    end

    def runs(curve)
      curve.points.slice_when { |(previous, _), (hour, _)| hour - previous > 1 }.to_a
    end

    # One filled shape per unbroken run, for the same reason the line is split:
    # a fill across a gap would show unmeasured hours as measured.
    def areas(curve)
      runs(curve).map do |run|
        corners = [ [ run.first.first, 0 ], *run, [ run.last.first, 0 ] ]
        corners.map { |hour, watts| "#{number(x(hour))},#{number(y(watts))}" }.join(" ")
      end
    end

    def hits(profile)
      values = KEYS.keys.to_h { |key| [ key, profile.curve(key).points.to_h ] }

      profile.hours.uniq.sort.map do |hour|
        width = [ x(hour + 1), plot_right ].min - x(hour)
        Hit.new(x: number(x(hour)), width: number(width), title: title_for(profile, hour, values))
      end
    end

    def title_for(profile, hour, values)
      [
        "#{MONTHS[profile.month - 1]} · #{hour}–#{hour + 1} Uhr",
        *KEYS.map { |key, label| "#{label} #{watts(values.fetch(key)[hour])}" }
      ].join(" · ")
    end

    def watts(value) = value.nil? ? "keine Daten" : "Ø #{value.round} W"

    def hours
      @hours ||= begin
        all = @profiles.flat_map(&:hours)
        all.empty? ? (0..0) : all.min..all.max
      end
    end

    def max_w
      @max_w ||= begin
        highest = @profiles.filter_map(&:max).max.to_f
        [ (highest / GRID_STEP_W).ceil * GRID_STEP_W, GRID_STEP_W ].max
      end
    end

    def grid_step = (max_w / MAX_GRID_LINES.to_f / GRID_STEP_W).ceil * GRID_STEP_W

    def span = [ hours.last - hours.first, 1 ].max

    def x(hour) = LEFT + (hour - hours.first) / span.to_f * (WIDTH - LEFT - RIGHT)

    # to_f: the grid's watts are whole numbers, and integer division
    # would put every line on the axis.
    def y(watts) = TOP + (1 - watts.to_f / max_w) * (HEIGHT - TOP - BOTTOM)
  end
end
