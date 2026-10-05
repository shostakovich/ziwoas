module Solakon
  # All months share one pair of axes, so June's shape can be held against September's.
  class DailyProfilesComponent < ApplicationComponent
    include ChartParts

    WIDTH = 300
    HEIGHT = 160
    MARGINS = {
      top: 10,
      right: 14,
      bottom: 30,
      # Wide enough for a four-digit watt label at the phone's size.
      left: 48
    }.freeze
    NICE_STEPS_W = [ 100, 200, 250, 500, 1000 ].freeze
    MAX_GRID_STEPS = 3
    DENSE_HOUR_STEP = 3
    SPARSE_HOUR_STEP = 6
    VALUE_LABEL_GAP = 4
    HOUR_LABEL_GAP = 8
    KEYS = { measured: "PV gemessen", expected: "Erwartet aus Einstrahlung", theory: "Wolkenloser Himmel" }.freeze

    Series = Data.define(:key, :segments)
    Multiple = Data.define(:month, :label, :days, :partial, :series, :areas, :hits) do
      def partial? = partial
    end

    def initialize(profiles:)
      @profiles = profiles
    end

    def empty? = @profiles.empty?

    def plot
      @plot ||= Plot.new(width: WIDTH, height: HEIGHT, margins: MARGINS, x: hours, y: 0..scale.top)
    end

    def multiples
      @profiles.map do |profile|
        Multiple.new(
          month: profile.month,
          label: MONTHS[profile.month - 1],
          days: profile.days,
          partial: profile.days < full_month_days(profile.month),
          series: drawing_order.map { |key| Series.new(key: key, segments: segments(profile, key)) },
          areas: plot.areas(profile.curve(:measured).points),
          hits: hits(profile)
        )
      end
    end

    def grid_lines = plot.grid_lines(grid_values)

    def value_labels = plot.value_labels(grid_values, gap: VALUE_LABEL_GAP)

    def hour_labels(density)
      step = density == :sparse ? SPARSE_HOUR_STEP : DENSE_HOUR_STEP

      plot.x_ticks(hours.select { |hour| (hour % step).zero? })
          .map { |tick| Plot::Label.new(x: tick.at, y: plot.bottom + HOUR_LABEL_GAP, text: format("%02d", tick.value)) }
    end

    def legend = KEYS

    def subtitle = "Mittlere Leistung je Stunde in W"

    def note
      "Einstrahlung und wolkenloser Himmel sind mit dem Wirkungsgrad der besten Stunde auf " \
        "Anlagenleistung umgerechnet. Der Abstand zwischen der gemessenen und der erwarteten Linie " \
        "ist der Anteil, den Abschattung, Ausrichtung oder Drosselung kosten."
    end

    private

    delegate :number, to: :plot, private: true

    # The measured line last, over the two it is read against.
    def drawing_order = KEYS.keys.reverse

    def segments(profile, key) = plot.polylines(profile.curve(key).points)

    def grid_values = 0.step(scale.top, scale.step)

    # A common year's length, so a month counts as whole whatever the leap day.
    def full_month_days(month) = Date.new(2001, month, -1).day

    def hits(profile)
      values = KEYS.keys.to_h { |key| [ key, profile.curve(key).points.to_h ] }
      measured = profile.hours.uniq.sort

      plot.hits(measured, measured.map { |hour| title_for(profile, hour, values) })
    end

    def title_for(profile, hour, values)
      [
        "#{MONTHS[profile.month - 1]} · #{hour}–#{hour + 1} Uhr",
        *KEYS.map { |key, label| "#{label} #{watts(values.fetch(key)[hour])}" }
      ].join(" · ")
    end

    def watts(value) = value.nil? ? "keine Daten" : "Ø #{GermanNumber.format(value, unit: "W")}"

    def hours = @hours ||= Plot.extent(@profiles.flat_map(&:hours))

    def scale
      @scale ||= Plot.nice_scale(@profiles.filter_map(&:max).max.to_f, steps: NICE_STEPS_W, max_steps: MAX_GRID_STEPS)
    end
  end
end
