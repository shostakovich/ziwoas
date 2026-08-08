require "test_helper"

class SwitchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    SwitchRule.delete_all
    PlugState.delete_all
    SwitchCommand.delete_all
    Sample.delete_all
    Light.delete_all
    @light = Light.create!(key: "ABCDEF01", name: "Wohnzimmer Stehlampe", sku: "H607C")
    LightState.record_state(@light.key, on: true, brightness: 60, color_temp_k: 2700)
  end

  test "lamp tile links to the detail page and exposes a toggle knob" do
    get switches_url
    assert_response :success
    assert_select "a.sw-light-link[href=?]", light_path(@light.key)
    assert_select ".sw-light-card[data-light-key=?] button.sw-knob", @light.key
    assert_match "Wohnzimmer Stehlampe", @response.body
    assert_match "An · Weiß · 60 %", @response.body
  end

  test "lamp tile knob carries the per-SKU plush class" do
    get switches_url
    assert_select "button.sw-lamp-knob.plush-floorlamp"
  end

  test "lamp knob is a turbo button_to form and the page streams lamp updates" do
    get switches_url
    assert_response :success
    # Knob posts the toggle as a real form (Turbo-driven), no Stimulus needed.
    assert_select "form[action=?] button.sw-knob", light_command_path(light_key: @light.key)
    # @light is on -> the knob posts the opposite (off).
    assert_select "form[action=?] input[name=on][value=false]", light_command_path(light_key: @light.key)
    # Live MQTT reconcile arrives via a Turbo Stream subscription, not ActionCable JS.
    assert_select "turbo-cable-stream-source"
  end

  test "GET /switches lists only switchable plugs" do
    get "/switches"
    assert_response :success
    assert_match "Kühlschrank", @response.body       # fridge: switchable in ziwoas.test.yml
    assert_no_match(/Balkonkraftwerk/, @response.body)  # bkw: producer, not switchable
  end

  # One string hit as a smoke probe that the row really reaches the page; what a
  # row is made of is the component's own test.
  test "shows the plug's schedule" do
    SwitchRules::SaveWindow.call(
      plug_id: "fridge",
      attrs:   { on_at_time: "18:00", off_at_time: "23:00", days: [ 1, 2, 3, 4, 5 ] }
    )
    get "/switches"
    assert_match "Mo–Fr · 18:00–23:00", @response.body
    assert_select "#sw_card_fridge a.sw-add", count: 2
  end

  test "the summary counts Schaltzeiten, not rows" do
    SwitchRules::SaveWindow.call(
      plug_id: "fridge", attrs: { on_at_time: "18:00", off_at_time: "23:00", days: [ 1 ] }
    )
    2.times do |i|
      SwitchRules::SaveSingle.call(
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
    SwitchRules::SaveSingle.call(
      plug_id: "gone", attrs: { at_minute_time: "01:00", action: "off", days: [ 1 ] }
    )
    get "/switches"
    assert_no_match(/gone/, @response.body)
    assert_equal 1, SwitchRule.where(plug_id: "gone").count
  end
end
