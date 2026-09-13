module Solakon
  # Three heat strips and the daily energy bars, one column per day of the year.
  # Geometry is computed here so the template only writes attributes.
  class SunCalendarComponent < ApplicationComponent
    WIDTH = 720
    LEFT = 26
    RIGHT = 4
    # Room above the plot for the month labels, which the phone's media query
    # enlarges to roughly this height.
    TOP = 22
    BOTTOM_PAD = 4
    ROW_HEIGHT = 8
    BARS_HEIGHT = 100
    BARS_BOTTOM = 24
    STRIP_MARGINS = { top: TOP, right: RIGHT, bottom: BOTTOM_PAD, left: LEFT }.freeze
    BARS_MARGINS = { top: TOP, right: RIGHT, bottom: BARS_BOTTOM, left: LEFT }.freeze
    # Cells snap to this many colour levels, so a run of near-equal days
    # collapses into one rectangle instead of hundreds.
    COLOUR_LEVELS = 64
    DENSE_HOUR_STEP = 3
    MAX_BAR_GRID_LINES = 4
    SPARSE_HOUR_STEP = 6
    BAR_GAP = 0.4
    MIN_BAR_WIDTH = 0.5
    MONTH_LINE_RISE = 4
    MONTH_LABEL_OFFSET = 2
    MONTH_LABEL_LIFT = 6
    AXIS_LABEL_GAP = 5
    LABEL_DROP = 3.5
    MONTH_LABEL_DROP = 18
    WEEKDAYS = %w[So Mo Di Mi Do Fr Sa].freeze

    Cells = Data.define(:fill, :rects)
    Hit = Data.define(:rect, :title)
    Label = Data.define(:x, :y, :text)

    def initialize(calendar:)
      @calendar = calendar
    end

    def empty? = @calendar.empty?

    def year = @calendar.year

    def strips = @calendar.strips.values

    def strip_plot
      @strip_plot ||= Plot.new(width: WIDTH, height: TOP + strip_height + BOTTOM_PAD, margins: STRIP_MARGINS,
                               x: day_axis, y: (hours.last + 1)..hours.first)
    end

    def bars_plot
      @bars_plot ||= Plot.new(width: WIDTH, height: TOP + BARS_HEIGHT + BARS_BOTTOM, margins: BARS_MARGINS,
                              x: day_axis, y: 0..bars_max)
    end

    # Grouped by colour so the fill is written once instead of on every rectangle.
    def cells(strip)
      ramp = Ramp.fetch(strip.ramp)
      hours.flat_map { |hour| row_runs(strip, ramp, hour) }
           .group_by { |run| run.fetch(:fill) }
           .map { |fill, runs| Cells.new(fill: fill, rects: runs.map { |run| rect(run) }) }
    end

    def bars
      @calendar.days.filter_map do |day|
        next if day.pv_kwh.nil?

        bars_plot.rect(day.doy..day.doy + 1, 0..day.pv_kwh).with(width: bar_width)
      end
    end

    def bars_max = [ @calendar.max_kwh.to_f.ceil, 1 ].max

    def bar_grid_lines = bar_grid.map(&:at)

    # At most MAX_BAR_GRID_LINES lines, so the labels stay apart once the
    # phone's media query enlarges them.
    def bar_grid_labels
      bar_grid.map do |tick|
        Label.new(x: bars_plot.left - AXIS_LABEL_GAP, y: number(tick.at + LABEL_DROP), text: tick.value.to_s)
      end
    end

    # The two frames share their x axis, so one set of month lines serves both.
    def month_lines = strip_plot.x_ticks(month_doys).map(&:at)

    def month_line_top = strip_plot.top - MONTH_LINE_RISE

    def month_labels(density)
      months = density == :sparse ? (1..12).step(2) : (1..12)

      months.map do |month|
        Label.new(x: number(strip_plot.x(first_doy(month)) + MONTH_LABEL_OFFSET),
                  y: strip_plot.top - MONTH_LABEL_LIFT, text: MONTHS[month - 1])
      end
    end

    def month_label_baseline = bars_plot.bottom + MONTH_LABEL_DROP

    def hour_labels(density)
      step = density == :sparse ? SPARSE_HOUR_STEP : DENSE_HOUR_STEP

      hours.step(step).map do |hour|
        Label.new(x: strip_plot.left - AXIS_LABEL_GAP, y: number(strip_plot.y(hour) + LABEL_DROP), text: hour.to_s)
      end
    end

    # The same tooltips sit on all four boxes; only the box they cover changes.
    def hits(plot)
      plot.columns(doys).zip(titles).map { |rect, title| Hit.new(rect: rect, title: title) }
    end

    def lines? = !@calendar.lines.empty?

    def seam? = !@calendar.seam.nil?

    def seam_x = number(strip_plot.x(@calendar.seam.yday))

    def seam_note
      return nil unless seam?

      "Bis #{day_month(@calendar.seam - 1)} aus der Energie der Erzeuger-Steckdose (AC), " \
        "ab #{day_month(@calendar.seam)} aus der PV-Leistung des Wechselrichters (DC). " \
        "Die gestrichelte Linie markiert den Wechsel."
    end

    def sun_segments(key) = strip_plot.polylines(@calendar.lines.public_send(key))

    def legend_gradient(strip) = Ramp.fetch(strip.ramp).css_gradient

    def legend_max(strip) = format("%d", strip.max)

    private

    delegate :number, to: :strip_plot, private: true

    def doys = @doys ||= @calendar.days.map(&:doy)

    # A day column reaches to the next day, so the axis runs one day past the
    # last one.
    def day_axis = doys.first..(doys.last + 1)

    def hours = @calendar.hours

    def strip_height = hours.count * ROW_HEIGHT

    def day_width = strip_plot.x(2) - strip_plot.x(1)

    def bar_width = number([ day_width - BAR_GAP, MIN_BAR_WIDTH ].max)

    def bar_grid
      step = (bars_max / MAX_BAR_GRID_LINES.to_f).ceil

      bars_plot.y_ticks(step.step(bars_max, step))
    end

    def month_doys = (1..12).map { |month| first_doy(month) }

    def titles = @titles ||= @calendar.days.map { |day| title_for(day) }

    def first_doy(month) = Date.new(year, month, 1).yday

    def day_month(date) = date.strftime("%d.%m.")

    def row_runs(strip, ramp, hour)
      runs = []

      doys.each do |doy|
        value = strip.values[[ doy, hour ]]
        next if value.nil?

        fill = ramp.color(level(value, strip.max))
        run = runs.last
        if run && run.fetch(:fill) == fill && run.fetch(:last) == doy - 1
          run[:last] = doy
        else
          runs << { first: doy, last: doy, fill: fill, hour: hour }
        end
      end

      runs
    end

    def rect(run)
      strip_plot.rect(run.fetch(:first)..(run.fetch(:last) + 1), run.fetch(:hour)..(run.fetch(:hour) + 1))
    end

    def level(value, max) = (value / max * COLOUR_LEVELS).round / COLOUR_LEVELS.to_f

    def title_for(day)
      date = "#{WEEKDAYS[day.date.wday]} #{day.date.strftime('%d.%m.%Y')}"
      return "#{date} · keine Daten" if [ day.pv_kwh, day.irradiance_kwh_per_m2, day.cloud_avg ].all?(&:nil?)

      [
        date,
        measure("PV-Energie", day.pv_kwh, "kWh", 2),
        measure("Einstrahlung", day.irradiance_kwh_per_m2, "kWh/m²", 2),
        measure("Bewölkung", day.cloud_avg, "%", 0, mean: true)
      ].join(" · ")
    end

    def measure(label, value, unit, precision, mean: false)
      return "#{label} keine Daten" if value.nil?

      "#{label} #{'Ø ' if mean}#{decimal(value, precision)} #{unit}"
    end

    def decimal(value, precision) = format("%.#{precision}f", value).tr(".", ",")
  end
end
