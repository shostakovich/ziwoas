require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  cover "WeatherRecord.dashboard_icon"
  test "energy flow renders four nodes and six live flow targets" do
    get root_path

    assert_response :success
    assert_select ".energy-flow > svg[viewBox='0 0 400 320']", 1
    assert_select ".energy-flow svg g[fill='none'] > circle", 4
    assert_select ".energy-flow svg g[clip-path='url(#ef-clip)'] > path", 6
    assert_select ".energy-flow svg g[clip-path='url(#ef-clip)'] > g[data-ef^='efDots']", 6

    assert_select "text", text: "PV-Anlage"
    assert_select "text", text: "Verbraucher"

    assert_select ".ef-ring[data-ring='grid'] > img.ef-icon[src*='icon_netz'][alt='']", 1
    assert_select ".ef-ring[data-ring='consumer'] > img.ef-icon[src*='icon_haus'][alt='']", 1
    battery = ".ef-ring[data-ring='battery'] > img.ef-icon[data-ef='efBatteryImage'][alt='']"
    assert_select "#{battery}[src*='solakon_battery_normal']", 1
    assert_select "#{battery}[data-battery-state-normal*='solakon_battery_normal']", 1
    assert_select "#{battery}[data-battery-state-charging*='solakon_battery_charging']", 1
    assert_select "#{battery}[data-battery-state-low*='solakon_battery_low']", 1
    assert_select "#{battery}[data-battery-state-fault*='solakon_battery_fault']", 1

    assert_select "[data-ef='efPvW']"
    assert_select "[data-ef='efGridW']"
    assert_select "[data-ef='efConsumerW']"
    assert_select "[data-ef='efBatterySoc']"
    assert_select "[data-ef='efBatteryW']"

    {
      "SolarHome" => "--viz-solar", "SolarGrid" => "--viz-solar", "SolarBattery" => "--viz-solar",
      "GridHome" => "--viz-grid", "GridBattery" => "--viz-grid", "BatteryHome" => "--viz-battery"
    }.each do |channel, token|
      assert_select "path.ef-link[data-ef='efLine#{channel}'][style='--ef-tone: var(#{token})']", 1
      assert_select "g[data-ef='efDots#{channel}'][style='fill: var(#{token})']", 1
    end
    assert_select "path.ef-link[data-flowing]", 0

    assert_select "text[data-ef='efGridName']", text: "Stromnetz"
    assert_select "text > tspan[data-ef='efBatteryName']", text: "Batterie"
    assert_select "p", text: "Verbraucher-Ring: Herkunft des Stroms"
  end

  test "dashboard battery hero icon shares the sun icon's sizing" do
    get "/"

    assert_select "#dashboard_hero img.hero-icon", 2
    assert_select "#dashboard_hero img.hero-icon[alt='Batterie']", 1
  end

  test "dashboard battery hero hides itself without a fresh reading and keeps the SVG asset map" do
    Solakon::Reading.delete_all

    get "/"
    assert_response :ok

    assert_select "#dashboard_hero .col[hidden] img.hero-icon[alt='Batterie']", 1
    assert_select "img[data-ef='efBatteryImage'][data-battery-state-charging*='solakon_battery_charging']", 1
  end

  test "each ring's icon and value sit in a box placed over that ring" do
    get "/"
    assert_response :ok

    rings = css_select(".energy-flow svg circle[data-ring]")
    boxes = css_select(".energy-flow > .ef-ring")
    assert_equal %w[pv grid consumer battery], rings.map { |ring| ring["data-ring"] }
    assert_equal %w[pv grid consumer battery], boxes.map { |box| box["data-ring"] }

    width, height = css_select(".energy-flow > svg").sole["viewBox"].split.last(2).map(&:to_f)
    percent = ->(units, extent) { format("%g%%", units * 100 / extent) }
    rings.zip(boxes).each do |ring, box|
      cx, cy, r = %w[cx cy r].map { |name| ring[name].to_f }
      assert_equal "left: #{percent[cx, width]}; top: #{percent[cy, height]}; " \
                   "width: #{percent[2 * r, width]}; height: #{percent[2 * r, height]}", box["style"]
    end

    { "pv" => "efPvW", "grid" => "efGridW", "consumer" => "efConsumerW", "battery" => "efBatteryW" }.each do |ring, value|
      assert_select ".ef-ring[data-ring='#{ring}'] > img.ef-icon:first-child + span.ef-value[data-ef='#{value}']", 1
    end
  end

  test "energy flow values share the text ink; the rings carry the hue" do
    get "/"
    assert_response :ok

    assert_select "span.ef-value.tabular-nums.fw-semibold", 4
    assert_select "span.ef-value[style]", 0
    %w[--viz-solar --viz-grid --ef-groove --viz-battery].each do |token|
      assert_select ".energy-flow svg circle[data-ring][style='stroke: var(#{token})']", 1
    end
  end

  test "uses current weather icon in hero and pv energy flow node" do
    WeatherRecord.delete_all
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405, timestamp: Time.zone.parse("2026-05-04 12:00"), daytime: "night", icon: "cloudy")

    get "/"
    assert_response :ok

    assert_select "img.hero-icon[src*='weather_cloudy_night']", 1
    assert_select "img.hero-icon[alt='cloudy']", 1
    assert_select ".ef-ring[data-ring='pv'] > img.ef-icon[src*='weather_cloudy_night'][alt='cloudy']", 1
  end

  test "falls back to sun icon without current weather" do
    WeatherRecord.delete_all

    get "/"
    assert_response :ok

    assert_select "img.hero-icon[src*='icon_sonne']", 1
    assert_select "img.hero-icon[alt='Sonne']", 1
    assert_select ".ef-ring[data-ring='pv'] > img.ef-icon[src*='icon_sonne'][alt='Sonne']", 1
  end

  test "a blank icon on the current weather record falls back to the Sonne alt text" do
    WeatherRecord.delete_all
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405, timestamp: Time.zone.parse("2026-05-04 12:00"), daytime: "day", icon: "")

    get "/"
    assert_response :ok

    assert_select "img.hero-icon[alt='Sonne']", 1
  end

  test "hero, tiles, plug bar and energy flow dim together when the live picture goes stale" do
    get "/"

    assert_select "[data-controller~='live-freshness'] .live-dim", 4
    assert_select "#dashboard_hero.live-dim", 1
    assert_select "#dashboard_plug_bar.live-dim", 1
    assert_select ".energy-flow-card.live-dim", 1
    assert_select ".live-dim > #tile_consumption_now", 1
  end

  test "the energy flow takes its colours from theme tokens" do
    get "/"

    svg = css_select(".energy-flow-card svg").sole.to_html
    assert_no_match(/#\h{3,8}\b|"white"/, svg)
    assert_select ".energy-flow-card [data-ef='efDotsSolarHome'][style*='var(--viz-solar)']", 1
  end

  test "dashboard renders Autarkie and Eigenverbrauch tiles" do
    get "/"
    assert_response :ok
    labels = css_select("[id^='tile_'] .stat-label").map { |n| n.text.squish }
    assert_includes labels, "Autarkie heute"
    assert_includes labels, "Eigen\u00ADverbrauchs\u00ADquote"
    assert_select "#tile_autarky .stat-value", 1
    assert_select "#tile_self_consumption .stat-value", 1
  end
end
