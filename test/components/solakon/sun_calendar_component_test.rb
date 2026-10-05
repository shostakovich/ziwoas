require "test_helper"

class Solakon::SunCalendarComponentTest < ViewComponent::TestCase
  cover "Solakon::SunCalendarComponent*"

  def strip(key, title, unit, ramp, max, values)
    SunCalendar::Strip.new(key: key, title: title, unit: unit, ramp: ramp, max: max, values: values)
  end

  def calendar(pv: { [ 100, 12 ] => 600.0 }, irradiance: {}, cloud: {}, days: nil, lines: nil, hours: (3..22), seam: nil,
               pv_max: 800.0)
    days ||= (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map do |date|
      SunCalendar::Day.new(doy: date.yday, date: date, pv_kwh: nil, irradiance_kwh_per_m2: nil, cloud_avg: nil)
    end
    SunCalendar::Year.new(
      year: 2026,
      days: days,
      hours: hours,
      strips: {
        pv: strip(:pv, "PV-Leistung", "W", :amber, pv_max, pv),
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

  def wide(rendered, strip = "pv") = rendered.css("[data-strip='#{strip}'] svg.strip-chart-wide").sole

  def narrow(rendered, strip = "pv") = rendered.css("[data-strip='#{strip}'] svg.strip-chart-narrow").sole

  def bars(rendered, frame = "wide") = rendered.css("[data-strip='energy'] svg.energy-chart-#{frame}").sole

  def coloured(rendered, strip = "pv") = rendered.css("[data-strip='#{strip}'] .cells g:not(.nodata)")

  def coloured_cells(rendered, strip = "pv") = coloured(rendered, strip).css("rect")

  def nodata_cells(rendered, strip = "pv") = rendered.css("[data-strip='#{strip}'] .cells g.nodata rect")

  def steps(path)
    path["d"].scan(/V([\d.]+)H([\d.]+)/).map { |top, right| [ right.to_f, top.to_f ] }
  end

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
    svg = wide(render_calendar)

    assert_equal "0 0 720 194", svg["viewBox"]
    assert_nil svg["width"]
  end

  test "draws every strip twice: flat from a small tablet up, taller on a phone" do
    rendered = render_calendar

    assert_equal %w[strip-chart-wide d-none d-sm-block], wide(rendered)["class"].split
    assert_equal %w[strip-chart-narrow d-sm-none], narrow(rendered)["class"].split
    assert_equal "0 0 720 534", narrow(rendered)["viewBox"]
  end

  test "stretches the wide strip's cells onto the phone's taller rows instead of writing them twice" do
    rendered = render_calendar(pv: { [ 100, 12 ] => 800.0 })

    assert_equal "sun-cells-pv", wide(rendered).css("g.cells").sole["id"]
    assert_empty narrow(rendered).css("g.cells rect")
    use = narrow(rendered).css("use.cells").sole
    assert_equal "#sun-cells-pv", use["href"]
    assert_equal "matrix(1 0 0 3.125 0 -63.8)", use["transform"]
    assert_equal %w[sun-cells-pv sun-cells-irradiance sun-cells-cloud], rendered.css("g.cells").map { |node| node["id"] }
  end

  test "leaves the tooltips to the wide frames, which a pointer reaches" do
    rendered = render_calendar

    assert_equal 365, wide(rendered).css(".hits rect").length
    assert_empty narrow(rendered).css(".hits")
    assert_equal 365, bars(rendered).css(".hits rect").length
    assert_empty bars(rendered, "narrow").css(".hits")
  end

  test "paints a cell in the ramp colour of its value" do
    rendered = render_calendar(pv: { [ 100, 12 ] => 800.0 })

    assert_equal "fill: var(--ramp-amber-2)", coloured(rendered).sole["style"]
  end

  test "merges neighbouring days of equal colour into one rectangle" do
    values = (10..14).to_h { |doy| [ [ doy, 12 ], 400.0 ] }

    cells = coloured_cells(render_calendar(pv: values))

    assert_equal 1, cells.length
    assert_in_delta 5 * (720 - 60) / 365.0, cells.first["width"].to_f, 0.05
  end

  test "keeps a gap between days that are not neighbours" do
    values = { [ 10, 12 ] => 400.0, [ 12, 12 ] => 400.0 }
    rendered = render_calendar(pv: values)

    assert_equal 2, coloured_cells(rendered).length
    gap = nodata_cells(rendered).find { |cell| cell["y"] == coloured_cells(rendered).first["y"] && cell["x"].to_f > 70 && cell["x"].to_f < 80 }
    assert_in_delta (720 - 60) / 365.0, gap["width"].to_f, 0.05, "the day between them lies on the no-data ground"
  end

  test "lays the no-data ground only under hours without a value, so quiet hours stay translucent" do
    rendered = render_calendar

    assert_empty rendered.css("rect.nodata"), "no ground under the whole plot"
    assert_equal 1, coloured_cells(rendered).length
    assert_equal 21, nodata_cells(rendered).length
    assert_equal 1, rendered.css("[data-strip='pv'] .cells g.nodata").length
    assert_nil rendered.css("[data-strip='pv'] .cells g.nodata").sole["style"]
    noon = nodata_cells(rendered).select { |cell| cell["y"] == coloured_cells(rendered).sole["y"] }
    assert_equal [ [ "56", "179" ], [ "236.8", "479.2" ] ], noon.map { |cell| [ cell["x"], cell["width"] ] }
    assert_equal 20, nodata_cells(rendered, "irradiance").length, "a strip without values is ground from end to end"
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

    assert_equal 3, wide(rendered).css("polyline.sun").length
    assert_equal 3, narrow(rendered).css("polyline.sun").length
    assert_equal 0, rendered.css("[data-strip='energy'] polyline.sun, [data-strip='energy'] use").length

    assert_equal 365, wide(rendered).css("polyline.rise").first["points"].split.length
  end

  test "draws the sun lines once per frame and lets the other strips reuse them" do
    rendered = render_calendar(lines: year_lines((1..365).to_a))

    assert_equal %w[sun-lines-wide sun-lines-narrow], rendered.css("polyline.sun").map { |line| line.parent["id"] }.uniq
    assert_equal 6, rendered.css("polyline.sun").length, "three lines in each frame of the first strip, none elsewhere"
    %w[irradiance cloud].each do |strip|
      assert_empty wide(rendered, strip).css("polyline")
      assert_equal "#sun-lines-wide", wide(rendered, strip).css("use:not(.cells)").sole["href"]
      assert_equal "#sun-lines-narrow", narrow(rendered, strip).css("use:not(.cells)").sole["href"]
    end
  end

  test "reuses no sun lines without a location" do
    assert_empty render_calendar.css("use:not(.cells)")
  end

  test "lays a halo under every sun line, along the same points" do
    rendered = render_calendar(lines: year_lines((1..365).to_a))

    halos = wide(rendered).css("polyline.sun-halo")
    assert_equal 3, halos.length
    assert_equal wide(rendered).css("polyline.sun").map { |line| line["points"] }, halos.map { |halo| halo["points"] }
    assert_equal "polyline", halos.first.next_element.name
    assert_equal halos.first["points"], halos.first.next_element["points"]
    assert_operator narrow(rendered).css("polyline.rise").first["points"].split.first.split(",").last.to_f, :>,
                    wide(rendered).css("polyline.rise").first["points"].split.first.split(",").last.to_f,
                    "the phone's lines are measured against its own, taller rows"
  end

  test "breaks the sun lines where polar days leave a gap" do
    rendered = render_calendar(lines: year_lines((1..100).to_a + (260..365).to_a))

    rise = wide(rendered).css("polyline.rise")

    assert_equal 2, rise.length, "a polar gap must not be bridged by a straight line"
    assert_equal 100, rise.first["points"].split.length
    assert_equal 106, rise.last["points"].split.length
    assert_equal 6, wide(rendered).css("polyline.sun").length
  end

  test "breaks the sun lines even when only a single day is missing" do
    doys = (1..100).to_a + (102..365).to_a

    rise = wide(render_calendar(lines: year_lines(doys))).css("polyline.rise")

    assert_equal 2, rise.length, "a single missing day must still start a new segment"
    assert_equal 100, rise.first["points"].split.length
    assert_equal 264, rise.last["points"].split.length
  end

  test "keeps the daylight saving seam inside one segment" do
    doys = (1..90).to_a + [ 90 ] + (91..365).to_a

    rise = wide(render_calendar(lines: year_lines(doys))).css("polyline.rise")

    assert_equal 1, rise.length
    assert_equal 366, rise.first["points"].split.length
  end

  test "marks the day the inverter took over from the plug" do
    rendered = render_calendar(seam: Date.new(2026, 6, 20))

    seam = wide(rendered).css("line.seam")

    assert_equal 1, seam.length
    assert_equal "363.4", seam.first["x1"]
    assert_equal seam.first["x1"], seam.first["x2"]
    assert_equal [ "363.4", "30", "530" ], %w[x1 y1 y2].map { |name| narrow(rendered).css("line.seam").sole[name] }
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
    rendered = render_calendar

    assert_equal %w[26 190], %w[y1 y2].map { |name| wide(rendered).css(".grid line").first[name] }
    assert_equal %w[26 530], %w[y1 y2].map { |name| narrow(rendered).css(".grid line").first[name] }
  end

  test "labels the wide frame densely and the phone's sparsely" do
    rendered = render_calendar

    assert_equal 12, wide(rendered).css(".month-labels.label-dense text").length
    assert_empty wide(rendered).css(".label-sparse")
    assert_equal 6, narrow(rendered).css(".month-labels.label-sparse text").length
    assert_empty narrow(rendered).css(".label-dense")
    assert_operator wide(rendered).css(".hour-labels.label-dense text").length, :>,
                    narrow(rendered).css(".hour-labels.label-sparse text").length
    assert_equal %w[label-dense label-sparse], rendered.css("[data-strip='energy'] .month-labels").map { |node| node["class"].split.last }
  end

  test "gives every day a tooltip with its numbers" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 4.213, irradiance: 3.4, cloud: 48.6)

    rendered = render_calendar(days: days)
    titles = wide(rendered).css(".hits title").map(&:text)

    assert_equal 365, titles.length
    assert_equal "Fr 10.04.2026 · PV-Energie 4,21 kWh · Einstrahlung 3,40 kWh/m² · Bewölkung Ø 49 %", titles[99]
    assert_equal "Do 01.01.2026 · keine Daten", titles[0]
  end

  test "names the missing halves of a partly measured day" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 4.213)

    title = wide(render_calendar(days: days)).css(".hits title")[99].text

    assert_equal "Fr 10.04.2026 · PV-Energie 4,21 kWh · Einstrahlung keine Daten · Bewölkung keine Daten", title
  end

  test "outlines neighbouring days with PV energy as one area, each day at its own height" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 4.0)
    days[100] = day(101, pv_kwh: 2.0)

    area = bars(render_calendar(days: days)).css(".bars path").sole

    assert_equal "M235 130V30H236.8V80H238.6V130Z", area["d"]
    assert_equal [ [ 236.8, 30.0 ], [ 238.6, 80.0 ] ], steps(area)
  end

  test "breaks the area where a day has no PV energy" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 4.0)
    days[101] = day(102, pv_kwh: 0.0)

    areas = bars(render_calendar(days: days)).css(".bars path")

    assert_equal 2, areas.length
    assert_equal [ [ 240.4, 130.0 ] ], steps(areas.last), "a day of zero still stands on the axis"
  end

  test "puts the maximum and the unit into every strip's legend" do
    legends = render_calendar.css(".sun-calendar .legend").map(&:text)

    assert_equal 3, legends.length, "the daily energy's title already says what its bars are"
    assert_match(/800\b.*W\b/, legends[0])
    assert_match(/900\b.*W\/m²/, legends[1])
    assert_match(/100\b.*%/, legends[2])
    assert_includes render_calendar.css("[data-strip='energy']").text, "Tage ohne Stundenwerte bleiben leer."
  end

  test "writes a legend's maximum from a thousand on with a thousands dot" do
    legend = render_calendar(pv_max: 1200.0).css("[data-strip='pv'] .legend-item").first.text

    assert_equal "01.200 W", legend, "the ramp runs from 0 to 1.200 W"
  end

  test "widens the strip when data sits outside the base hours" do
    rendered = render_calendar(hours: (1..23))

    assert_equal "0 0 720 218", wide(rendered)["viewBox"]
    assert_equal "0 0 720 609", narrow(rendered)["viewBox"]
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
    chart = bars(render_calendar(days: days), "narrow")

    assert_equal "M235 270V30H236.8V270Z", chart.css(".bars path").sole["d"]
    assert_equal %w[56 716 270 270], %w[x1 x2 y1 y2].map { |name| chart.css("line.axis").sole[name] }
    assert_equal %w[0 1 2], chart.css(".hour-labels text").map(&:text), "the top step gives way to the unit"
    assert_equal %w[270 190 110], chart.css(".hour-labels text").map { |label| label["y"] }
    assert_equal "275", chart.css(".month-labels.label-sparse text").first["y"]
  end

  test "stands the energy axis' zero on the axis, clear of the month below" do
    labels = bars(render_calendar(days: [ day(1, pv_kwh: 4.0), *(2..365).map { |doy| day(doy) } ])).css(".hour-labels text")

    assert_equal %w[zero], labels.first["class"].split
    assert_equal [ nil ], labels.drop(1).map { |label| label["class"] }.uniq
  end

  test "names the energy axis' unit above it, over the plot's left edge" do
    units = render_calendar.css("[data-strip='energy'] text.unit")

    assert_equal [ [ "kWh", "56", "24" ] ] * 2, units.map { |node| [ node.text, node["x"], node["y"] ] }
  end

  test "measures the ground, the cells, the bars, the sun lines and the hits against the same axes" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 3.0)
    rendered = render_calendar(days: days, pv: { [ 10, 12 ] => 800.0 }, lines: year_lines((1..365).to_a))

    ground = nodata_cells(rendered)
    assert_equal [ "56", "30" ], [ ground.first["x"], ground.first["y"] ]
    assert_equal "190", ground.map { |rect| Plot.number(rect["y"].to_f + rect["height"].to_f) }.max.to_s

    cell = coloured_cells(rendered).sole
    assert_equal %w[72.3 102 1.8 8], %w[x y width height].map { |name| cell[name] }

    hit = wide(rendered).css(".hits rect")[99]
    assert_equal %w[235 30 1.8 160], %w[x y width height].map { |name| hit[name] }

    axis = bars(rendered).css("line.axis").sole
    assert_equal %w[56 716 130 130], %w[x1 x2 y1 y2].map { |name| axis[name] }

    assert_equal "M235 130V30H236.8V130Z", bars(rendered).css(".bars path").sole["d"]

    energy_hit = bars(rendered).css(".hits rect").first
    assert_equal %w[30 100], %w[y height].map { |name| energy_hit[name] }

    rise = wide(rendered).css("polyline.rise").first["points"].split
    assert_equal "56,70", rise.first
    assert_equal "714.2,70", rise.last

    hour = wide(rendered).css(".hour-labels.label-dense text").first
    assert_equal %w[51 54], [ hour["x"], hour["y"] ]

    month = wide(rendered).css(".month-labels.label-dense text").first
    assert_equal %w[58 24], [ month["x"], month["y"] ]
  end

  test "draws the month grid lines at each month's first day of year" do
    rendered = render_calendar
    x_values = wide(rendered).css(".grid line").map { |line| line["x1"] }

    expected = [ 56, 112.1, 162.7, 218.7, 273, 329, 383.3, 439.3, 495.4, 549.6, 605.7, 659.9 ]
    assert_equal expected.map(&:to_s), x_values
    assert_equal x_values, narrow(rendered).css(".grid line").map { |line| line["x1"] }
  end

  test "shows the ramp's css gradient in the legend" do
    style = render_calendar.css("[data-strip='pv'] .legend-ramp").first["style"]

    assert_includes style, Ramp.fetch(:amber).css_gradient
  end

  test "ceils the year's best day to the next whole kWh for the axis maximum" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 3.3)

    area = bars(render_calendar(days: days)).css(".bars path").sole

    assert_in_delta 130 - (3.3 / 4.0 * 100), steps(area).sole.last, 0.05
  end

  test "keeps the axis maximum at one kWh, not two, when the best day is exactly one" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 1.0)

    area = bars(render_calendar(days: days)).css(".bars path").sole

    assert_equal 30.0, steps(area).sole.last
  end

  test "labels the PV-energy axis at even kWh steps, ceiling the step to fill the range" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 10.0)

    labels = bars(render_calendar(days: days)).css(".hour-labels text")

    assert_equal %w[0 3 6 9], labels.map(&:text)
    assert_equal %w[130 100 70 40], labels.map { |label| label["y"] }
  end

  test "keeps the kWh grid labels clear of the axis, rounded to one decimal" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 11.0)

    labels = bars(render_calendar(days: days)).css(".hour-labels text")

    assert_equal %w[51 51 51 51], labels.map { |label| label["x"] }
    assert_equal %w[130 102.7 75.5 48.2], labels.map { |label| label["y"] }
  end

  test "draws a grid line at each labeled kWh height above zero, spanning the full width" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 11.0)

    lines = bars(render_calendar(days: days)).css(".grid line").select { |line| line["y1"] == line["y2"] }

    assert_equal %w[102.7 75.5 48.2], lines.map { |line| line["y1"] }, "the axis stands for zero"
    assert_equal %w[56 56 56], lines.map { |line| line["x1"] }
    assert_equal %w[716 716 716], lines.map { |line| line["x2"] }
  end

  test "hangs the energy chart's month labels just under the axis, clear of the bars" do
    label = bars(render_calendar).css(".month-labels.label-dense text").first

    assert_equal "135", label["y"]
  end

  test "colours a cell by its share of the strip's maximum, not by the raw value" do
    rendered = render_calendar(pv: { [ 10, 12 ] => 400.0 })

    fill = coloured(rendered).sole["style"]

    assert_equal "fill: #{Ramp.fetch(:amber).color(0.5)}", fill
  end

  test "rounds the colour share to the nearest level instead of using the raw fraction" do
    # 390 / 800 falls between two levels: rounding first picks a different stop.
    rendered = render_calendar(pv: { [ 10, 12 ] => 390.0 })

    fill = coloured(rendered).sole["style"]

    assert_equal "fill: color-mix(in oklab, var(--ramp-amber-1) 96.9%, var(--ramp-amber-0))", fill
  end

  test "includes both the year's first and last day in the heat strip" do
    values = { [ 1, 12 ] => 200.0, [ 365, 12 ] => 800.0 }

    rects = coloured_cells(render_calendar(pv: values))

    assert_equal 2, rects.length
    assert_equal "56", rects.first["x"]
  end

  test "keeps adjacent days with different values as separate rectangles" do
    values = { [ 10, 12 ] => 200.0, [ 11, 12 ] => 800.0 }

    rects = coloured_cells(render_calendar(pv: values))

    assert_equal 2, rects.length
  end

  test "labels the hour axis as clock times where there is room and as bare hours on the phone" do
    rendered = render_calendar

    dense = wide(rendered).css(".hour-labels.label-dense text")
    sparse = narrow(rendered).css(".hour-labels.label-sparse text")

    assert_equal %w[06:00 09:00 12:00 15:00 18:00 21:00], dense.map(&:text)
    assert_equal %w[06 12 18], sparse.map(&:text)
    assert_equal [ %w[51 105], %w[51 255], %w[51 405] ], sparse.map { |label| [ label["x"], label["y"] ] }
  end

  test "keeps the hour labels on the clock's step and two rows clear of the month labels" do
    rendered = render_calendar(hours: (4..20))

    assert_equal %w[06:00 09:00 12:00 15:00 18:00], wide(rendered).css(".hour-labels.label-dense text").map(&:text)

    rendered = render_calendar(hours: (5..20))

    assert_equal %w[09:00 12:00 15:00 18:00], wide(rendered).css(".hour-labels.label-dense text").map(&:text)
    assert_equal %w[12 18], narrow(rendered).css(".hour-labels.label-sparse text").map(&:text)
  end

  test "labels the month axis at the dense and sparse step, offset from the day column" do
    rendered = render_calendar

    dense = wide(rendered).css(".month-labels.label-dense text")
    sparse = narrow(rendered).css(".month-labels.label-sparse text")

    assert_equal %w[Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez], dense.map(&:text)
    assert_equal %w[Jan Mär Mai Jul Sep Nov], sparse.map(&:text)
    assert_equal "331", dense[5]["x"]
  end

  test "names only the fully empty day as having no data" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[100] = day(101, irradiance: 3.4)
    days[101] = day(102, cloud: 48.6)

    titles = wide(render_calendar(days: days)).css(".hits title").map(&:text)

    assert_equal "Sa 11.04.2026 · PV-Energie keine Daten · Einstrahlung 3,40 kWh/m² · Bewölkung keine Daten", titles[100]
    assert_equal "So 12.04.2026 · PV-Energie keine Daten · Einstrahlung keine Daten · Bewölkung Ø 49 %", titles[101]
  end
end
