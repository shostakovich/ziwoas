# test/controllers/sensors_controller_test.rb
require "test_helper"

class SensorsControllerTest < ActionDispatch::IntegrationTest
  test "GET /sensors returns 200" do
    get "/sensors"
    assert_response :success
  end

  test "GET /sensors shows a card per sensor with the CO₂ traffic light" do
    SensorReading.delete_all
    SensorReading.create!(device_id: "TEST_INDOOR",  taken_at: 5.minutes.ago,
                          temperature: 21.0, humidity: 50, co2: 1200, battery_pct: 90)
    SensorReading.create!(device_id: "TEST_OUTDOOR", taken_at: 5.minutes.ago,
                          temperature: 12.0, humidity: 70, battery_pct: 100)

    get "/sensors"

    assert_select "turbo-frame#sensors_dashboard .card", text: /Test Wohnzimmer/ do
      assert_select "img[alt=?][src*=?]", "CO₂-Ampel warn", "co2_warn"
      assert_select "li", text: /1200\s*ppm/
    end
    assert_select "turbo-frame#sensors_dashboard .card", text: /Test Balkon/ do
      assert_select "img[alt^=?]", "CO₂-Ampel", count: 0
    end
    assert_select ".alert", count: 0
    assert_select "section[aria-label=Sensoren].row-cols-sm-2.row-cols-lg-2", 1,
      "two sensors fill a row of two on desktops instead of leaving a third slot empty"
    assert_select "[data-controller=sensors-chart] canvas", count: 3
    # Only the living room measures CO₂: its chart names the room instead of a legend.
    assert_select "[data-controller=sensors-chart] .card-subtitle", text: "ppm · Test Wohnzimmer · letzte 24 h"
    assert_select "[data-controller=sensors-chart] .card-subtitle", text: "°C · letzte 24 h"
    assert_select "[data-controller=sensors-chart] .card-subtitle", text: "Prozent · letzte 24 h"
  end

  test "GET /sensors warns about sensors with a low battery" do
    SensorReading.delete_all
    SensorReading.create!(device_id: "TEST_INDOOR",  taken_at: 5.minutes.ago,
                          temperature: 21.0, co2: 600, battery_pct: 90)
    SensorReading.create!(device_id: "TEST_OUTDOOR", taken_at: 5.minutes.ago,
                          temperature: 12.0, battery_pct: 15)

    get "/sensors"

    assert_select ".alert.alert-warning[role=alert]", text: /Batterie schwach:\s*Test Balkon/
    assert_select ".alert", text: /Test Wohnzimmer/, count: 0
  end

  test "GET /sensors shows the empty state without readings" do
    SensorReading.delete_all

    get "/sensors"

    assert_select ".empty-state", text: /Noch keine Sensordaten/
    assert_select "[data-controller=sensors-chart]", count: 0
  end

  test "GET /sensors/series returns JSON with three series" do
    SensorReading.delete_all
    SensorReading.create!(device_id: "TEST_INDOOR",  taken_at: 30.minutes.ago,
                          temperature: 21.0, humidity: 50, co2: 700, battery_pct: 90)
    SensorReading.create!(device_id: "TEST_OUTDOOR", taken_at: 30.minutes.ago,
                          temperature: 12.0, humidity: 70, battery_pct: 100)

    get "/sensors/series"
    assert_response :success
    body = JSON.parse(@response.body)
    assert body.key?("temperature")
    assert body.key?("humidity")
    assert body.key?("co2")

    indoor_temp = body["temperature"].find { |s| s["device_id"] == "TEST_INDOOR" }
    assert_equal 1, indoor_temp["points"].length
    assert_equal 21.0, indoor_temp["points"][0][1]

    co2_devices = body["co2"].map { |s| s["device_id"] }
    refute_includes co2_devices, "TEST_OUTDOOR"
  end
end
