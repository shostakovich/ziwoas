require "test_helper"

class Dashboard::PlugDeltasComponentTest < ViewComponent::TestCase
  cover "Dashboard::PlugDeltasComponent*"
  test "carries per-plug deltas as a JSON payload for the 24h chart" do
    delta = LiveState::Update.new(
      id: "fridge", name: "Kühlschrank", role: :consumer,
      apower_w: 80.0, last_seen_ts: 1_700_000_000,
      bucket_ts: 1_699_999_980, avg_power_w: 78.5, output: true
    )

    rendered = render_inline(Dashboard::PlugDeltasComponent.new(deltas: [ delta ]))
    carrier = rendered.css("#plug_deltas").first

    assert carrier["hidden"]
    assert_equal "deltas", carrier["data-today-chart-target"]

    payload = JSON.parse(carrier["data-payload"])
    assert_equal 1, payload.length
    assert_equal "fridge", payload.first["id"]
    assert_equal 1_699_999_980, payload.first["bucket_ts"]
    assert_in_delta 78.5, payload.first["avg_power_w"]
  end

  test "renders an empty payload for the initial page" do
    rendered = render_inline(Dashboard::PlugDeltasComponent.new(deltas: []))

    assert_equal "[]", rendered.css("#plug_deltas").first["data-payload"]
  end
end
