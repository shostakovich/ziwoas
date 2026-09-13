require_relative "application_system_test_case"

class SunCalendarTest < ApplicationSystemTestCase
  LAT = 52.52
  LON = 13.405

  setup do
    Solakon::PvHour.delete_all
    WeatherRecord.delete_all
    Plugs::DailyTotal.delete_all
    DailyEnergySummary.delete_all
    seed_year
  end

  test "the sun calendar stacks four boxes on the reports page" do
    visit reports_path

    # The section label is uppercased via CSS, so the browser reports it in caps.
    assert_text(/Sonnenkalender 2026/i)
    assert_selector ".sun-calendar [data-strip]", count: 4
    assert_selector ".sun-calendar [data-strip='pv'] polyline.sun", count: 3, visible: :all
    assert_selector ".sun-calendar [data-strip='energy'] .bars rect", minimum: 30, visible: :all

    widths = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(".sun-calendar svg")).map((svg) => svg.getBoundingClientRect().width);
    JS

    assert_equal 1, widths.uniq.length, "all four boxes share one time axis"
  end

  test "the sun calendar switches to the sparse labels on a phone" do
    page.current_window.resize_to(390, 844)

    visit reports_path

    assert_selector ".sun-calendar .month-labels.label-sparse text", visible: true, minimum: 1
    assert_no_selector ".sun-calendar .month-labels.label-dense text", visible: true

    overflow = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    assert_operator overflow, :<=, 0, "the page must not scroll sideways"
  end

  private

  def seed_year
    Plugs::DailyTotal.create!(plug_id: "bkw", date: "2026-04-10", energy_wh: 2000)
    DailyEnergySummary.create!(date: "2026-04-10", produced_wh: 2000.0, consumed_wh: 1000.0, self_consumed_wh: 500.0)

    hours = []
    records = []
    (Date.new(2026, 3, 1)..Date.new(2026, 5, 31)).each do |date|
      clouds = 50 + 40 * Math.sin(date.yday / 5.0)
      (4..20).each do |hour|
        at = Time.zone.local(date.year, date.month, date.day, hour)
        irradiance = [ 0.0, 900 * Math.sin((hour - 4) / 16.0 * Math::PI) * (1 - clouds / 200.0) ].max
        hours << { started_at: at, pv_power_w: (irradiance * 0.78).round(1), reading_count: 120 }
        records << {
          kind: "historic", daytime: "day", lat: LAT, lon: LON, timestamp: at,
          solar: (irradiance / 1000.0).round(4), cloud_cover: clouds.round, icon: "partly-cloudy-day",
          created_at: Time.current, updated_at: Time.current
        }
      end
    end
    Solakon::PvHour.insert_all(hours)
    WeatherRecord.insert_all(records)
  end
end
