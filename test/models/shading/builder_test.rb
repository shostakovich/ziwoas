require "test_helper"

class Shading::BuilderTest < ActiveSupport::TestCase
  cover "Shading::Builder*"

  LAT = 52.52
  LON = 13.405
  JULY = Date.new(2026, 7, 1)

  setup do
    Solakon::PvHour.delete_all
    WeatherRecord.delete_all
  end

  def pv_hour(local_hour, watts, date: JULY, panels: [ 100.0, 100.0, 100.0, 100.0 ])
    Solakon::PvHour.create!(
      started_at: Time.zone.local(date.year, date.month, date.day, local_hour),
      pv_power_w: watts, reading_count: 120,
      pv1_power_w: panels[0], pv2_power_w: panels[1], pv3_power_w: panels[2], pv4_power_w: panels[3]
    )
  end

  def weather(local_hour, solar:, date: JULY, lat: LAT, lon: LON)
    WeatherRecord.create!(
      kind: "historic", daytime: "day", lat: lat, lon: lon,
      timestamp: Time.zone.local(date.year, date.month, date.day, local_hour), solar: solar
    )
  end

  def build(lat: LAT, lon: LON) = Shading::Builder.new(timezone: "Europe/Berlin", lat: lat, lon: lon).build

  test "reads the day's shape from the PV hours alone" do
    pv_hour(12, 640.0)

    profile = build.profiles.sole

    assert_equal 7, profile.month
    assert_equal [ [ 12, 640.0 ] ], profile.curve(:measured).points
  end

  test "joins the station's irradiance of the same hour onto the PV hour" do
    pv_hour(12, 400.0)
    weather(12, solar: 0.5)

    profile = build.profiles.sole

    assert_equal [ [ 12, 400.0 ] ], profile.curve(:expected).points
  end

  test "ignores the irradiance measured somewhere else" do
    pv_hour(12, 400.0)
    weather(12, solar: 0.5, lat: 48.15, lon: 11.26)

    assert_empty build.profiles.sole.curve(:expected).points
  end

  test "calibrates on the best hour and shrugs off a single outlier" do
    20.times { |index| pv_hour(12, 400.0, date: Date.new(2026, 7, 1 + index)) }
    20.times { |index| weather(12, solar: 0.5, date: Date.new(2026, 7, 1 + index)) }
    pv_hour(12, 2000.0, date: Date.new(2026, 8, 1))
    weather(12, solar: 0.5, date: Date.new(2026, 8, 1))

    august = build.profiles.find { |profile| profile.month == 8 }

    # 0.8 W per W/m², the ratio of the twenty ordinary hours, not the outlier's 4.0.
    assert_equal [ [ 12, 400.0 ] ], august.curve(:expected).points
  end

  test "places the hour where the sun stood over the house" do
    3.times { |index| pv_hour(12, 400.0, date: JULY + index) }
    3.times { |index| weather(12, solar: 0.5, date: JULY + index) }

    bin = build.map.bins.sole

    assert_equal [ 160, 55 ], [ bin.azimuth, bin.elevation ]
    assert_equal 3, bin.hours
  end

  test "draws the sun paths under the map, whatever the hours cover" do
    pv_hour(12, 400.0, date: Date.new(2025, 7, 1))

    assert_equal [ "21.6.", "21.3. / 23.9.", "21.12." ], build.map.paths.map(&:label)
  end

  test "keeps the measured curve without a location, and nothing that needs one" do
    pv_hour(12, 400.0)

    report = build(lat: nil, lon: nil)
    profile = report.profiles.sole

    assert_empty report.map.bins
    assert_empty report.map.paths
    assert_equal [ [ 12, 400.0 ] ], profile.curve(:measured).points
    assert_empty profile.curve(:theory).points
  end

  test "counts the panels of the days on which all four delivered" do
    pv_hour(12, 400.0, panels: [ 100.0, 100.0, 0.0, 0.0 ], date: JULY)
    pv_hour(12, 400.0, panels: [ 100.0, 100.0, 50.0, 50.0 ], date: JULY + 1)

    panels = build.panels

    assert_equal 1, panels.days
    assert_equal [ [ 12, 50.0 ] ], panels.curve(:pv3).points
  end

  test "is empty while no PV hour has been aggregated" do
    assert build.empty?
  end
end
