require "test_helper"

class SolakonControllerTest < ActionDispatch::IntegrationTest
  cover "Solakon::Snapshot#panels"
  cover "SolakonController#index"
  cover "SolakonController#history"

  setup do
    Solakon::Reading.delete_all
    Solakon::Snapshot.delete_all if defined?(Solakon::Snapshot)
    Solakon::PvHour.delete_all
    WeatherRecord.delete_all
    # AggregatorJobTest runs without a transaction, so its buckets can reach this class.
    Plugs::Sample5min.delete_all
    DailyEnergySummary.delete_all
    Economics::CostItem.delete_all
    Economics::ElectricityPrice.delete_all
  end

  def pv_hour(date, hour, watts, panels: [ 100.0, 100.0, 100.0, 100.0 ])
    Solakon::PvHour.create!(
      started_at: Time.zone.local(date.year, date.month, date.day, hour),
      pv_power_w: watts, reading_count: 120,
      pv1_power_w: panels[0], pv2_power_w: panels[1], pv3_power_w: panels[2], pv4_power_w: panels[3]
    )
  end

  test "page renders single continuous Solakon overview" do
    get "/solakon"

    assert_response :success
    assert_select "h1", text: "PV", count: 1
    assert_select "[data-controller~='solakon']", 1
    assert_select ".card-title", text: "Energiefluss"
    assert_select ".card-title", text: "Status"
    assert_select ".card-title", text: "Solakon-Verlauf"
    assert_select ".section-label", text: "Steuerung"
    assert_select ".section-label", text: "Panels"
    assert_select ".section-label", text: "Speicher"
    assert_operator response.body.index("Status"), :<, response.body.index("Steuerung")
    assert_select "[role='tablist']", count: 0
    assert_no_match(/SOH|EPS|46613|39067|Modbus/, response.body)
    assert_match(/Außensteckdose/, response.body)
    assert_match(/Auto-Regelung/, response.body)
    assert_match(/Batteriegesundheit/, response.body)
    assert_select "turbo-frame#solakon_history canvas[data-solakon-history-target='canvas']", 1
    assert_select "turbo-frame#solakon_history script[data-solakon-history-target='payload']", 1
    assert_select "turbo-frame#solakon_history .solakon-balance", 1
    assert_select "turbo-frame#solakon_history a.preset-link.active", text: "Letzte 24 h", count: 1
    assert_select "input[data-solakon-target='epsToggle'][data-action='change->solakon#toggleEps']", 1
    assert_select "input[data-solakon-target='controlToggle'][data-action='change->solakon#toggleControl']", 1
  end

  test "page carries the Wirtschaftlichkeit card between the history and the sun calendar" do
    Economics::CostItem.create!(label: "Anlage", amount_eur: 1_000.00, spent_on: "2026-01-01")
    Economics::ElectricityPrice.create!(valid_from: "2026-01-01", eur_per_kwh: 0.30)
    DailyEnergySummary.create!(date: "2026-01-01", produced_wh: 5_000.0, consumed_wh: 3_000.0,
                               self_consumed_wh: 2_000.0)

    get "/solakon"

    assert_response :success
    assert_select ".card-title", text: /\AWirtschaftlichkeit/
    labels = css_select(".economics-tiles .tile-label").map { |node| node.text.squish }
    assert_equal [ "Anschaffungskosten", "Ersparnis", "Zurückverdient", "Voraussichtliche Amortisation" ], labels
    assert_match "1.000,00 €", response.body
    assert_match "0,60 €", response.body
    assert_select "a[href=?]", economics_path
    assert_operator response.body.index("Wirtschaftlichkeit"), :<, response.body.index("Sonnenkalender")
    assert_operator response.body.index("Solakon-Verlauf"), :<, response.body.index("Wirtschaftlichkeit")
  end

  test "page asks for cost items while none are recorded" do
    get "/solakon"

    assert_response :success
    assert_match "Kosten erfassen", response.body
    assert_select "[data-economics-covered-pct]", 0
  end

  test "page reuses four-node energy flow with Solakon targets" do
    get "/solakon"

    assert_response :success
    assert_select "svg[viewBox='0 0 400 320']", 1
    assert_select "[data-ef='efPvW']", 1
    assert_select "[data-ef='efGridW']", 1
    assert_select "[data-ef='efConsumerW']", 1
    assert_select "[data-ef='efBatterySoc']", 1
    assert_select "[data-ef='efBatteryW']", 1
    assert_select "[data-ef='efDotsSolarHome']", 1
    assert_select "image[href*='solakon_battery_normal']", minimum: 1
    assert_select "image[data-ef='efBatteryImage'][data-battery-state-normal*='solakon_battery_normal']", 1
    assert_select "image[data-ef='efBatteryImage'][data-battery-state-charging*='solakon_battery_charging']", 1
    assert_select "image[data-ef='efBatteryImage'][data-battery-state-low*='solakon_battery_low']", 1
    assert_select "image[data-ef='efBatteryImage'][data-battery-state-fault*='solakon_battery_fault']", 1
  end

  test "history frame renders the selected range with its switch active" do
    Solakon::Snapshot.create!(taken_at: 10.minutes.ago, pv1_power_w: 100, pv2_power_w: 50, battery_power_w: 20, active_power_w: 140, grid_power_w: 30)

    get "/solakon/history", params: { range: "7d" }, headers: { "Turbo-Frame" => "solakon_history" }

    assert_response :success
    assert_select "h1", 0
    assert_select "turbo-frame#solakon_history", 1
    assert_select "a.preset-link.active", text: "Letzte 7 Tage", count: 1
    assert_select "a.preset-link.active", 1
    assert_select "a.preset-link[href=?]", "/solakon/history?range=30d"
    assert_select "[data-controller='solakon-history'][data-solakon-history-url-value=?]", "/solakon/history?range=7d"
    assert_select ".solakon-balance-row", minimum: 6
    chart = JSON.parse(css_select("script[data-solakon-history-target='payload']").first.text)
    assert_equal [ "PV", "Akku", "Außensteckdose", "0 W" ], chart.fetch("datasets").map { |dataset| dataset.fetch("label") }
  end

  test "history frame falls back to 24 h for an unknown range and names the empty state" do
    get "/solakon/history", params: { range: "1y" }, headers: { "Turbo-Frame" => "solakon_history" }

    assert_response :success
    assert_select "a.preset-link.active", text: "Letzte 24 h", count: 1
    assert_select ".muted-text", text: "Keine Solakon-Historie"
    assert_select ".solakon-balance-row", 0
  end

  test "page renders controls, panel, storage, balance, and status labels without protocol language" do
    Solakon::Snapshot.create!(
      taken_at: Time.current,
      pv1_power_w: 210.6,
      pv1_voltage_v: 41.7,
      pv1_current_a: 5.12,
      pv2_power_w: 198,
      pv2_voltage_v: 40.5,
      pv2_current_a: 4.88,
      pv3_power_w: 176,
      pv3_voltage_v: 39.8,
      pv3_current_a: 4.42,
      pv4_power_w: 164,
      pv4_voltage_v: 39.2,
      pv4_current_a: 4.18,
      battery_health_pct: 97,
      battery_voltage_v: 51.3,
      battery_current_a: 4.2,
      battery_temperature_c: 24.8,
      remaining_energy_wh: 123.4,
      full_charge_capacity_ah: 51.2,
      design_energy_wh: 1920.0,
      inverter_temperature_c: 34.1,
      eps_enabled: true,
      eps_voltage_v: 230.1,
      eps_power_w: 125
    )

    get "/solakon"

    assert_response :success
    assert_select ".solakon-control-card", 2
    assert_select ".solakon-panel-card", 4
    assert_select ".solakon-panel-card .tile-label", text: "Panel 3"
    assert_select ".solakon-panel-card .tile-label", text: "Panel 4"
    assert_select ".solakon-panel-card .muted-text", text: "41,7 V · 5,12 A"
    assert_select ".muted-text", text: /Speichertemperatur.*24,8 °C/
    assert_select ".muted-text", text: /Wechselrichtertemperatur.*34,1 °C/

    assert_select ".solakon-storage-grid .tile-label", text: "Ladestand"
    assert_select ".solakon-storage-grid .tile-label", text: "Batteriegesundheit"
    assert_select ".solakon-storage-grid .tile-label", text: "Aktuelle Batterieleistung"
    assert_select ".solakon-storage-grid .tile-label", text: "Batteriespannung"
    assert_select ".solakon-storage-grid .tile-label", text: "Batteriestrom"
    assert_select ".solakon-storage-grid .tile-label", text: "Speichertemperatur"
    assert_select ".solakon-storage-grid .tile-label", text: "Ladezyklen", count: 0
    assert_select ".solakon-balance-row", minimum: 6
    assert_no_match(/SOH|EPS|Modbus|Register|39067|46613|Fault\d|Alarm \d/, response.body)
  end

  test "a panel without yield keeps its card and shows zero watts" do
    Solakon::Snapshot.create!(
      taken_at: Time.current,
      pv1_power_w: 210, pv1_voltage_v: 41.0, pv1_current_a: 5.12,
      pv2_power_w: 198, pv2_voltage_v: 40.5, pv2_current_a: 4.88,
      pv3_power_w: 176, pv3_voltage_v: 39.8, pv3_current_a: 4.42,
      pv4_power_w: 0, pv4_voltage_v: 0, pv4_current_a: 0
    )

    get "/solakon"

    assert_response :success
    assert_select ".solakon-panel-card", 4
    assert_select ".solakon-panel-card", text: /Panel 4\s*0 W/
  end

  test "a snapshot predating panels three and four shows zero, not a blank dash" do
    Solakon::Snapshot.create!(
      taken_at: Time.current,
      pv1_power_w: 210, pv1_voltage_v: 41.0, pv1_current_a: 5.12,
      pv2_power_w: 198, pv2_voltage_v: 40.5, pv2_current_a: 4.88
    )

    get "/solakon"

    assert_response :success
    assert_select ".solakon-panel-card", 4
    assert_select ".solakon-panel-card", text: /Panel 3\s*0 W\s*0,0 V · 0,00 A/
    assert_select ".solakon-panel-card", text: /Panel 4\s*0 W\s*0,0 V · 0,00 A/
  end

  test "panel power rounds to the nearest watt instead of truncating" do
    Solakon::Snapshot.create!(
      taken_at: Time.current,
      pv1_power_w: 210.6, pv1_voltage_v: 41.0, pv1_current_a: 5.12,
      pv2_power_w: 198, pv2_voltage_v: 40.5, pv2_current_a: 4.88,
      pv3_power_w: 176, pv3_voltage_v: 39.8, pv3_current_a: 4.42,
      pv4_power_w: 164, pv4_voltage_v: 39.2, pv4_current_a: 4.18
    )

    get "/solakon"

    assert_response :success
    # 210.6 rounds to 211; a truncating cast would show 210.
    assert_select ".solakon-panel-card", text: /Panel 1\s*211 W/
  end

  test "status renders one relevant battery character with short description" do
    Solakon::Reading.create!(
      taken_at: Time.current,
      active_power_w: 260,
      pv_power_w: 310,
      battery_power_w: 80,
      battery_soc_pct: 84,
      battery_temperature_c: 24.8
    )

    get "/solakon"

    assert_response :success
    assert_select ".solakon-status-figure img[data-solakon-battery-state]", 1
    assert_select ".solakon-status-figure img[data-solakon-battery-state=charging][src*=solakon_battery_charging]", 1
    assert_select ".solakon-status-summary", text: /Akku lädt gerade/
    assert_select ".solakon-battery-states", count: 0
  end

  test "auto-regulation card reflects an enabled config with an active runtime state" do
    config = ConfigLoader.app_config.dup
    config.solakon = ConfigLoader::SolakonCfg.new(control_enabled: true)

    ConfigLoader.stub(:app_config, config) do
      get "/solakon"
    end

    assert_response :success
    assert_select ".tile-value[data-solakon-target='controlState']", text: "Aktiv"
    assert_select ".muted-text[data-solakon-target='controlHelp']", text: "folgt dem gemessenen Verbrauch"
    assert_select "input[data-solakon-target='controlToggle'][checked]", 1
    assert_select "input[data-solakon-target='controlToggle'][disabled]", 0
  end

  test "auto-regulation card stays off when the config disables control despite a config object being present" do
    config = ConfigLoader.app_config.dup
    config.solakon = ConfigLoader::SolakonCfg.new(control_enabled: false)

    ConfigLoader.stub(:app_config, config) do
      get "/solakon"
    end

    assert_response :success
    assert_select ".tile-value[data-solakon-target='controlState']", text: "Aus"
    assert_select ".muted-text[data-solakon-target='controlHelp']", text: "in Konfiguration deaktiviert"
    assert_select "input[data-solakon-target='controlToggle'][checked]", 0
    assert_select "input[data-solakon-target='controlToggle'][disabled]", 1
  end

  test "status shows the newest reading, not merely any reading" do
    Solakon::Reading.create!(taken_at: 1.hour.ago, active_power_w: 0, pv_power_w: 0, battery_power_w: 0, battery_soc_pct: 50)
    Solakon::Reading.create!(taken_at: Time.current, active_power_w: 0, pv_power_w: 0, battery_power_w: 0, battery_soc_pct: 84)

    get "/solakon"

    assert_response :success
    assert_select ".solakon-storage-grid .tile-value", text: "84 %"
  end

  test "history frame falls back to 24 h when the range parameter is missing entirely" do
    get "/solakon/history", headers: { "Turbo-Frame" => "solakon_history" }

    assert_response :success
    assert_select "a.preset-link.active", text: "Letzte 24 h", count: 1
    assert_select ".muted-text", text: "Keine Solakon-Historie"
  end

  test "page shows the shading section under the history" do
    3.times do |index|
      date = Date.new(2026, 7, 1) + index
      pv_hour(date, 12, 400.0)
      # Bright Sky stamps the end of the hour it sums up.
      WeatherRecord.create!(kind: "historic", daytime: "day", lat: 52.52, lon: 13.405,
                            timestamp: Time.zone.local(date.year, date.month, date.day, 13), solar: 0.5)
    end

    get "/solakon"

    assert_response :success
    assert_select ".card-title", text: "Ausbeute nach Sonnenstand"
    assert_select ".card-title", text: "Tagesgang je Monat"
    assert_select ".card-title", text: /\ADie vier Panels im Tagesverlauf seit /
    assert_select ".shading [data-chart='yield-map'] .fields rect", minimum: 1
    assert_select ".shading [data-chart='daily-profiles'] .multiple", 1
    assert_select ".shading [data-chart='panels'] polyline", 4
  end

  test "page keeps an empty state for the shading section while no PV hour exists" do
    get "/solakon"

    assert_response :success
    assert_select ".shading", 0
    assert_select ".empty-state h2", text: "Noch keine Ausbeute"
  end

  test "page shows the sun calendar of the year the newest hour falls into" do
    pv_hour(Date.new(2026, 4, 10), 12, 640.0)

    get "/solakon"

    assert_response :success
    assert_select ".section-label", text: "Sonnenkalender 2026"
    assert_select ".sun-calendar [data-strip]", 4
    assert_select ".sun-calendar [data-strip='pv'] .cells rect", minimum: 1
    assert_select ".sun-calendar [data-strip='pv'] polyline.sun", 3
  end

  test "sun calendar marks the switch from producer-plug energy once PV data begins" do
    pv_hour(Date.new(2026, 4, 10), 12, 640.0)
    Plugs::Sample5min.create!(
      plug_id: "bkw",
      bucket_ts: Time.zone.local(2026, 3, 1, 12).to_i,
      avg_power_w: 120.0,
      energy_delta_wh: 10.0,
      sample_count: 12
    )

    get "/solakon"

    assert_response :success
    assert_select ".sun-calendar .legend-item", text: "Wechsel der Quelle", count: 1
    assert_select ".sun-calendar .note", 1
  end

  test "sun calendar keeps its own empty state while no PV hour exists" do
    get "/solakon"

    assert_response :success
    assert_select ".sun-calendar", 0
    assert_select ".empty-state h2", text: "Noch kein Sonnenkalender"
  end
end
