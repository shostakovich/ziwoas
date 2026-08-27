require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  cover "WeatherRecord.dashboard_icon"
  test "energy flow renders four nodes and six live flow targets" do
    get root_path

    assert_response :success
    assert_select "svg[viewBox='0 0 400 320']", 1

    assert_select "text", text: "PV-Anlage"
    assert_select "text", text: "Stromnetz"
    assert_select "text", text: "Verbraucher"
    assert_select "text", text: "Batterie"

    assert_select "image[x='184'][y='55'][width='32'][height='32']", 1
    assert_select "image[href*='icon_netz']"
    assert_select "image[href*='icon_haus']"
    assert_select "image[href*='solakon_battery_normal']"
    assert_select "image[data-ef='efBatteryImage'][data-battery-state-normal*='solakon_battery_normal']", 1
    assert_select "image[data-ef='efBatteryImage'][data-battery-state-charging*='solakon_battery_charging']", 1
    assert_select "image[data-ef='efBatteryImage'][data-battery-state-low*='solakon_battery_low']", 1
    assert_select "image[data-ef='efBatteryImage'][data-battery-state-fault*='solakon_battery_fault']", 1

    assert_select "[data-ef='efPvW']"
    assert_select "[data-ef='efGridW']"
    assert_select "[data-ef='efConsumerW']"
    assert_select "[data-ef='efBatterySoc']"
    assert_select "[data-ef='efBatteryW']"

    # The six static flow lines render as <path> elements (one per channel,
    # identified by stroke colour). Only the animated efDots overlays below are
    # driven from Stimulus, so the lines carry no data-target.
    assert_select "path[stroke='#f59f00']" # solar -> home
    assert_select "path[stroke='#8b5cf6']" # solar -> grid
    assert_select "path[stroke='#ec4899']" # solar -> battery
    assert_select "path[stroke='#3b82f6']" # grid -> home
    assert_select "path[stroke='#94a3b8']" # grid -> battery
    assert_select "path[stroke='#14b8a6']" # battery -> home

    assert_select "[data-ef='efDotsSolarHome']"
    assert_select "[data-ef='efDotsSolarGrid']"
    assert_select "[data-ef='efDotsSolarBattery']"
    assert_select "[data-ef='efDotsGridHome']"
    assert_select "[data-ef='efDotsGridBattery']"
    assert_select "[data-ef='efDotsBatteryHome']"
  end

  test "dashboard battery hero icon uses full sun height" do
    css = Rails.root.join("app/assets/stylesheets/application.css").read

    assert_match(/\.hero-icon-battery \{ height: 80px; \}/, css)
    assert_match(/@media \(max-width: 480px\).*\.hero-icon-battery \{ height: 48px; \}/m, css)
    assert_match(/@media \(max-width: 380px\).*\.hero-icon-battery \{ height: 42px; \}/m, css)
  end

  test "dashboard battery hero hides itself without a fresh reading and keeps the SVG asset map" do
    SolakonReading.delete_all

    get "/"
    assert_response :ok

    # The hero battery is server-rendered now; without a fresh reading its
    # half is hidden. The SVG keeps the client-side asset map for the flow.
    assert_select "#dashboard_hero .hero-half[hidden] img.hero-icon-battery", 1
    assert_select "image[data-ef='efBatteryImage'][data-battery-state-charging*='solakon_battery_charging']", 1
  end

  test "energy flow node contents are vertically centered in circles" do
    get "/"
    assert_response :ok

    assert_select "text[data-ef='efPvW'][x='200'][y='102'][text-anchor='middle']", 1

    assert_select "image[x='42'][y='145'][width='32'][height='32']", 1
    assert_select "text[data-ef='efGridW'][x='58'][y='192'][text-anchor='middle']", 1

    assert_select "image[x='326'][y='145'][width='32'][height='32']", 1
    assert_select "text[data-ef='efConsumerW'][x='342'][y='192'][text-anchor='middle']", 1
  end

  test "uses current weather icon in hero and pv energy flow node" do
    WeatherRecord.delete_all
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405, timestamp: Time.zone.parse("2026-05-04 12:00"), daytime: "night", icon: "cloudy")

    get "/"
    assert_response :ok

    assert_select "img.hero-icon[src*='weather_cloudy_night']", 1
    assert_select "img.hero-icon[alt='cloudy']", 1
    assert_select "image[href*='weather_cloudy_night'][x='184'][y='55'][width='32'][height='32']", 1
  end

  test "falls back to sun icon without current weather" do
    WeatherRecord.delete_all

    get "/"
    assert_response :ok

    assert_select "img.hero-icon[src*='icon_sonne']", 1
    assert_select "img.hero-icon[alt='Sonne']", 1
    assert_select "image[href*='icon_sonne'][x='184'][y='55'][width='32'][height='32']", 1
  end

  test "a blank icon on the current weather record falls back to the Sonne alt text" do
    WeatherRecord.delete_all
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405, timestamp: Time.zone.parse("2026-05-04 12:00"), daytime: "day", icon: "")

    get "/"
    assert_response :ok

    assert_select "img.hero-icon[alt='Sonne']", 1
  end

  test "dashboard renders Autarkie and Eigenverbrauch tiles" do
    get "/"
    assert_response :ok
    labels = css_select(".tiles .tile .tile-label").map { |n| n.text.squish }
    assert_includes labels, "Autarkie heute"
    assert_includes labels, "Eigenverbrauch"
    assert_select "#tile_autarky .tile-value", 1
    assert_select "#tile_self_consumption .tile-value", 1
  end
end
