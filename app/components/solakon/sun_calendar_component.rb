module Solakon
  # The sun calendar: three heat strips and the daily energy bars, one column
  # per day of the year, drawn server-side as SVG. Geometry is computed here so
  # the template only writes attributes.
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
    # Cells snap to this many colour levels, so a run of near-equal days
    # collapses into one rectangle instead of hundreds.
    COLOUR_LEVELS = 64
    DENSE_HOUR_STEP = 3
    MAX_BAR_GRID_LINES = 4
    SPARSE_HOUR_STEP = 6
    WEEKDAYS = %w[So Mo Di Mi Do Fr Sa].freeze

    Cells = Data.define(:fill, :rects)
    Rect = Data.define(:x, :y, :width)
    Bar = Data.define(:x, :y, :width, :height)
    Hit = Data.define(:x, :width, :title)
    Label = Data.define(:x, :y, :text)

    def initialize(calendar:)
      @calendar = calendar
    end

    def empty? = @calendar.empty?

    def year = @calendar.year

    def strips = @calendar.strips.values

    def row_height = ROW_HEIGHT

    def strip_view_box = "0 0 #{WIDTH} #{TOP + strip_height + BOTTOM_PAD}"

    def bars_view_box = "0 0 #{WIDTH} #{TOP + BARS_HEIGHT + BARS_BOTTOM}"

    def strip_height = hours.count * ROW_HEIGHT

    def bars_height = BARS_HEIGHT

    def plot_top = TOP

    def plot_left = LEFT

    def ground_width = number(days.length * day_width)

    # One rectangle per run of neighbouring days that share a colour, grouped
    # by colour so the fill is written once instead of on every rectangle.
    def cells(strip)
      ramp = Ramp.fetch(strip.ramp)
      hours.flat_map { |hour| row_runs(strip, ramp, hour) }
           .group_by { |run| run.fetch(:fill) }
           .map { |fill, runs| Cells.new(fill: fill, rects: runs.map { |run| rect(run) }) }
    end

    def bars
      @calendar.days.filter_map do |day|
        next if day.pv_kwh.nil?

        height = day.pv_kwh / bars_max * BARS_HEIGHT
        Bar.new(x: number(x(day.doy)), y: number(TOP + BARS_HEIGHT - height), width: bar_width, height: number(height))
      end
    end

    def bars_max = [ @calendar.max_kwh.to_f.ceil, 1 ].max

    # At most MAX_BAR_GRID_LINES lines, so the labels stay apart once the
    # phone's media query enlarges them.
    def bar_grid
      step = (bars_max / MAX_BAR_GRID_LINES.to_f).ceil
      step.step(bars_max, step).map do |kwh|
        Label.new(x: LEFT, y: number(TOP + BARS_HEIGHT - kwh.to_f / bars_max * BARS_HEIGHT), text: kwh.to_s)
      end
    end

    def baseline_y = TOP + BARS_HEIGHT

    def plot_right = number(x(days.length) + day_width)

    # The same tooltips sit on all four boxes, so they are built once.
    def hits
      @hits ||= @calendar.days.map do |day|
        Hit.new(x: number(x(day.doy)), width: number(day_width), title: title_for(day))
      end
    end

    def lines? = !@calendar.lines.empty?

    def seam? = !@calendar.seam.nil?

    def seam_x = number(x(@calendar.seam.yday))

    # Says which side of the dashed line was measured how, in the page's own
    # words rather than in the glossary's.
    def seam_note
      return nil unless seam?

      "Bis #{day_month(@calendar.seam - 1)} aus der Energie der Erzeuger-Steckdose (AC), " \
        "ab #{day_month(@calendar.seam)} aus der PV-Leistung des Wechselrichters (DC). " \
        "Die gestrichelte Linie markiert den Wechsel."
    end

    # One polyline per unbroken stretch of days. A polar period leaves a gap in
    # the events, and a single polyline would bridge it with a straight line
    # that no sun ever took. The daylight saving seam repeats a day of year
    # rather than skipping one, so it stays inside its segment.
    def sun_segments(key)
      @calendar.lines.public_send(key)
               .slice_when { |(previous, _), (doy, _)| doy - previous > 1 }
               .map { |segment| segment.map { |doy, hour| "#{number(x(doy))},#{number(y(hour))}" }.join(" ") }
    end

    def month_lines = (1..12).map { |month| number(x(first_doy(month))) }

    def month_labels(density)
      months = density == :sparse ? (1..12).step(2) : (1..12)
      months.map do |month|
        Label.new(x: number(x(first_doy(month)) + 2), y: TOP - 6, text: MONTHS[month - 1])
      end
    end

    def hour_labels(density)
      step = density == :sparse ? SPARSE_HOUR_STEP : DENSE_HOUR_STEP
      hours.first.step(hours.last, step).map do |hour|
        Label.new(x: LEFT - 5, y: number(y(hour) + 3.5), text: hour.to_s)
      end
    end

    def legend_gradient(strip) = Ramp.fetch(strip.ramp).css_gradient

    def legend_max(strip) = format("%d", strip.max)

    private

    def days = @calendar.days

    def hours = @calendar.hours

    def day_width = (WIDTH - LEFT - RIGHT) / days.length.to_f

    def bar_width = number([ day_width - 0.4, 0.5 ].max)

    def x(doy) = LEFT + (doy - 1) * day_width

    def y(hour) = TOP + (hour - hours.first) * ROW_HEIGHT

    def first_doy(month) = Date.new(year, month, 1).yday

    def day_month(date) = date.strftime("%d.%m.")

    def row_runs(strip, ramp, hour)
      runs = []

      (1..days.length).each do |doy|
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
      Rect.new(
        x: number(x(run.fetch(:first))),
        y: number(y(run.fetch(:hour))),
        width: number((run.fetch(:last) - run.fetch(:first) + 1) * day_width)
      )
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
