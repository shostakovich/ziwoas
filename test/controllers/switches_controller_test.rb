require "test_helper"

class SwitchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Switching::Rule.delete_all
    Plugs::State.delete_all
    Switching::Command.delete_all
    Plugs::Sample.delete_all
    Light.delete_all
    @light = Light.create!(key: "ABCDEF01", name: "Wohnzimmer Stehlampe", sku: "H607C")
    LightState.record_state(@light.key, on: true, brightness: 60, color_temp_k: 2700)
  end

  test "lamp tile links to the detail page and exposes a toggle knob" do
    get switches_url
    assert_response :success
    assert_select "#light_card_#{@light.key} a[aria-label='Wohnzimmer Stehlampe Details'][href=?]", light_path(@light.key)
    assert_select ".card[data-light-key=?] button.sw-knob", @light.key
    assert_match "Wohnzimmer Stehlampe", @response.body
    assert_select "#light_card_#{@light.key} .small", text: "An · Weiß"
    assert_select "#light_card_#{@light.key} span.badge", text: "60 %"
  end

  test "lamp tile knob shows the lamp's own plush" do
    get switches_url
    assert_select "button.sw-lamp-knob img.sw-knob-plush[src*='lamp_floorlamp_']"
  end

  test "lamp knob is a turbo button_to form and the page streams lamp updates" do
    get switches_url
    assert_response :success
    assert_select "form[action=?] button.sw-knob", light_command_path(light_key: @light.key)
    assert_select "form[action=?] input[name=on][value=false]", light_command_path(light_key: @light.key)
    assert_select "turbo-cable-stream-source"
  end

  test "GET /switches lists only switchable plugs" do
    get "/switches"
    assert_response :success
    assert_match "Kühlschrank", @response.body       # fridge: switchable in ziwoas.test.yml
    assert_no_match(/Balkonkraftwerk/, @response.body)  # bkw: producer, not switchable
  end

  test "shows the plug's schedule" do
    Switching::Rules::SaveWindow.call(
      plug_id: "fridge",
      attrs:   { on_at_time: "18:00", off_at_time: "23:00", days: [ 1, 2, 3, 4, 5 ] }
    )
    get "/switches"
    assert_match "Mo–Fr · 18:00–23:00", @response.body
    assert_select "#sw_card_fridge a[data-turbo-stream]", text: /\A\+ /, count: 2
  end

  test "the summary counts Schaltzeiten, not rows" do
    Switching::Rules::SaveWindow.call(
      plug_id: "fridge", attrs: { on_at_time: "18:00", off_at_time: "23:00", days: [ 1 ] }
    )
    2.times do |i|
      Switching::Rules::SaveSingle.call(
        plug_id: "fridge", attrs: { at_minute_time: "0#{i + 1}:00", action: "off", days: [ 1 ] }
      )
    end

    get "/switches"
    assert_select "#sw_card_fridge summary", "Schaltzeiten (4)"
  end

  test "a plug without a schedule shows the bare summary" do
    get "/switches"
    assert_select "#sw_card_fridge summary", "Schaltzeiten"
  end

  test "rules of a plug that left ziwoas.yml stay out of sight, not deleted" do
    Switching::Rules::SaveSingle.call(
      plug_id: "gone", attrs: { at_minute_time: "01:00", action: "off", days: [ 1 ] }
    )
    get "/switches"
    assert_no_match(/gone/, @response.body)
    assert_equal 1, Switching::Rule.where(plug_id: "gone").count
  end

  test "a plug that reports power shows its watts under the knob" do
    Plugs::Sample.create!(plug_id: "fridge", ts: Time.current.to_i, apower_w: 84.4, aenergy_wh: 1)
    Plugs::State.create!(plug_id: "fridge", output: true)
    get "/switches"
    assert_select "#sw_head_fridge button.btn.btn-light.btn-icon.sw-knob:not(.off)[aria-label='Kühlschrank ausschalten'] img[src*='switch_plush_on']"
    assert_select "#sw_head_fridge .badge", text: /84 W/
    assert_select "#sw_card_fridge.opacity-75", false
  end

  test "the watt chip groups thousands the German way" do
    Plugs::Sample.create!(plug_id: "fridge", ts: Time.current.to_i, apower_w: 1980.2, aenergy_wh: 1)
    Plugs::State.create!(plug_id: "fridge", output: true)
    get "/switches"
    assert_select "#sw_head_fridge .badge", text: /\A⚡1\.980 W\z/
  end

  test "a silent plug is dimmed, its knob disabled and without watts" do
    get "/switches"
    assert_select "#sw_card_fridge.card.opacity-75"
    assert_select "#sw_head_fridge button.sw-knob.off[disabled] img[src*='switch_plush_off']"
    assert_select "#sw_head_fridge .badge", false
  end

  test "without switchable plugs the page says how to mark one" do
    ConfigLoader.stub :app_config, Struct.new(:plugs).new([]) do
      get "/switches"
    end
    assert_select ".card h2.card-title", text: "Keine schaltbaren Steckdosen"
  end
end
