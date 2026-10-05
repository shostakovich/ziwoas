module Solakon
  # Every box is drawn twice: on a phone the 720-unit drawing shrinks to less than half.
  class SunCalendarComponent < ApplicationComponent
    include ChartParts

    WIDTH = 720
    # Room for the hour labels and, above the plot, the phone's larger month labels.
    LEFT = 56
    RIGHT = 4
    TOP = 30
    BOTTOM_PAD = 4
    ROW_HEIGHTS = { wide: 8, narrow: 25 }.freeze
    BARS_HEIGHTS = { wide: 100, narrow: 240 }.freeze
    DENSITIES = { wide: :dense, narrow: :sparse }.freeze
    BARS_BOTTOM = 34
    STRIP_MARGINS = { top: TOP, right: RIGHT, bottom: BOTTOM_PAD, left: LEFT }.freeze
    BARS_MARGINS = { top: TOP, right: RIGHT, bottom: BARS_BOTTOM, left: LEFT }.freeze
    DENSE_HOUR_STEP = 3
    MAX_BAR_GRID_LINES = 4
    SPARSE_HOUR_STEP = 6
    MONTH_LINE_RISE = 4
    MONTH_LABEL_OFFSET = 2
    MONTH_LABEL_LIFT = 6
    AXIS_LABEL_GAP = 5
    MONTH_LABEL_GAP = 5
    # At the phone's size an hour label in the top rows would touch the month labels.
    HOUR_LABEL_CLEAR_ROWS = 2
    WEEKDAYS = %w[So Mo Di Mi Do Fr Sa].freeze

    Cells = Data.define(:fill, :rects) do
      def nodata? = fill.nil?
    end

    def initialize(calendar:)
      @calendar = calendar
    end

    def empty? = @calendar.empty?

    def year = @calendar.year

    def strips = @calendar.strips.values

    def strip_plots
      @strip_plots ||= ROW_HEIGHTS.to_h do |frame, row_height|
        height = TOP + (hours.count * row_height) + BOTTOM_PAD
        [ frame, Plot.new(width: WIDTH, height: height, margins: STRIP_MARGINS, x: day_axis, y: (hours.last + 1)..hours.first) ]
      end
    end

    def bars_plots
      @bars_plots ||= BARS_HEIGHTS.transform_values do |height|
        Plot.new(width: WIDTH, height: TOP + height + BARS_BOTTOM, margins: BARS_MARGINS, x: day_axis, y: 0..bars_max)
      end
    end

    def density(frame) = DENSITIES.fetch(frame)

    # Unmeasured hours get cells too: the ramp's low end is translucent, so a
    # ground under the whole plot would tint every quiet hour.
    def cells(strip)
      ramp = Ramp.fetch(strip.ramp)
      hours.flat_map { |hour| row_runs(strip, ramp, hour) }
           .group_by { |run| run.fetch(:fill) }
           .map { |fill, runs| Cells.new(fill: fill, rects: runs.map { |run| rect(run) }) }
    end

    def cells_id(strip) = "sun-cells-#{strip.key}"

    # Scales the wide frame's rows to the narrow frame's, keeping the plot's top.
    def cells_transform
      scale = ROW_HEIGHTS.fetch(:narrow) / ROW_HEIGHTS.fetch(:wide).to_f

      "matrix(1 0 0 #{format('%g', scale)} 0 #{number(TOP * (1 - scale))})"
    end

    # One outline per run of days: single bars a column wide shimmer as moiré.
    def bar_areas(plot)
      measured = @calendar.days.reject { |day| day.pv_kwh.nil? }

      measured.slice_when { |previous, day| day.doy != previous.doy + 1 }.map do |run|
        steps = run.map { |day| "V#{number(plot.y(day.pv_kwh))}H#{number(plot.x(day.doy + 1))}" }
        "M#{number(plot.x(run.first.doy))} #{plot.bottom}#{steps.join}V#{plot.bottom}Z"
      end
    end

    def bars_max = [ @calendar.max_kwh.to_f.ceil, 1 ].max

    def bar_grid_lines(plot) = plot.grid_lines(bar_values)

    def bar_grid_labels(plot) = plot.value_labels(bar_values, gap: AXIS_LABEL_GAP)

    def bar_unit_label(plot) = Plot::Label.new(x: plot.left, y: plot.top - MONTH_LABEL_LIFT, text: "kWh")

    def month_lines(plot) = plot.x_ticks(month_doys).map(&:at)

    def month_line_top(plot) = plot.top - MONTH_LINE_RISE

    def month_labels(plot, density)
      months = density == :sparse ? (1..12).step(2) : (1..12)

      months.map do |month|
        Plot::Label.new(x: number(plot.x(first_doy(month)) + MONTH_LABEL_OFFSET),
                  y: plot.top - MONTH_LABEL_LIFT, text: MONTHS[month - 1])
      end
    end

    def month_label_top(plot) = plot.bottom + MONTH_LABEL_GAP

    def hour_labels(plot, density)
      step = density == :sparse ? SPARSE_HOUR_STEP : DENSE_HOUR_STEP
      pattern = density == :sparse ? "%02d" : "%02d:00"

      labelled = hours.select { |hour| (hour % step).zero? && hour >= hours.first + HOUR_LABEL_CLEAR_ROWS }
      labelled.map do |hour|
        Plot::Label.new(x: plot.left - AXIS_LABEL_GAP, y: number(plot.y(hour)), text: format(pattern, hour))
      end
    end

    def hits(plot) = plot.hits(doys, titles)

    def lines? = !@calendar.lines.empty?

    def seam? = !@calendar.seam.nil?

    def seam_x(plot) = number(plot.x(@calendar.seam.yday))

    def seam_note
      return nil unless seam?

      "Bis #{day_month(@calendar.seam - 1)} aus der Energie der Erzeuger-Steckdose (AC), " \
        "ab #{day_month(@calendar.seam)} aus der PV-Leistung des Wechselrichters (DC). " \
        "Die gestrichelte Linie markiert den Wechsel."
    end

    # A frame's strips share one plot: the first draws the sun lines, the others <use> them.
    def draws_sun_lines?(strip) = strip.key == strips.first.key

    def sun_lines_id(frame) = "sun-lines-#{frame}"

    def sun_segments(plot, key) = plot.polylines(@calendar.lines.public_send(key))

    def legend_gradient(strip) = Ramp.fetch(strip.ramp).css_gradient

    private

    def number(value) = Plot.number(value)

    def wide_plot = strip_plots.fetch(:wide)

    def doys = @doys ||= @calendar.days.map(&:doy)

    # A day's column reaches to the next day's start.
    def day_axis = doys.first..(doys.last + 1)

    def hours = @calendar.hours

    # Few enough for the phone's larger labels to stay apart; the top belongs to the unit.
    def bar_values = 0.step(bars_max - 1, (bars_max / MAX_BAR_GRID_LINES.to_f).ceil)

    def month_doys = (1..12).map { |month| first_doy(month) }

    def titles = @titles ||= @calendar.days.map { |day| title_for(day) }

    def first_doy(month) = Date.new(year, month, 1).yday

    def day_month(date) = date.strftime("%d.%m.")

    def row_runs(strip, ramp, hour)
      runs = []

      doys.each do |doy|
        value = strip.values[[ doy, hour ]]
        fill = value && ramp.color(Ramp.level(value / strip.max))
        run = runs.last
        if run && run.fetch(:fill) == fill
          run[:last] = doy
        else
          runs << { first: doy, last: doy, fill: fill, hour: hour }
        end
      end

      runs
    end

    def rect(run)
      wide_plot.rect(run.fetch(:first)..(run.fetch(:last) + 1), run.fetch(:hour)..(run.fetch(:hour) + 1))
    end

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

      "#{label} #{'Ø ' if mean}#{GermanNumber.format(value, precision:, unit:)}"
    end
  end
end
