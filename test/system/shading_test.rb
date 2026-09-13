require_relative "application_system_test_case"

class ShadingTest < ApplicationSystemTestCase
  LAT = 52.52
  LON = 13.405

  setup do
    Solakon::PvHour.delete_all
    WeatherRecord.delete_all
    seed_hours
  end

  test "the PV page shows the sky map, the months and the four panels" do
    visit solakon_path

    # The section labels are uppercased via CSS, so the browser reports them in caps.
    assert_text(/Ausbeute nach Sonnenstand/i)
    assert_text(/Tagesgang je Monat/i)
    assert_text(/Die vier Panels im Tagesverlauf/i)

    assert_selector ".shading [data-chart='yield-map'] .fields rect", minimum: 20, visible: :all
    assert_selector ".shading [data-chart='yield-map'] polyline.sun", count: 3, visible: :all
    assert_selector ".shading [data-chart='daily-profiles'] .multiple", count: 3
    assert_selector ".shading [data-chart='panels'] polyline", count: 4, visible: :all

    titles = page.all("[data-chart='yield-map'] .fields rect title", visible: :all).map(&:text)
    assert_match(/Azimut \d+–\d+° · Höhe \d+–\d+° · Ausbeute \d+ % · \d+ Stunden/, titles.first)
  end

  test "the section switches to the sparse labels on a phone and stays inside the screen" do
    page.current_window.resize_to(390, 844)

    visit solakon_path

    assert_selector ".shading [data-chart='yield-map'] .label-sparse text", visible: true, minimum: 1
    assert_no_selector ".shading [data-chart='yield-map'] .label-dense text", visible: true

    overflow = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    assert_operator overflow, :<=, 0, "the page must not scroll sideways"
  end

  private

  # Three months of clear-ish days, with the fourth panel behind the other
  # three so the panel comparison has something to tell apart.
  def seed_hours
    hours = []
    records = []
    (Date.new(2026, 6, 1)..Date.new(2026, 8, 31)).each do |date|
      (4..20).each do |hour|
        at = Time.zone.local(date.year, date.month, date.day, hour)
        irradiance = [ 0.0, 900 * Math.sin((hour - 4) / 16.0 * Math::PI) ].max
        power = (irradiance * 0.78).round(1)
        hours << {
          started_at: at, pv_power_w: power, reading_count: 120,
          pv1_power_w: (power * 0.3).round(1), pv2_power_w: (power * 0.3).round(1),
          pv3_power_w: (power * 0.25).round(1), pv4_power_w: (power * 0.15).round(1)
        }
        records << {
          kind: "historic", daytime: "day", lat: LAT, lon: LON, timestamp: at,
          solar: (irradiance / 1000.0).round(4), cloud_cover: 20, icon: "partly-cloudy-day",
          created_at: Time.current, updated_at: Time.current
        }
      end
    end
    Solakon::PvHour.insert_all(hours)
    WeatherRecord.insert_all(records)
  end
end
