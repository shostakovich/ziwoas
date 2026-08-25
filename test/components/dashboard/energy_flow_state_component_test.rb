require "test_helper"
require_relative "live_test_support"

class Dashboard::EnergyFlowStateComponentTest < ViewComponent::TestCase
  include Dashboard::LiveTestSupport

  cover "Dashboard::EnergyFlowStateComponent*"

  test "carries the flow as JSON and doubles as the freshness beat" do
    l = live(flow: { solakon_online: true, solar_w: 420.0, home_w: 130.0,
                     flows: EnergyFlow::Flows.split(home_w: 130.0, solar_w: 420.0,
                                                    battery_w: 0.0, grid_w: -290.0) })

    rendered = render_inline(Dashboard::EnergyFlowStateComponent.new(live: l))
    carrier = rendered.css("#energy_flow_state").first

    assert carrier["hidden"]
    assert_equal "state", carrier["data-energy-flow-target"]
    assert_equal "beat", carrier["data-live-freshness-target"]

    state = JSON.parse(carrier["data-state"])
    assert_equal true, state["solakon_online"]
    assert_in_delta 420.0, state["solar_w"]
    assert_in_delta 130.0, state["flows"]["solar_to_home_w"]
  end

  test "a stale inverter arrives as an offline flow, not as old watts" do
    rendered = render_inline(Dashboard::EnergyFlowStateComponent.new(live: live))
    state = JSON.parse(rendered.css("#energy_flow_state").first["data-state"])

    assert_equal false, state["solakon_online"]
    assert_nil state["solar_w"]
  end
end
