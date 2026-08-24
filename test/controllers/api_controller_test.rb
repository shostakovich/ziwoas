require "test_helper"

class ApiControllerTest < ActionDispatch::IntegrationTest
  setup do
    Plugs::Sample.delete_all
    Plugs::DailyTotal.delete_all
    SolakonReading.delete_all
  end

  # --- /api/live ---

  test "GET /api/live renders plug lines, an energy flow and a now_ts, with the role as a string" do
    Plugs::Sample.create!(plug_id: "bkw", ts: Time.now.to_i - 2, apower_w: 342.5, aenergy_wh: 1000.0)

    get "/api/live", as: :json
    assert_response :ok

    data = response.parsed_body
    assert_equal %w[plugs energy_flow now_ts offline_after_s stale_after_s].sort, data.keys.sort
    assert data["energy_flow"].key?("flows")

    bkw = data["plugs"].find { |p| p["id"] == "bkw" }
    assert_equal %w[id name role online apower_w last_seen_ts].sort, bkw.keys.sort
    assert_equal "producer", bkw["role"]
    assert_in_delta 342.5, bkw["apower_w"]
  end

  test "GET /api/live sends both Fristen along, so a reader can re-apply them" do
    get "/api/live", as: :json

    data = response.parsed_body
    assert_equal Plugs::Measurement::OFFLINE_AFTER_S, data["offline_after_s"]
    assert_equal SolakonReading::STALE_AFTER_S, data["stale_after_s"]
  end

  test "GET /api/live leaves the reading date empty without a fresh reading" do
    SolakonReading.delete_all

    get "/api/live", as: :json

    flow = response.parsed_body["energy_flow"]
    assert_equal false, flow["solakon_online"]
    assert_nil flow["reading_ts"]
  end

  # --- /api/today ---

  test "GET /api/today returns series per plug" do
    now = Time.now.to_i
    Plugs::Sample.create!(plug_id: "bkw", ts: now - 3600, apower_w: 200.0, aenergy_wh: 100.0)
    Plugs::Sample.create!(plug_id: "bkw", ts: now - 3540, apower_w: 300.0, aenergy_wh: 110.0)

    get "/api/today", as: :json
    assert_response :ok

    data = response.parsed_body
    assert data["series"].any? { |s| s["plug_id"] == "bkw" }
    bkw = data["series"].find { |s| s["plug_id"] == "bkw" }
    assert bkw["points"].length >= 1
    assert bkw["points"].first.key?("ts")
    assert bkw["points"].first.key?("avg_power_w")
  end

  test "GET /api/today reports producer power as a positive magnitude" do
    now = Time.now.to_i
    Plugs::Sample.create!(plug_id: "bkw",    ts: now - 3600, apower_w: -200.0, aenergy_wh: 100.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: now - 3600, apower_w:   80.0, aenergy_wh: 100.0)

    get "/api/today", as: :json
    assert_response :ok

    series = response.parsed_body["series"]
    assert_in_delta 200.0, series.find { |s| s["plug_id"] == "bkw" }["points"].first["avg_power_w"]
    assert_in_delta 80.0, series.find { |s| s["plug_id"] == "fridge" }["points"].first["avg_power_w"]
  end

  test "GET /api/today returns points in ascending ts order" do
    now = Time.now.to_i
    Plugs::Sample.create!(plug_id: "bkw", ts: now -  600, apower_w: 100.0, aenergy_wh: 100.0)
    Plugs::Sample.create!(plug_id: "bkw", ts: now - 3600, apower_w: 200.0, aenergy_wh:  90.0)

    get "/api/today", as: :json
    assert_response :ok

    timestamps = response.parsed_body["series"].find { |s| s["plug_id"] == "bkw" }["points"].map { |p| p["ts"] }
    assert_equal timestamps.sort, timestamps
  end

  # --- /api/today/summary ---

  test "GET /api/today/summary calculates energy and savings" do
    tz       = TZInfo::Timezone.get("Europe/Berlin")
    midnight = tz.local_to_utc(Time.parse("#{Date.today} 00:00:00")).to_i

    Plugs::Sample.create!(plug_id: "bkw",    ts: midnight + 60,   apower_w: 0, aenergy_wh: 0.0)
    Plugs::Sample.create!(plug_id: "bkw",    ts: midnight + 3600, apower_w: 0, aenergy_wh: 1000.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: midnight + 60,   apower_w: 0, aenergy_wh: 500.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: midnight + 3600, apower_w: 0, aenergy_wh: 600.0)

    get "/api/today/summary", as: :json
    assert_response :ok

    data = response.parsed_body
    assert_in_delta 1000.0, data["produced_wh_today"]
    assert_in_delta 100.0,  data["consumed_wh_today"]
    assert_in_delta 1000.0 * 0.2902 / 1000.0, data["savings_eur_today"], 0.001
  end

  test "GET /api/today/summary includes self-consumption fields" do
    tz       = TZInfo::Timezone.get("Europe/Berlin")
    midnight = tz.local_to_utc(Time.parse("#{Date.today} 00:00:00")).to_i

    (0..3600).step(60) do |dt|
      Plugs::Sample.create!(plug_id: "bkw",    ts: midnight + dt, apower_w: 200.0, aenergy_wh: 200.0 * dt / 3600.0)
      Plugs::Sample.create!(plug_id: "fridge", ts: midnight + dt, apower_w: 100.0, aenergy_wh: 100.0 * dt / 3600.0)
    end

    get "/api/today/summary", as: :json
    assert_response :ok

    data = response.parsed_body
    assert data.key?("self_consumed_wh_today")
    assert data.key?("autarky_ratio")
    assert data.key?("self_consumption_ratio")
    assert_in_delta 100.0, data["self_consumed_wh_today"], 2.0
    assert_in_delta 1.0,   data["autarky_ratio"],          0.05
    assert_in_delta 0.5,   data["self_consumption_ratio"], 0.05
  end

  # --- /api/history ---

  test "GET /api/history returns requested number of days" do
    today = Date.today
    7.times do |i|
      Plugs::DailyTotal.create!(plug_id: "bkw", date: (today - (i + 1)).to_s, energy_wh: 1000 + i * 100)
    end

    get "/api/history?days=5", as: :json
    assert_response :ok

    data = response.parsed_body
    bkw = data["series"].find { |s| s["plug_id"] == "bkw" }
    assert_equal 5, bkw["points"].length
    # sorted ascending
    assert bkw["points"].first["date"] < bkw["points"].last["date"]
  end

  # --- / ---

  test "GET / serves dashboard HTML" do
    get "/"
    assert_response :ok
    assert_select "h1", text: "Dashboard", count: 1
    assert_select ".chart-card .chart-frame", minimum: 3
  end
end
