# test/components/lights/white_panel_component_test.rb
require "test_helper"

class Lights::WhitePanelComponentTest < ViewComponent::TestCase
  cover "Lights::WhitePanelComponent*"

  def panel(light:, state: nil)
    Lights::WhitePanelComponent.new(snapshot: LightSnapshot.new(light: light, state: state))
  end

  def preset_param(rendered, label)
    rendered.css("button[data-light-detail-temp-param]").find { |b| b.text.strip == label }["data-light-detail-temp-param"]
  end

  test "renders the white panel with the lamp's slider range" do
    light = Light.new(key: "K1", name: "Floor", color_temp_min_k: 2200, color_temp_max_k: 6500, zones: [])
    rendered = render_inline(panel(light: light))

    slider = rendered.css("input.ld-white").first
    assert_equal "2200", slider["min"]
    assert_equal "6500", slider["max"]
    assert rendered.css("div[role=tabpanel][data-tab='white']:not([hidden])").any?
  end

  test "presets span min..5400 with the midpoint in between (2200 lamp)" do
    light = Light.new(key: "K1", name: "Floor", color_temp_min_k: 2200, color_temp_max_k: 6500, zones: [])
    rendered = render_inline(panel(light: light))
    assert_equal "2200", preset_param(rendered, "Gemütlich")
    assert_equal "3800", preset_param(rendered, "Neutral")
    assert_equal "5400", preset_param(rendered, "Arbeiten")
  end

  test "presets adapt to a 2700 lamp" do
    light = Light.new(key: "K2", name: "Ceiling", color_temp_min_k: 2700, color_temp_max_k: 6500, zones: [])
    rendered = render_inline(panel(light: light))
    assert_equal "2700", preset_param(rendered, "Gemütlich")
    assert_equal "4100", preset_param(rendered, "Neutral")
    assert_equal "5400", preset_param(rendered, "Arbeiten")
  end

  test "presets stay within a lamp whose range tops out below PRESET_MAX_K" do
    light = Light.new(key: "K4", name: "Warm only", color_temp_min_k: 2200, color_temp_max_k: 4000, zones: [])
    rendered = render_inline(panel(light: light))
    assert_equal "2200", preset_param(rendered, "Gemütlich")
    assert_equal "3100", preset_param(rendered, "Neutral")
    assert_equal "4000", preset_param(rendered, "Arbeiten")
    # no preset may exceed the slider's own max
    rendered.css("button[data-light-detail-temp-param]").each do |b|
      assert_operator b["data-light-detail-temp-param"].to_i, :<=, 4000
    end
  end

  test "the preset matching the current colour temperature is marked active" do
    light = Light.new(key: "K3", name: "Ceiling", color_temp_min_k: 2700, color_temp_max_k: 6500, zones: [])
    state = LightState.new(light_key: "K3", color_temp_k: 5400)
    rendered = render_inline(panel(light: light, state: state))

    active = rendered.css("button.active[data-light-detail-temp-param]")
    assert_equal 1, active.length
    assert_equal "Arbeiten", active.first.text.strip
    assert_equal "true", active.first["aria-pressed"]
  end

  test "the readout and the range ends speak German numbers" do
    light = Light.new(key: "K5", name: "Floor", color_temp_min_k: 2200, color_temp_max_k: 6500, zones: [])
    rendered = render_inline(panel(light: light, state: LightState.new(light_key: "K5", color_temp_k: 2700)))

    readout = rendered.css("output[for=light_temp][data-light-detail-target=tempValue]").sole
    assert_equal "2.700 K", readout.text
    assert_equal [ "2.200 K · warm", "6.500 K · kalt" ], rendered.css(".justify-content-between span").map(&:text)
  end

  test "without a colour temperature the slider and readout start at the warm end" do
    light = Light.new(key: "K6", name: "Floor", color_temp_min_k: 2700, color_temp_max_k: 6500, zones: [])
    rendered = render_inline(panel(light: light))
    assert_equal "2700", rendered.css("input#light_temp").sole["value"]
    assert_equal "2.700 K", rendered.css("output[for=light_temp]").sole.text
  end

  test "a notch under the track marks each preset at its share of the range" do
    light = Light.new(key: "K7", name: "Floor", color_temp_min_k: 2200, color_temp_max_k: 6500, zones: [])
    rendered = render_inline(panel(light: light))

    ticks = rendered.css(".ld-ticks[aria-hidden=true] .ld-tick").map { |t| t["style"] }
    assert_equal [ "--at: 0.0", "--at: 0.3721", "--at: 0.7442" ], ticks
  end

  test "a lamp with a single colour temperature puts every notch at the start" do
    light = Light.new(key: "K8", name: "Fixed", color_temp_min_k: 2700, color_temp_max_k: 2700, zones: [])
    rendered = render_inline(panel(light: light))
    assert_equal [ "--at: 0" ] * 3, rendered.css(".ld-tick").map { |t| t["style"] }
  end
end
