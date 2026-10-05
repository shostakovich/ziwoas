# test/components/lights/power_component_test.rb
require "test_helper"

class Lights::PowerComponentTest < ViewComponent::TestCase
  def snapshot(light:, state: nil)
    LightSnapshot.new(light: light, state: state)
  end

  test "renders the hero with on/off pills and the power id" do
    light = Light.new(key: "K1", name: "Stehlampe", sku: "H607C")
    state = LightState.new(light_key: "K1", on: true)
    rendered = render_inline(Lights::PowerComponent.new(snapshot: snapshot(light: light, state: state)))

    assert rendered.css("div#light_power").any?
    assert rendered.css(".sw-lamp-hero:not(.off) img.sw-knob-plush[src*='lamp_floorlamp_on']").any?
    hero = rendered.css(".sw-lamp-hero").sole
    assert_equal "span", hero.name, "the hero shows the knob; only the buttons switch"
    assert_equal %w[btn btn-light btn-icon sw-knob sw-lamp-knob], hero["class"].split & %w[btn btn-light btn-icon sw-knob sw-lamp-knob]
    assert_equal "true", hero["aria-hidden"]
    on_button, off_button = %w[An Aus].map { |label| rendered.css("button.btn-outline-primary").find { |b| b.text == label } }
    assert_equal [ "true", "false" ], [ on_button["aria-pressed"], off_button["aria-pressed"] ]
    assert_includes on_button["class"].split, "active"
    refute_includes off_button["class"].split, "active"
  end

  test "shows the zones row only for zone lamps" do
    zone_light = Light.new(key: "K2", name: "Uplighter", sku: "H60B0",
                           zones: %w[bottomLightToggle sideLightToggle])
    rendered = render_inline(Lights::PowerComponent.new(snapshot: snapshot(light: zone_light)))
    assert rendered.css("[role=group][aria-label=Zonen][hidden]").any?, "zones hide while the lamp is off"
    assert rendered.css("form#zone_bottomLightToggle").any?

    simple = Light.new(key: "K3", name: "Lampe", sku: "H607C", zones: [])
    rendered2 = render_inline(Lights::PowerComponent.new(snapshot: snapshot(light: simple)))
    assert rendered2.css("[aria-label=Zonen]").none?
  end

  test "an off lamp shows its off plush and presses Aus" do
    light = Light.new(key: "K1", name: "Stehlampe", sku: "H607C")
    rendered = render_inline(Lights::PowerComponent.new(snapshot: snapshot(light: light)))

    assert rendered.css(".sw-lamp-hero.off img.sw-knob-plush[src*='lamp_floorlamp_off']").any?
    assert_equal "true", rendered.css("button.btn-outline-primary.active").sole.tap { |b| assert_equal "Aus", b.text }["aria-pressed"]
  end
end
