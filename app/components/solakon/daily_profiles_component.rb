module Solakon
  # Small multiples, one per month. All months share one pair of axes, so the
  # shape of June can be held against the shape of September.
  class DailyProfilesComponent < ApplicationComponent
    WIDTH = 300
    HEIGHT = 160
    MARGINS = {
      # Half the top value's label stands above the plot.
      top: 10,
      # Room at the right edge for the last hour's label.
      right: 14,
      # The hours hang clear of the zero at the axis' end.
      bottom: 30,
      # Wide enough for a four-digit watt label at the phone's size.
      left: 48
    }.freeze
    # Grid steps a reader can count in; the first that reaches the peak in at
    # most MAX_GRID_STEPS steps wins, and its last step is the top of the plot.
    NICE_STEPS_W = [ 100, 200, 250, 500, 1000 ].freeze
    MAX_GRID_STEPS = 3
    DENSE_HOUR_STEP = 3
    SPARSE_HOUR_STEP = 6
    VALUE_LABEL_GAP = 4
    HOUR_LABEL_GAP = 8
    KEYS = { measured: "PV gemessen", expected: "Erwartet aus Einstrahlung", theory: "Wolkenloser Himmel" }.freeze

    Series = Data.define(:key, :segments)
    Hit = Data.define(:rect, :title)
    Label = Data.define(:x, :y, :text)
    Multiple = Data.define(:month, :label, :days, :partial, :series, :areas, :hits) do
      def partial? = partial
    end

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
          partial: profile.days < full_month_days(profile.month),
          series: drawing_order.map { |key| Series.new(key: key, segments: segments(profile, key)) },
          areas: plot.areas(profile.curve(:measured).points),
          hits: hits(profile)
        )
      end
    end

    # The axis stands for zero.
    def grid_lines = grid.reject { |tick| tick.value.zero? }.map(&:at)

    def value_labels
      grid.map do |tick|
        Label.new(x: plot.left - VALUE_LABEL_GAP, y: tick.at, text: tick.value.to_s)
      end
    end

    # On the clock's step, as bare hours: a small multiple has no room for more.
    def hour_labels(density)
      step = density == :sparse ? SPARSE_HOUR_STEP : DENSE_HOUR_STEP

      plot.x_ticks(hours.select { |hour| (hour % step).zero? })
          .map { |tick| Label.new(x: tick.at, y: plot.bottom + HOUR_LABEL_GAP, text: format("%02d", tick.value)) }
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

    # The measured line is drawn last so it lies over the two it is read
    # against.
    def drawing_order = KEYS.keys.reverse

    def segments(profile, key) = plot.polylines(profile.curve(key).points)

    def grid = plot.y_ticks(0.step(max_w, grid_step))

    # A common year's length, so a month counts as whole whatever the leap day.
    def full_month_days(month) = Date.new(2001, month, -1).day

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

    def peak_w = @profiles.filter_map(&:max).max.to_f

    def grid_step
      @grid_step ||= NICE_STEPS_W.find { |step| peak_w <= step * MAX_GRID_STEPS } ||
                     Plot.round_up(peak_w / MAX_GRID_STEPS, to: NICE_STEPS_W.last)
    end

    def max_w = [ Plot.round_up(peak_w, to: grid_step), grid_step ].max
  end
end
