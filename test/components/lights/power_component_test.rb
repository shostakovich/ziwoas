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

  test "An and Aus are one segmented toggle that posts the chosen state" do
    light = Light.new(key: "K1", name: "Stehlampe", sku: "H607C")
    rendered = render_inline(Lights::PowerComponent.new(snapshot: snapshot(light: light)))

    form = rendered.css("form[action='/lights/K1/command']").sole
    assert_equal "turn", form.css("input[type=hidden][name=command]").sole["value"]
    group = form.css(".btn-group[role=group][aria-label=Lampe]").sole
    assert_equal [ %w[An true], %w[Aus false] ],
                 group.element_children.map { |b| [ b.text, b["value"] ] }
    assert group.element_children.all? { |b| b.name == "button" && b["type"] == "submit" && b["name"] == "on" }
  end

  test "shows the zones row only for zone lamps" do
    zone_light = Light.new(key: "K2", name: "Uplighter", sku: "H60B0",
                           zones: %w[bottomLightToggle sideLightToggle])
    rendered = render_inline(Lights::PowerComponent.new(snapshot: snapshot(light: zone_light)))
    assert rendered.css("[role=group][aria-label=Zonen][hidden]").any?, "zones hide while the lamp is off"
    assert rendered.css("form#zone_bottomLightToggle").any?

    lit = render_inline(Lights::PowerComponent.new(snapshot: snapshot(light: zone_light,
                                                                      state: LightState.new(light_key: "K2", on: true))))
    zones = lit.css("[role=group][aria-label=Zonen]:not([hidden])").sole
    assert_equal "Zonen", zones.css("p").sole.text
    assert_equal %w[zone_bottomLightToggle zone_sideLightToggle],
                 zones.css(".row.row-cols-2 > form.col").map { |f| f["id"] }, "one equal column per zone"

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
