# test/components/lights/light_card_component_test.rb
require "test_helper"

class Lights::LightCardComponentTest < ViewComponent::TestCase
  cover "Lights::LightCardComponent*"

  def card(attrs)
    light = Light.new(key: "K1", name: "Stehlampe", sku: "H607C")
    state = attrs.nil? ? nil : LightState.new(attrs.merge(light_key: "K1"))
    Lights::LightCardComponent.new(snapshot: LightSnapshot.new(light: light, state: state))
  end

  test "off card summarises as Aus and has no chip" do
    rendered = render_inline(card(on: false))
    assert rendered.css("div#light_card_K1.card.opacity-75").none?, "the card itself stays opaque"
    assert rendered.css("a.text-reset[aria-label='Stehlampe Details']").any?, "the ring says off, the name stays as it is"
    assert rendered.css("button.sw-knob.sw-lamp-knob.off img.sw-knob-plush[src*='lamp_floorlamp_off']").any?
    assert_includes rendered.to_html, "Aus"
    assert rendered.css("span.badge").none?
  end

  test "white-on card names the light in its line and the brightness only in its chip" do
    rendered = render_inline(card(on: true, brightness: 60, color_temp_k: 2700))
    assert_equal "An · Weiß", rendered.css("a .small").sole.text
    assert_equal "60 %", rendered.css("span.badge").sole.text.strip
    assert_equal 1, rendered.to_html.scan("60 %").size
  end

  test "colour-on card derives the chip swatch from rgb" do
    rendered = render_inline(card(on: true, brightness: 40, color_r: 255, color_g: 107, color_b: 61))
    assert_equal "An · Farbe", rendered.css("a .small").sole.text
    assert_includes rendered.css("span.badge .sw-swatch").first["style"], "#ff6b3d"
  end

  test "the card links to the detail page and carries the plush knob" do
    rendered = render_inline(card(on: true, brightness: 60))
    assert rendered.css("a[href='/lights/K1'][aria-label='Stehlampe Details']").any?
    assert rendered.css("a.text-reset[aria-label='Stehlampe Details']").any?
    knob = rendered.css("form[action='/lights/K1/command'] button.btn.btn-light.btn-icon.sw-knob.sw-lamp-knob:not(.off)").sole
    assert_equal "", knob.css("img.sw-knob-plush[src*='lamp_floorlamp_on']").sole["alt"]
  end
end
