module Solakon
  # Three heat strips and the daily energy, one column per day of the year.
  # Geometry is computed here so the template only writes attributes.
  #
  # Every box is drawn twice: flat from a small tablet up, taller for phones,
  # where the 720-unit drawing shrinks to less than half. The wide frame
  # carries the dense labels, the narrow one the sparse.
  class SunCalendarComponent < ApplicationComponent
    WIDTH = 720
    # Room for the hour labels at the small tablet's size and, above the plot,
    # the month labels at the size the phone's media query gives them.
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
    # Cells snap to this many colour levels, so a run of near-equal days
    # collapses into one rectangle instead of hundreds.
    COLOUR_LEVELS = 64
    DENSE_HOUR_STEP = 3
    MAX_BAR_GRID_LINES = 4
    SPARSE_HOUR_STEP = 6
    MONTH_LINE_RISE = 4
    MONTH_LABEL_OFFSET = 2
    MONTH_LABEL_LIFT = 6
    AXIS_LABEL_GAP = 5
    # The month labels under the bars hang from this line, whatever their size.
    MONTH_LABEL_GAP = 5
    # Hour labels keep this many rows clear of the plot's top, where the month
    # labels stand: at the phone's size the two would touch.
    HOUR_LABEL_CLEAR_ROWS = 2
    WEEKDAYS = %w[So Mo Di Mi Do Fr Sa].freeze

    # A group without a fill holds the hours nobody measured.
    Cells = Data.define(:fill, :rects) do
      def nodata? = fill.nil?
    end
    Hit = Data.define(:rect, :title)
    # The zero stands on the axis rather than across it, clear of the first
    # month hanging below.
    Label = Data.define(:x, :y, :text, :zero) do
      def initialize(x:, y:, text:, zero: false) = super
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

    def frame_classes(frame) = frame == :wide ? "d-none d-sm-block" : "d-sm-none"

    # Only the wide frame shows a pointer's tooltips; a phone has none to show.
    def hits?(frame) = frame == :wide

    # Grouped by colour so the fill is written once instead of on every
    # rectangle. They are measured in the wide frame; the narrow one stretches
    # the same cells instead of writing thousands of them a second time.
    # Hours without a value are cells too: the ramp's low end is translucent,
    # so a ground under the whole plot would tint every quiet hour.
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

    # One closed outline per run of measured days: at a column per day, single
    # bars with gaps between them shimmer as moiré on any screen.
    def bar_areas(plot)
      measured = @calendar.days.reject { |day| day.pv_kwh.nil? }

      measured.slice_when { |previous, day| day.doy != previous.doy + 1 }.map do |run|
        steps = run.map { |day| "V#{number(plot.y(day.pv_kwh))}H#{number(plot.x(day.doy + 1))}" }
        "M#{number(plot.x(run.first.doy))} #{plot.bottom}#{steps.join}V#{plot.bottom}Z"
      end
    end

    def bars_max = [ @calendar.max_kwh.to_f.ceil, 1 ].max

    # The axis stands for the zero line.
    def bar_grid_lines(plot) = bar_grid(plot).reject { |tick| tick.value.zero? }.map(&:at)

    # At most MAX_BAR_GRID_LINES lines, so the labels stay apart once the
    # phone's media query enlarges them.
    def bar_grid_labels(plot)
      bar_grid(plot).map do |tick|
        Label.new(x: plot.left - AXIS_LABEL_GAP, y: tick.at, text: tick.value.to_s, zero: tick.value.zero?)
      end
    end

    # The unit stands over the plot's left edge, where the axis begins.
    def bar_unit_label(plot) = Label.new(x: plot.left, y: plot.top - MONTH_LABEL_LIFT, text: "kWh")

    # Every frame shares the x axis, so the month lines stand alike in all.
    def month_lines(plot) = plot.x_ticks(month_doys).map(&:at)

    def month_line_top(plot) = plot.top - MONTH_LINE_RISE

    def month_labels(plot, density)
      months = density == :sparse ? (1..12).step(2) : (1..12)

      months.map do |month|
        Label.new(x: number(plot.x(first_doy(month)) + MONTH_LABEL_OFFSET),
                  y: plot.top - MONTH_LABEL_LIFT, text: MONTHS[month - 1])
      end
    end

    def month_label_top(plot) = plot.bottom + MONTH_LABEL_GAP

    # A full clock time where there is room, the bare hour on the phone.
    def hour_labels(plot, density)
      step = density == :sparse ? SPARSE_HOUR_STEP : DENSE_HOUR_STEP
      pattern = density == :sparse ? "%02d" : "%02d:00"

      labelled = hours.select { |hour| (hour % step).zero? && hour >= hours.first + HOUR_LABEL_CLEAR_ROWS }
      labelled.map do |hour|
        Label.new(x: plot.left - AXIS_LABEL_GAP, y: number(plot.y(hour)), text: format(pattern, hour))
      end
    end

    # The same tooltips sit on all four boxes; only the box they cover changes.
    def hits(plot)
      plot.columns(doys).zip(titles).map { |rect, title| Hit.new(rect: rect, title: title) }
    end

    def lines? = !@calendar.lines.empty?

    def seam? = !@calendar.seam.nil?

    def seam_x(plot) = number(plot.x(@calendar.seam.yday))

    def seam_note
      return nil unless seam?

      "Bis #{day_month(@calendar.seam - 1)} aus der Energie der Erzeuger-Steckdose (AC), " \
        "ab #{day_month(@calendar.seam)} aus der PV-Leistung des Wechselrichters (DC). " \
        "Die gestrichelte Linie markiert den Wechsel."
    end

    def sun_segments(plot, key) = plot.polylines(@calendar.lines.public_send(key))

    def legend_gradient(strip) = Ramp.fetch(strip.ramp).css_gradient

    def legend_max(strip) = format("%d", strip.max)

    private

    def number(value) = Plot.number(value)

    def wide_plot = strip_plots.fetch(:wide)

    def doys = @doys ||= @calendar.days.map(&:doy)

    # A day column reaches to the next day, so the axis runs one day past the
    # last one.
    def day_axis = doys.first..(doys.last + 1)

    def hours = @calendar.hours

    # Below the plot's top, where the unit stands instead.
    def bar_grid(plot)
      step = (bars_max / MAX_BAR_GRID_LINES.to_f).ceil

      plot.y_ticks(0.step(bars_max - 1, step))
    end

    def month_doys = (1..12).map { |month| first_doy(month) }

    def titles = @titles ||= @calendar.days.map { |day| title_for(day) }

    def first_doy(month) = Date.new(year, month, 1).yday

    def day_month(date) = date.strftime("%d.%m.")

    # Every day of the year has a cell, measured or not, so a run ends only
    # where its colour does.
    def row_runs(strip, ramp, hour)
      runs = []

      doys.each do |doy|
        value = strip.values[[ doy, hour ]]
        fill = value && ramp.color(level(value, strip.max))
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

    def decimal(value, precision) = GermanNumber.format(value, precision: precision)
  end
end
