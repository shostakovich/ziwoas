require "test_helper"

class Lights::ColorPanelComponentTest < ViewComponent::TestCase
  cover "Lights::ColorPanelComponent#selected?"
  cover "Lights::ColorPanelComponent#custom?"

  def panel(light:, state: nil)
    Lights::ColorPanelComponent.new(snapshot: LightSnapshot.new(light: light, state: state))
  end

  test "renders the swatch palette and the colour panel tab" do
    light = Light.new(key: "K1", name: "Lampe", zones: [])
    rendered = render_inline(panel(light: light))

    assert rendered.css("div[role=tabpanel][data-tab='color'][hidden]").any?
    swatches = rendered.css("input.btn-check[type=radio][data-light-detail-color-param]")
    assert_equal 8, swatches.length
    swatches.each { |s| assert rendered.css("label[for='#{s['id']}']").any? }
    assert swatches.none? { |s| s["checked"] }
    assert_includes rendered.to_html, "Farbe"
  end

  test "zone lamps get the Welle + Seite label" do
    zone_light = Light.new(key: "K2", name: "Uplighter",
                           zones: %w[bottomLightToggle sideLightToggle])
    rendered = render_inline(panel(light: zone_light))
    assert_includes rendered.to_html, "Farbe · Welle + Seite"
  end

  test "the colour-wheel input defaults to the current hex" do
    light = Light.new(key: "K3", name: "Lampe", zones: [])
    state = LightState.new(light_key: "K3", color_r: 255, color_g: 107, color_b: 61)
    rendered = render_inline(panel(light: light, state: state))
    assert_equal "#ff6b3d", rendered.css("input[type='color']").first["value"]
  end

  test "the swatch matching the lamp's colour is checked, none in white mode" do
    light = Light.new(key: "K4", name: "Lampe", zones: [])
    colour = LightState.new(light_key: "K4", color_r: 0xff, color_g: 0x7a, color_b: 0x3d)
    checked = render_inline(panel(light: light, state: colour)).css("input.btn-check[checked]")
    assert_equal [ "#ff7a3d" ], checked.map { |s| s["data-light-detail-color-param"] }

    white = LightState.new(light_key: "K4", color_r: 0xff, color_g: 0x7a, color_b: 0x3d, color_temp_k: 2700)
    assert render_inline(panel(light: light, state: white)).css("input.btn-check[checked]").none?
  end

  test "the swatches sit in their own grid" do
    light = Light.new(key: "K5", name: "Lampe", zones: [])
    rendered = render_inline(panel(light: light))
    assert_equal 9, rendered.css(".ld-swatches[role=radiogroup] > label.ld-swatch").length
  end

  test "a colour no swatch has is shown and marked on the wheel" do
    light = Light.new(key: "K6", name: "Lampe", zones: [])
    custom = LightState.new(light_key: "K6", color_r: 180, color_g: 60, color_b: 140)
    rendered = render_inline(panel(light: light, state: custom))

    wheel = rendered.css("label.ld-swatch-wheel[data-light-detail-target=wheel]").sole
    assert_includes wheel["class"].split, "ld-swatch-custom"
    assert_equal "--ld-custom: #b43c8c", wheel["style"]
    assert rendered.css("input.btn-check[checked]").none?
  end

  test "the wheel stays unmarked for a swatch colour, in white mode and without a colour" do
    light = Light.new(key: "K7", name: "Lampe", zones: [])
    preset = LightState.new(light_key: "K7", color_r: 0x4d, color_g: 0x7c, color_b: 0xff)
    white = LightState.new(light_key: "K7", color_r: 180, color_g: 60, color_b: 140, color_temp_k: 4000)

    [ preset, white, nil ].each do |state|
      wheel = render_inline(panel(light: light, state: state)).css("label.ld-swatch-wheel").sole
      refute_includes wheel["class"].split, "ld-swatch-custom"
      assert_nil wheel["style"]
    end
  end
end
