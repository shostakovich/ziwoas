require "test_helper"

class SolakonControllerTest < ActionDispatch::IntegrationTest
  setup do
    SolakonReading.delete_all
    SolakonSnapshot.delete_all if defined?(SolakonSnapshot)
  end

  test "page renders single continuous Solakon overview" do
    get "/solakon"

    assert_response :success
    assert_select "h1", text: "PV", count: 1
    assert_select "[data-controller='solakon']", 1
    assert_select ".section-label", text: "Energiefluss"
    assert_select ".section-label", text: "Steuerung"
    assert_select ".section-label", text: "Panels"
    assert_select ".section-label", text: "Speicher"
    assert_select ".section-label", text: "Solakon-Verlauf"
    assert_select ".section-label", text: "Status"
    assert_select "[role='tablist']", count: 0
    assert_no_match(/SOH|EPS|46613|39067|Modbus/, response.body)
    assert_match(/Außensteckdose/, response.body)
    assert_match(/Auto-Regelung/, response.body)
    assert_match(/Batteriegesundheit/, response.body)
  end

  test "page reuses four-node energy flow with Solakon targets" do
    get "/solakon"

    assert_response :success
    assert_select "svg[viewBox='0 0 400 320']", 1
    assert_select "[data-solakon-target='efPvW']", 1
    assert_select "[data-solakon-target='efGridW']", 1
    assert_select "[data-solakon-target='efConsumerW']", 1
    assert_select "[data-solakon-target='efBatterySoc']", 1
    assert_select "[data-solakon-target='efBatteryW']", 1
    assert_select "[data-solakon-target='efDotsSolarHome']", 1
    assert_select "image[href*='solakon_battery_normal']", minimum: 1
  end

  test "history endpoint returns selected range payload" do
    SolakonSnapshot.create!(taken_at: 10.minutes.ago, pv1_power_w: 100, pv2_power_w: 50, battery_power_w: 20, grid_power_w: 30)

    get "/solakon/history.json", params: { range: "24h" }

    assert_response :success
    data = response.parsed_body
    assert_equal "24h", data["range"]
    assert_equal [ "PV", "Akku", "Netz", "0 W" ], data.dig("chart", "datasets").map { |dataset| dataset.fetch("label") }
  end
end
