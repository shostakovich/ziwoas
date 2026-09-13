require "test_helper"

class Reports::SunCalendarComponentTest < ViewComponent::TestCase
  cover "Reports::SunCalendarComponent*"

  def strip(key, title, unit, ramp, max, values)
    SunCalendar::Strip.new(key: key, title: title, unit: unit, ramp: ramp, max: max, values: values)
  end

  def calendar(pv: { [ 100, 12 ] => 600.0 }, irradiance: {}, cloud: {}, days: nil, lines: nil, hours: (3..22))
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
      lines: lines || SunCalendar::Lines.new(rise: [], set: [], noon: [])
    )
  end

  def day(doy, pv_kwh: nil, irradiance: nil, cloud: nil)
    date = Date.new(2026, 1, 1) + (doy - 1)
    SunCalendar::Day.new(doy: doy, date: date, pv_kwh: pv_kwh, irradiance_kwh_per_m2: irradiance, cloud_avg: cloud)
  end

  def render_calendar(**options) = render_inline(Reports::SunCalendarComponent.new(calendar: calendar(**options)))

  test "stacks the three strips and the daily bars on one time axis" do
    rendered = render_calendar

    assert_equal %w[pv irradiance cloud energy], rendered.css("[data-strip]").map { |node| node["data-strip"] }
    titles = rendered.css(".sun-calendar h3").map(&:text)
    assert_equal [ "PV-Leistung", "Einstrahlung", "Bewölkung", "PV-Energie je Tag" ], titles
  end

  test "shows the empty state while no PV hour exists" do
    rendered = render_inline(Reports::SunCalendarComponent.new(calendar: calendar(pv: {})))

    assert_selector ".empty-state"
    assert_text "Stundenwerte"
    assert_equal 0, rendered.css("svg").length
  end

  test "scales over the viewBox instead of a fixed size" do
    svg = render_calendar.css("[data-strip='pv'] svg").first

    assert_equal "0 0 720 186", svg["viewBox"]
    assert_nil svg["width"]
  end

  test "paints a cell in the ramp colour of its value" do
    rendered = render_calendar(pv: { [ 100, 12 ] => 800.0 })

    group = rendered.css("[data-strip='pv'] .cells g").first

    assert_equal "#a85300", group["fill"]
    assert_equal "8", group.css("rect").first["height"]
  end

  test "merges neighbouring days of equal colour into one rectangle" do
    values = (10..14).to_h { |doy| [ [ doy, 12 ], 400.0 ] }

    cells = render_calendar(pv: values).css("[data-strip='pv'] .cells rect")

    assert_equal 1, cells.length
    assert_in_delta 5 * (720 - 30) / 365.0, cells.first["width"].to_f, 0.05
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

    points = rendered.css("[data-strip='pv'] polyline.rise").first["points"].split
    assert_equal 365, points.length
    assert_equal "26,62", points.first
    assert_equal "714.1,62", points.last
  end

  test "breaks the sun lines where polar days leave a gap" do
    rendered = render_calendar(lines: year_lines((1..100).to_a + (260..365).to_a))

    rise = rendered.css("[data-strip='pv'] polyline.rise")

    assert_equal 2, rise.length, "a polar gap must not be bridged by a straight line"
    assert_equal 100, rise.first["points"].split.length
    assert_equal 106, rise.last["points"].split.length
    assert_equal 6, rendered.css("[data-strip='pv'] polyline.sun").length
  end

  test "keeps the daylight saving seam inside one segment" do
    doys = (1..90).to_a + [ 90 ] + (91..365).to_a

    rise = render_calendar(lines: year_lines(doys)).css("[data-strip='pv'] polyline.rise")

    assert_equal 1, rise.length
    assert_equal 366, rise.first["points"].split.length
  end

  test "leaves the sun lines out without a location" do
    assert_equal 0, render_calendar.css("polyline.sun").length
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

    bars = render_calendar(days: days).css("[data-strip='energy'] .bars rect")

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

    assert_equal "0 0 720 210", svg["viewBox"]
  end

  test "sizes the energy chart's viewBox from the bars height and bottom margin" do
    svg = render_calendar.css("[data-strip='energy'] svg").first

    assert_equal "0 0 720 146", svg["viewBox"]
  end

  test "draws the plot at the fixed left margin and the axis at the bars height" do
    rendered = render_calendar

    assert_equal "26", rendered.css("[data-strip='pv'] rect.nodata").first["x"]
    axis = rendered.css("[data-strip='energy'] line.axis").first
    assert_equal "26", axis["x1"]
    assert_equal "716", axis["x2"]
    assert_equal "122", axis["y1"]
    assert_equal "122", axis["y2"]
    assert_equal "22", rendered.css("[data-strip='energy'] .hits rect").first["y"]
    assert_equal "100", rendered.css("[data-strip='energy'] .hits rect").first["height"]
  end

  test "spans the no-data ground across every day of the year" do
    assert_equal "690", render_calendar.css("[data-strip='pv'] rect.nodata").first["width"]
  end

  test "draws the month grid lines at each month's first day of year" do
    x_values = render_calendar.css("[data-strip='pv'] .grid line").map { |line| line["x1"] }

    expected = [ 26, 84.6, 137.5, 196.1, 252.8, 311.5, 368.2, 426.8, 485.4, 542.1, 600.7, 657.4 ]
    assert_equal expected.map(&:to_s), x_values
  end

  test "shows the ramp's css gradient in the legend" do
    style = render_calendar.css("[data-strip='pv'] .legend-ramp").first["style"]

    assert_includes style, SunCalendar::Ramp.fetch(:amber).css_gradient
  end

  test "draws a bar at the exact position and size the day's energy scales to" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 3.0)

    bar = render_calendar(days: days).css("[data-strip='energy'] .bars rect").first

    assert_equal "213.2", bar["x"]
    assert_equal "22", bar["y"]
    assert_equal "1.5", bar["width"]
    assert_equal "100", bar["height"]
  end

  test "keeps the bar width from collapsing below half a pixel on a very dense calendar" do
    # At 3000 columns day_width - 0.4 goes negative, well clear of the 0.5 floor,
    # so this proves the floor actually binds rather than coinciding with it.
    days = (1..3000).map { |doy| SunCalendar::Day.new(doy: doy, date: Date.new(2026, 1, 1), pv_kwh: nil, irradiance_kwh_per_m2: nil, cloud_avg: nil) }
    days[1499] = SunCalendar::Day.new(doy: 1500, date: Date.new(2026, 1, 1), pv_kwh: 1.0, irradiance_kwh_per_m2: nil, cloud_avg: nil)

    bar = render_calendar(days: days).css("[data-strip='energy'] .bars rect").first

    assert_equal "0.5", bar["width"]
  end

  test "ceils the year's best day to the next whole kWh for the axis maximum" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 3.3)

    bar = render_calendar(days: days).css("[data-strip='energy'] .bars rect").first

    # bars_max ceils 3.3 to 4, so the bar reaches only 3.3 / 4 of the chart height.
    assert_in_delta 3.3 / 4.0 * 100, bar["height"].to_f, 0.05
  end

  test "keeps the axis maximum at one kWh, not two, when the best day is exactly one" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 1.0)

    bar = render_calendar(days: days).css("[data-strip='energy'] .bars rect").first

    assert_equal "100", bar["height"]
  end

  test "labels the PV-energy axis at even kWh steps, ceiling the step to fill the range" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 10.0)

    labels = render_calendar(days: days).css("[data-strip='energy'] .hour-labels text")

    assert_equal %w[3 6 9], labels.map(&:text)
    assert_equal %w[95.5 65.5 35.5], labels.map { |label| label["y"] }
  end

  test "rounds an axis label's position to one decimal instead of the raw fraction" do
    days = (Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).map { |date| day(date.yday) }
    days[99] = day(100, pv_kwh: 7.0)

    labels = render_calendar(days: days).css("[data-strip='energy'] .hour-labels text")

    assert_equal %w[2 4 6], labels.map(&:text)
    assert_equal %w[96.9 68.4 39.8], labels.map { |label| label["y"] }
  end

  test "gives every day's hit its exact position and width" do
    hit = render_calendar.css("[data-strip='pv'] .hits rect")[99]

    assert_equal "213.2", hit["x"]
    assert_equal "1.9", hit["width"]
  end

  test "positions a cell rectangle at its day and hour" do
    rendered = render_calendar(pv: { [ 10, 12 ] => 800.0 })

    rect = rendered.css("[data-strip='pv'] .cells rect").first

    assert_equal "43", rect["x"]
    assert_equal "94", rect["y"]
    assert_equal "1.9", rect["width"]
  end

  test "colours a cell by its share of the strip's maximum, not by the raw value" do
    rendered = render_calendar(pv: { [ 10, 12 ] => 400.0 })

    fill = rendered.css("[data-strip='pv'] .cells g").first["fill"]

    assert_equal SunCalendar::Ramp.fetch(:amber).color(0.5), fill
  end

  test "rounds the colour share to the nearest level instead of using the raw fraction" do
    # 390 / 800 lands between two colour levels; rounding first picks a visibly
    # different stop than dividing the unrounded fraction straight through.
    rendered = render_calendar(pv: { [ 10, 12 ] => 390.0 })

    fill = rendered.css("[data-strip='pv'] .cells g").first["fill"]

    assert_equal "#f8b938", fill
  end

  test "includes both the year's first and last day in the heat strip" do
    values = { [ 1, 12 ] => 200.0, [ 365, 12 ] => 800.0 }

    rects = render_calendar(pv: values).css("[data-strip='pv'] .cells rect")

    assert_equal 2, rects.length
    assert_equal "26", rects.first["x"]
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

    assert_equal %w[3 6 9 12 15 18 21], dense.map(&:text)
    assert_equal %w[3 9 15 21], sparse.map(&:text)
    assert_equal "21", dense.first["x"]
    assert_equal "25.5", dense.first["y"]
  end

  test "labels the month axis at the dense and sparse step, offset from the day column" do
    rendered = render_calendar

    dense = rendered.css("[data-strip='pv'] .month-labels.label-dense text")
    sparse = rendered.css("[data-strip='pv'] .month-labels.label-sparse text")

    assert_equal %w[Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez], dense.map(&:text)
    assert_equal %w[Jan Mär Mai Jul Sep Nov], sparse.map(&:text)
    assert_equal "28", dense.first["x"]
    assert_equal "16", dense.first["y"]
    # June's column sits at its first day of year (152), not at the month number (6).
    assert_equal "313.5", dense[5]["x"]
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
