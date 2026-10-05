require_relative "application_system_test_case"

class LightDetailTest < ApplicationSystemTestCase
  setup do
    Light.delete_all
    LightState.delete_all
    @light = Light.create!(key: "DET1", name: "Uplighter", sku: "H60B0", supports_color: true,
                           supports_color_temp: true, color_temp_min_k: 2200, color_temp_max_k: 6500)
    LightState.record_state(@light.key, on: true, brightness: 70, color_r: 0x4d, color_g: 0x7c, color_b: 0xff,
                                        reachable: true, last_seen_at: Time.current)
  end

  test "the readouts follow the sliders and a preset marks itself when the thumb sits on it" do
    open_detail

    slide "#light_brightness", 40
    assert_selector "output[for=light_brightness]", text: "40 %"

    click_button "Neutral"
    assert_selector "output[for=light_temp]", text: "3.800 K"
    assert_selector "button.active[aria-pressed=true]", text: "Neutral"
    assert_equal "3800", find("#light_temp").value

    slide "#light_temp", 2200
    assert_selector "output[for=light_temp]", text: "2.200 K"
    assert_selector "button.active[aria-pressed=true]", text: "Gemütlich"
    assert_no_selector "button.active", text: "Neutral"
  end

  test "a colour from the wheel is marked on the wheel; a swatch takes the mark back" do
    open_detail
    click_button "Farbe"
    assert_selector "input#light_color_5:checked", visible: :all

    page.execute_script(<<~JS)
      const wheel = document.querySelector("input[type=color]")
      wheel.value = "#b43c8c"
      wheel.dispatchEvent(new Event("input", { bubbles: true }))
    JS
    assert_selector ".ld-swatch-wheel.ld-swatch-custom[style*='#b43c8c']"
    assert_no_selector "input[name=light_color]:checked", visible: :all

    find("label[for=light_color_0]").click
    assert_selector "input#light_color_0:checked", visible: :all
    assert_no_selector ".ld-swatch-custom"
  end

  private

  def open_detail
    visit light_path(@light.key)
    assert_selector "#light_panel_white"
    # Commands are fire-and-forget; keep them off the (absent) MQTT broker.
    page.execute_script("window.fetch = () => Promise.resolve(new Response(null, { status: 204 }))")
  end

  def slide(selector, value)
    page.execute_script(<<~JS, selector, value.to_s)
      const range = document.querySelector(arguments[0])
      range.value = arguments[1]
      range.dispatchEvent(new Event("input", { bubbles: true }))
    JS
  end
end
