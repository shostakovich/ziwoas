require "test_helper"

class Solakon::SunCalendarComponentTest < ViewComponent::TestCase
  cover "Solakon::SunCalendarComponent*"

  def strip(key, title, unit, ramp, max, values)
    SunCalendar::Strip.new(key: key, title: title, unit: unit, ramp: ramp, max: max, values: values)
  end

  def calendar(pv: { [ 100, 12 ] => 600.0 }, irradiance: {}, cloud: {}, days: nil, lines: nil, hours: (3..22), seam: nil)
    days ||= (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map do |date|
      SunCalendar::Day.new(doy: date.yday, date: date, pv_kwh: nil, irradiance_kwh_per_m2: nil, cloud_avg: nil)
    end
    SunCalendar::Year.new(
      year: 2026,
      days: days,
      hours: hours,
      strips: {
        pv: strip(:pv, "PV-Leistung", "W", :amber, 800.0, pv),
        irradiance: strip(:irradiance, "Einstrahlung", "W/m²", :blue, 900.0, irradiance),
        cloud: strip(:cloud, "Bewölkung", "%", :grey, 100.0, cloud)
      },
      max_kwh: days.filter_map(&:pv_kwh).max,
      lines: lines || SunCalendar::Lines.new(rise: [], set: [], noon: []),
      seam: seam
    )
  end

  def day(doy, pv_kwh: nil, irradiance: nil, cloud: nil)
    date = Date.new(2026, 1, 1) + (doy - 1)
    SunCalendar::Day.new(doy: doy, date: date, pv_kwh: pv_kwh, irradiance_kwh_per_m2: irradiance, cloud_avg: cloud)
  end

  def render_calendar(**options) = render_inline(Solakon::SunCalendarComponent.new(calendar: calendar(**options)))

  test "stacks the three strips and the daily bars on one time axis" do
    rendered = render_calendar

    assert_equal %w[pv irradiance cloud energy], rendered.css("[data-strip]").map { |node| node["data-strip"] }
    titles = rendered.css(".sun-calendar h3").map(&:text)
    assert_equal [ "PV-Leistung", "Einstrahlung", "Bewölkung", "PV-Energie je Tag" ], titles
  end

  test "shows the empty state while no PV hour exists" do
    rendered = render_inline(Solakon::SunCalendarComponent.new(calendar: calendar(pv: {})))

    assert_selector ".empty-state"
    assert_text "Stundenwerte"
    assert_equal 0, rendered.css("svg").length
  end

  test "scales over the viewBox instead of a fixed size" do
    svg = render_calendar.css("[data-strip='pv'] svg").first

    assert_equal "0 0 720 194", svg["viewBox"]
    assert_nil svg["width"]
  end

  test "paints a cell in the ramp colour of its value" do
    rendered = render_calendar(pv: { [ 100, 12 ] => 800.0 })

    assert_equal "fill: var(--ramp-amber-2)", rendered.css("[data-strip='pv'] .cells g").first["style"]
  end

  test "merges neighbouring days of equal colour into one rectangle" do
    values = (10..14).to_h { |doy| [ [ doy, 12 ], 400.0 ] }

    cells = render_calendar(pv: values).css("[data-strip='pv'] .cells rect")

    assert_equal 1, cells.length
    assert_in_delta 5 * (720 - 44) / 365.0, cells.first["width"].to_f, 0.05
  end

  test "keeps a gap between days that are not neighbours" do
    values = { [ 10, 12 ] => 400.0, [ 12, 12 ] => 400.0 }

    assert_equal 2, render_calendar(pv: values).css("[data-strip='pv'] .cells rect").length
  end

  test "leaves days without a value on the no-data ground" do
    rendered = render_calendar

    assert_equal 1, rendered.css("[data-strip='pv'] rect.nodata").length
    assert_equal 1, rendered.css("[data-strip='pv'] .cells rect").length
    assert_includes rendered.css("[data-strip='pv'] .legend").text, "keine Daten"
  end

  def year_lines(days)
    SunCalendar::Lines.new(
      rise: days.map { |doy| [ doy, 8.0 ] },
      set: days.map { |doy| [ doy, 16.0 ] },
      noon: days.map { |doy| [ doy, 12.0 ] }
    )
  end

  test "draws sunrise, sunset and solar noon across the whole year" do
    rendered = render_calendar(lines: year_lines((1..365).to_a))

    assert_equal 3, rendered.css("[data-strip='pv'] polyline.sun").length
    assert_equal 3, rendered.css("[data-strip='cloud'] polyline.sun").length
    assert_equal 0, rendered.css("[data-strip='energy'] polyline.sun").length

    assert_equal 365, rendered.css("[data-strip='pv'] polyline.rise").first["points"].split.length
  end

  test "breaks the sun lines where polar days leave a gap" do
    rendered = render_calendar(lines: year_lines((1..100).to_a + (260..365).to_a))

    rise = rendered.css("[data-strip='pv'] polyline.rise")

    assert_equal 2, rise.length, "a polar gap must not be bridged by a straight line"
    assert_equal 100, rise.first["points"].split.length
    assert_equal 106, rise.last["points"].split.length
    assert_equal 6, rendered.css("[data-strip='pv'] polyline.sun").length
  end

  test "breaks the sun lines even when only a single day is missing" do
    doys = (1..100).to_a + (102..365).to_a

    rise = render_calendar(lines: year_lines(doys)).css("[data-strip='pv'] polyline.rise")

    assert_equal 2, rise.length, "a single missing day must still start a new segment"
    assert_equal 100, rise.first["points"].split.length
    assert_equal 264, rise.last["points"].split.length
  end

  test "keeps the daylight saving seam inside one segment" do
    doys = (1..90).to_a + [ 90 ] + (91..365).to_a

    rise = render_calendar(lines: year_lines(doys)).css("[data-strip='pv'] polyline.rise")

    assert_equal 1, rise.length
    assert_equal 366, rise.first["points"].split.length
  end

  test "marks the day the inverter took over from the plug" do
    rendered = render_calendar(seam: Date.new(2026, 6, 20))

    seam = rendered.css("[data-strip='pv'] line.seam")

    assert_equal 1, seam.length
    assert_equal "354.8", seam.first["x1"]
    assert_equal seam.first["x1"], seam.first["x2"]
    assert_includes rendered.css("[data-strip='pv'] .legend").text, "Wechsel der Quelle"
  end

  test "puts the seam only on the PV strip, where the source changes" do
    rendered = render_calendar(seam: Date.new(2026, 6, 20))

    assert_equal 0, rendered.css("[data-strip='irradiance'] line.seam").length
    assert_equal 0, rendered.css("[data-strip='cloud'] line.seam").length
    assert_equal 0, rendered.css("[data-strip='energy'] line.seam").length
  end

  test "names both sources and their dates under the strip they explain" do
    rendered = render_calendar(seam: Date.new(2026, 6, 20))

    note = rendered.css("[data-strip='pv'] .note").text

    assert_includes note, "Bis 19.06."
    assert_includes note, "ab 20.06."
    assert_includes note, "AC"
    assert_includes note, "DC"
    assert_equal 1, rendered.css(".sun-calendar .note").length, "the note belongs to the PV strip alone"
  end

  test "says nothing about a seam on a year that had only one source" do
    rendered = render_calendar

    assert_equal 0, rendered.css("line.seam").length
    assert_equal 0, rendered.css(".sun-calendar .note").length
    assert_not_includes rendered.css("[data-strip='pv'] .legend").text, "Wechsel"
  end

  test "leaves the sun lines out without a location" do
    assert_equal 0, render_calendar.css("polyline.sun").length
  end

  test "says nothing about sunrise and sunset in the legend without a location" do
    rendered = render_calendar

    assert_not_includes rendered.css(".sun-calendar .legend").text, "Sonnenaufgang"
    assert_not_includes rendered.css(".sun-calendar .legend").text, "Sonnenhöchststand"
  end

  test "rises the month lines a little above the plot, up to their labels" do
    line = render_calendar.css("[data-strip='pv'] .grid line").first

    assert_equal "26", line["y1"]
  end

  test "labels the axes in two densities so the phone gets the sparse one" do
    rendered = render_calendar

    assert_equal 12, rendered.css("[data-strip='pv'] .month-labels.label-dense text").length
    assert_equal 6, rendered.css("[data-strip='pv'] .month-labels.label-sparse text").length
    assert_operator rendered.css("[data-strip='pv'] .hour-labels.label-dense text").length, :>,
                    rendered.css("[data-strip='pv'] .hour-labels.label-sparse text").length
  end

  test "gives every day a tooltip with its numbers" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 4.213, irradiance: 3.4, cloud: 48.6)

    rendered = render_calendar(days: days)
    titles = rendered.css("[data-strip='pv'] .hits title").map(&:text)

    assert_equal 365, titles.length
    assert_equal "Fr 10.04.2026 · PV-Energie 4,21 kWh · Einstrahlung 3,40 kWh/m² · Bewölkung Ø 49 %", titles[99]
    assert_equal "Do 01.01.2026 · keine Daten", titles[0]
  end

  test "names the missing halves of a partly measured day" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 4.213)

    title = render_calendar(days: days).css("[data-strip='pv'] .hits title")[99].text

    assert_equal "Fr 10.04.2026 · PV-Energie 4,21 kWh · Einstrahlung keine Daten · Bewölkung keine Daten", title
  end

  test "draws a bar per day with PV energy and scales it to the best day" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 4.0)
    days[100] = day(101, pv_kwh: 2.0)

    bars = render_calendar(days: days).css("[data-strip='energy'] svg.energy-chart-wide .bars rect")

    assert_equal 2, bars.length
    assert_in_delta 2 * bars.last["height"].to_f, bars.first["height"].to_f, 0.01
  end

  test "puts the maximum and the unit into every legend" do
    legends = render_calendar.css(".sun-calendar .legend").map(&:text)

    assert_match(/800\b.*W\b/, legends[0])
    assert_match(/900\b.*W\/m²/, legends[1])
    assert_match(/100\b.*%/, legends[2])
    assert_match(/kWh/, legends[3])
  end

  test "widens the strip when data sits outside the base hours" do
    svg = render_calendar(hours: (1..23)).css("[data-strip='pv'] svg").first

    assert_equal "0 0 720 218", svg["viewBox"]
  end

  test "sizes the energy chart's viewBox from the bars height and bottom margin, taller for phones" do
    wide, narrow = render_calendar.css("[data-strip='energy'] svg").to_a

    assert_equal "0 0 720 164", wide["viewBox"]
    assert_equal %w[energy-chart-wide d-none d-sm-block], wide["class"].split
    assert_equal "0 0 720 304", narrow["viewBox"]
    assert_equal %w[energy-chart-narrow d-sm-none], narrow["class"].split
  end

  test "draws the phone's bars against its own, taller plot" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 3.0)
    chart = render_calendar(days: days).css("[data-strip='energy'] svg.energy-chart-narrow").sole

    assert_equal %w[223.4 30 1.5 240], %w[x y width height].map { |name| chart.css(".bars rect").sole[name] }
    assert_equal %w[40 716 270 270], %w[x1 x2 y1 y2].map { |name| chart.css("line.axis").sole[name] }
    assert_equal %w[30 240], %w[y height].map { |name| chart.css(".hits rect").first[name] }
    assert_equal %w[1 2], chart.css(".hour-labels text").map(&:text), "the top step gives way to the unit"
    assert_equal %w[190 110], chart.css(".hour-labels text").map { |label| label["y"] }
    assert_equal "275", chart.css(".month-labels.label-dense text").first["y"]
  end

  test "names the energy axis' unit above it, from the drawing's left edge" do
    units = render_calendar.css("[data-strip='energy'] text.unit")

    assert_equal [ [ "kWh", "0", "24" ] ] * 2, units.map { |node| [ node.text, node["x"], node["y"] ] }
  end

  test "measures the ground, the cells, the bars, the sun lines and the hits against the same axes" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 3.0)
    rendered = render_calendar(days: days, pv: { [ 10, 12 ] => 800.0 }, lines: year_lines((1..365).to_a))

    ground = rendered.css("[data-strip='pv'] rect.nodata").first
    assert_equal %w[40 30 676 160], %w[x y width height].map { |name| ground[name] }

    cell = rendered.css("[data-strip='pv'] .cells rect").sole
    assert_equal %w[56.7 102 1.9 8], %w[x y width height].map { |name| cell[name] }

    hit = rendered.css("[data-strip='pv'] .hits rect")[99]
    assert_equal %w[223.4 30 1.9 160], %w[x y width height].map { |name| hit[name] }

    axis = rendered.css("[data-strip='energy'] svg.energy-chart-wide line.axis").first
    assert_equal %w[40 716 130 130], %w[x1 x2 y1 y2].map { |name| axis[name] }

    bar = rendered.css("[data-strip='energy'] svg.energy-chart-wide .bars rect").sole
    assert_equal %w[223.4 30 1.5 100], %w[x y width height].map { |name| bar[name] }

    energy_hit = rendered.css("[data-strip='energy'] svg.energy-chart-wide .hits rect").first
    assert_equal %w[30 100], %w[y height].map { |name| energy_hit[name] }

    rise = rendered.css("[data-strip='pv'] polyline.rise").first["points"].split
    assert_equal "40,70", rise.first
    assert_equal "714.1,70", rise.last

    hour = rendered.css("[data-strip='pv'] .hour-labels.label-dense text").first
    assert_equal %w[35 54], [ hour["x"], hour["y"] ]

    month = rendered.css("[data-strip='pv'] .month-labels.label-dense text").first
    assert_equal %w[42 24], [ month["x"], month["y"] ]
  end

  test "draws the month grid lines at each month's first day of year" do
    x_values = render_calendar.css("[data-strip='pv'] .grid line").map { |line| line["x1"] }

    expected = [ 40, 97.4, 149.3, 206.7, 262.2, 319.7, 375.2, 432.6, 490, 545.6, 603, 658.6 ]
    assert_equal expected.map(&:to_s), x_values
  end

  test "shows the ramp's css gradient in the legend" do
    style = render_calendar.css("[data-strip='pv'] .legend-ramp").first["style"]

    assert_includes style, Ramp.fetch(:amber).css_gradient
  end

  test "keeps the bar width from collapsing below half a pixel on a very dense calendar" do
    # At 3000 columns day_width - 0.4 goes negative, well clear of the 0.5 floor,
    # so this proves the floor actually binds rather than coinciding with it.
    days = (1..3000).map { |doy| SunCalendar::Day.new(doy: doy, date: Date.new(2026, 1, 1), pv_kwh: nil, irradiance_kwh_per_m2: nil, cloud_avg: nil) }
    days[1499] = SunCalendar::Day.new(doy: 1500, date: Date.new(2026, 1, 1), pv_kwh: 1.0, irradiance_kwh_per_m2: nil, cloud_avg: nil)

    bar = render_calendar(days: days).css("[data-strip='energy'] svg.energy-chart-wide .bars rect").first

    assert_equal "0.5", bar["width"]
  end

  test "ceils the year's best day to the next whole kWh for the axis maximum" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 3.3)

    bar = render_calendar(days: days).css("[data-strip='energy'] svg.energy-chart-wide .bars rect").first

    # bars_max ceils 3.3 to 4, so the bar reaches only 3.3 / 4 of the chart height.
    assert_in_delta 3.3 / 4.0 * 100, bar["height"].to_f, 0.05
  end

  test "keeps the axis maximum at one kWh, not two, when the best day is exactly one" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 1.0)

    bar = render_calendar(days: days).css("[data-strip='energy'] svg.energy-chart-wide .bars rect").first

    assert_equal "100", bar["height"]
  end

  test "labels the PV-energy axis at even kWh steps, ceiling the step to fill the range" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 10.0)

    labels = render_calendar(days: days).css("[data-strip='energy'] svg.energy-chart-wide .hour-labels text")

    assert_equal %w[3 6 9], labels.map(&:text)
    assert_equal %w[100 70 40], labels.map { |label| label["y"] }
  end

  test "keeps the kWh grid labels clear of the axis, rounded to one decimal" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 11.0)

    labels = render_calendar(days: days).css("[data-strip='energy'] svg.energy-chart-wide .hour-labels text")

    assert_equal %w[35 35 35], labels.map { |label| label["x"] }
    assert_equal %w[102.7 75.5 48.2], labels.map { |label| label["y"] }
  end

  test "draws a grid line at each labeled kWh height, spanning the full width" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 11.0)

    lines = render_calendar(days: days).css("[data-strip='energy'] svg.energy-chart-wide .grid line").select { |line| line["y1"] == line["y2"] }

    assert_equal %w[102.7 75.5 48.2], lines.map { |line| line["y1"] }
    assert_equal %w[40 40 40], lines.map { |line| line["x1"] }
    assert_equal %w[716 716 716], lines.map { |line| line["x2"] }
  end

  test "hangs the energy chart's month labels just under the axis, clear of the bars" do
    label = render_calendar.css("[data-strip='energy'] svg.energy-chart-wide .month-labels.label-dense text").first

    assert_equal "135", label["y"]
  end

  test "colours a cell by its share of the strip's maximum, not by the raw value" do
    rendered = render_calendar(pv: { [ 10, 12 ] => 400.0 })

    fill = rendered.css("[data-strip='pv'] .cells g").first["style"]

    assert_equal "fill: #{Ramp.fetch(:amber).color(0.5)}", fill
  end

  test "rounds the colour share to the nearest level instead of using the raw fraction" do
    # 390 / 800 lands between two colour levels; rounding first picks a visibly
    # different stop than dividing the unrounded fraction straight through.
    rendered = render_calendar(pv: { [ 10, 12 ] => 390.0 })

    fill = rendered.css("[data-strip='pv'] .cells g").first["style"]

    assert_equal "fill: color-mix(in oklab, var(--ramp-amber-1) 96.9%, var(--ramp-amber-0))", fill
  end

  test "includes both the year's first and last day in the heat strip" do
    values = { [ 1, 12 ] => 200.0, [ 365, 12 ] => 800.0 }

    rects = render_calendar(pv: values).css("[data-strip='pv'] .cells rect")

    assert_equal 2, rects.length
    assert_equal "40", rects.first["x"]
  end

  test "keeps adjacent days with different values as separate rectangles" do
    values = { [ 10, 12 ] => 200.0, [ 11, 12 ] => 800.0 }

    rects = render_calendar(pv: values).css("[data-strip='pv'] .cells rect")

    assert_equal 2, rects.length
  end

  test "labels the hour axis at the dense and sparse step, offset from the plot" do
    rendered = render_calendar

    dense = rendered.css("[data-strip='pv'] .hour-labels.label-dense text")
    sparse = rendered.css("[data-strip='pv'] .hour-labels.label-sparse text")

    assert_equal %w[6 9 12 15 18 21], dense.map(&:text)
    assert_equal %w[6 12 18], sparse.map(&:text)
  end

  test "keeps the hour labels on the clock's step and two rows clear of the month labels" do
    rendered = render_calendar(hours: (4..20))

    assert_equal %w[6 9 12 15 18], rendered.css("[data-strip='pv'] .hour-labels.label-dense text").map(&:text)

    rendered = render_calendar(hours: (5..20))

    assert_equal %w[9 12 15 18], rendered.css("[data-strip='pv'] .hour-labels.label-dense text").map(&:text)
    assert_equal %w[12 18], rendered.css("[data-strip='pv'] .hour-labels.label-sparse text").map(&:text)
  end

  test "labels the month axis at the dense and sparse step, offset from the day column" do
    rendered = render_calendar

    dense = rendered.css("[data-strip='pv'] .month-labels.label-dense text")
    sparse = rendered.css("[data-strip='pv'] .month-labels.label-sparse text")

    assert_equal %w[Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez], dense.map(&:text)
    assert_equal %w[Jan Mär Mai Jul Sep Nov], sparse.map(&:text)
    # June's column sits at its first day of year (152), not at the month number (6).
    assert_equal "321.7", dense[5]["x"]
  end

  test "names only the fully empty day as having no data" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[100] = day(101, irradiance: 3.4)
    days[101] = day(102, cloud: 48.6)

    titles = render_calendar(days: days).css("[data-strip='pv'] .hits title").map(&:text)

    assert_equal "Sa 11.04.2026 · PV-Energie keine Daten · Einstrahlung 3,40 kWh/m² · Bewölkung keine Daten", titles[100]
    assert_equal "So 12.04.2026 · PV-Energie keine Daten · Einstrahlung keine Daten · Bewölkung Ø 49 %", titles[101]
  end
end
