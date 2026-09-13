module Solakon
  # Small multiples, one per month. All months share one pair of axes, so the
  # shape of June can be held against the shape of September.
  class DailyProfilesComponent < ApplicationComponent
    WIDTH = 300
    HEIGHT = 150
    MARGINS = {
      top: 10,
      # Room at the right edge for the last hour's label.
      right: 14,
      bottom: 22,
      # Wide enough for a four-digit watt label once the phone's media query
      # enlarges the type inside the viewBox.
      left: 40
    }.freeze
    GRID_STEP_W = 100
    MAX_GRID_LINES = 3
    DENSE_HOUR_STEP = 3
    SPARSE_HOUR_STEP = 6
    VALUE_LABEL_GAP = 4
    VALUE_LABEL_DROP = 3.5
    HOUR_LABEL_Y = HEIGHT - 6
    KEYS = { measured: "PV gemessen", expected: "Erwartet aus Einstrahlung", theory: "Wolkenloser Himmel" }.freeze

    Series = Data.define(:key, :segments)
    Hit = Data.define(:rect, :title)
    Label = Data.define(:x, :y, :text)
    Multiple = Data.define(:month, :label, :days, :series, :areas, :hits)

    def initialize(profiles:)
      @profiles = profiles
    end

    def empty? = @profiles.empty?

    def plot
      @plot ||= Plot.new(width: WIDTH, height: HEIGHT, margins: MARGINS, x: hours, y: 0..max_w)
    end

    def multiples
      @profiles.map do |profile|
        Multiple.new(
          month: profile.month,
          label: MONTHS[profile.month - 1],
          days: profile.days,
          series: drawing_order.map { |key| Series.new(key: key, segments: segments(profile, key)) },
          areas: plot.areas(profile.curve(:measured).points),
          hits: hits(profile)
        )
      end
    end

    def grid_lines = grid.map(&:at)

    def value_labels
      grid.map do |tick|
        Label.new(x: plot.left - VALUE_LABEL_GAP, y: number(tick.at + VALUE_LABEL_DROP), text: tick.value.to_s)
      end
    end

    def hour_labels(density)
      step = density == :sparse ? SPARSE_HOUR_STEP : DENSE_HOUR_STEP

      plot.x_ticks(hours.step(step)).map { |tick| Label.new(x: tick.at, y: HOUR_LABEL_Y, text: tick.value.to_s) }
    end

    def legend = KEYS

    def note
      "Einstrahlung und wolkenloser Himmel sind mit dem Wirkungsgrad der besten Stunde auf " \
        "Anlagenleistung umgerechnet. Der Abstand zwischen der gemessenen und der erwarteten Linie " \
        "ist der Anteil, den Abschattung, Ausrichtung oder Drosselung kosten."
    end

    private

    delegate :number, to: :plot, private: true

    # The measured line is drawn last so it lies over the two it is read
    # against.
    def drawing_order = KEYS.keys.reverse

    def segments(profile, key) = plot.polylines(profile.curve(key).points)

    def grid = plot.y_ticks(grid_step.step(max_w - 1, grid_step))

    def hits(profile)
      values = KEYS.keys.to_h { |key| [ key, profile.curve(key).points.to_h ] }
      measured = profile.hours.uniq.sort

      measured.zip(plot.columns(measured)).map do |hour, column|
        Hit.new(rect: column, title: title_for(profile, hour, values))
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
      @max_w ||= [ Plot.round_up(@profiles.filter_map(&:max).max.to_f, to: GRID_STEP_W), GRID_STEP_W ].max
    end

    def grid_step = Plot.round_up(max_w / MAX_GRID_LINES.to_f, to: GRID_STEP_W)
  end
end
