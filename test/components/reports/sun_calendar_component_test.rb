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

  test "draws sunrise, sunset and solar noon across the whole year" do
    lines = SunCalendar::Lines.new(
      rise: [ [ 1, 8.0 ], [ 365, 8.2 ] ], set: [ [ 1, 16.0 ], [ 365, 15.8 ] ], noon: [ [ 1, 12.0 ], [ 365, 12.0 ] ]
    )

    rendered = render_calendar(lines: lines)

    assert_equal 3, rendered.css("[data-strip='pv'] polyline.sun").length
    assert_equal 3, rendered.css("[data-strip='cloud'] polyline.sun").length
    assert_equal 0, rendered.css("[data-strip='energy'] polyline.sun").length
    assert_equal "26,62 714.1,63.6", rendered.css("[data-strip='pv'] polyline.rise").first["points"]
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
end
