# test/govees/messages_test.rb
require "test_helper"
require "govees/messages"

class GoveesMessagesSetTest < ActiveSupport::TestCase
  M = Govees::Messages

  test "power to_wire uses on/off strings and round-trips" do
    assert_equal({ "power" => "on" },  M::Set::Power.new(on: true).to_wire)
    assert_equal({ "power" => "off" }, M::Set::Power.new(on: false).to_wire)
    assert_equal true, M::Set.parse("power" => "on").on
  end

  test "brightness round-trips as integer" do
    assert_equal({ "brightness" => 40 }, M::Set::Brightness.new(value: 40).to_wire)
    assert_equal 40, M::Set.parse("brightness" => 40).value
  end

  test "color carries an Rgb and round-trips" do
    wire = M::Set::Color.new(rgb: { r: 1, g: 2, b: 3 }).to_wire
    assert_equal({ "color" => { "r" => 1, "g" => 2, "b" => 3 } }, wire)
    parsed = M::Set.parse(wire)
    assert_equal [ 1, 2, 3 ], [ parsed.rgb.r, parsed.rgb.g, parsed.rgb.b ]
  end

  test "color_temp round-trips" do
    assert_equal({ "color_temp_k" => 3000 }, M::Set::ColorTemp.new(kelvin: 3000).to_wire)
    assert_equal 3000, M::Set.parse("color_temp_k" => 3000).kelvin
  end

  test "zone carries name + boolean on and round-trips" do
    wire = M::Set::Zone.new(name: "rippleLightToggle", on: true).to_wire
    assert_equal({ "zone" => { "name" => "rippleLightToggle", "on" => true } }, wire)
    z = M::Set.parse(wire)
    assert_equal [ "rippleLightToggle", true ], [ z.name, z.on ]
  end

  test "scene round-trips" do
    assert_equal({ "scene" => "Sunset" }, M::Set::Scene.new(name: "Sunset").to_wire)
    assert_equal "Sunset", M::Set.parse("scene" => "Sunset").name
  end

  test "parse returns nil for an unknown verb" do
    assert_nil M::Set.parse("wat" => 1)
  end
end

class GoveesMessagesStateTest < ActiveSupport::TestCase
  M = Govees::Messages

  test "from_hash defaults on=false and reachable=true when absent" do
    s = M::State.from_hash({})
    assert_equal false, s.on
    assert_equal true,  s.reachable
    assert_equal({ "on" => false, "reachable" => true }, s.to_wire)
  end

  test "to_wire emits only present optional fields" do
    s = M::State.from_hash(on: true, brightness: 60)
    assert_equal({ "on" => true, "reachable" => true, "brightness" => 60 }, s.to_wire)
  end

  test "nil color/color_temp_k are dropped (reset semantics from the store)" do
    s = M::State.from_hash(on: true, color: nil, color_temp_k: nil)
    refute s.to_wire.key?("color")
    refute s.to_wire.key?("color_temp_k")
  end

  test "color round-trips as an Rgb hash" do
    s = M::State.from_hash(on: true, color: { r: 1, g: 2, b: 3 })
    assert_equal({ "r" => 1, "g" => 2, "b" => 3 }, s.to_wire["color"])
    assert_equal 2, M::State.from_hash(s.to_wire).color.g
  end

  test "zone_states keep string keys and boolean values" do
    s = M::State.from_hash(on: true, zone_states: { "powerSwitch" => true })
    assert_equal({ "powerSwitch" => true }, s.to_wire["zone_states"])
  end
end

class GoveesMessagesDeviceStateTest < ActiveSupport::TestCase
  cover "Govees::Messages::DeviceState*"

  M = Govees::Messages

  test "DeviceState: an offline lamp is never on, whatever the cloud remembers" do
    ds = M::DeviceState.from_capabilities({ "powerSwitch" => 1, "online" => false }, zone_keys: [])
    assert_equal false, ds.on
    assert_equal false, ds.reachable
  end

  test "DeviceState: an online lamp adopts powerSwitch as on" do
    assert_equal true,  M::DeviceState.from_capabilities({ "powerSwitch" => 1, "online" => true }, zone_keys: []).on
    assert_equal false, M::DeviceState.from_capabilities({ "powerSwitch" => 0, "online" => true }, zone_keys: []).on
  end

  test "DeviceState maps a raw capability map to telemetry" do
    map = { "powerSwitch" => 1, "online" => true, "brightness" => 70,
            "colorRgb" => (10 << 16) | (20 << 8) | 30, "rippleLightToggle" => 1 }
    ds = M::DeviceState.from_capabilities(map, zone_keys: %w[rippleLightToggle sideLightToggle])
    t = ds.to_telemetry
    assert_equal true, t[:on]
    assert_equal true, t[:reachable]
    assert_equal 70, t[:brightness]
    assert_equal({ r: 10, g: 20, b: 30 }, t[:color])
    assert_equal({ "rippleLightToggle" => true }, t[:zone_states])
  end

  test "DeviceState prefers color_temp_k when colorRgb is absent" do
    ds = M::DeviceState.from_capabilities({ "powerSwitch" => 0, "colorTemperatureK" => 3000 }, zone_keys: [])
    t = ds.to_telemetry
    assert_equal false, t[:on]
    assert_equal 3000, t[:color_temp_k]
    assert_not t.key?(:color)
  end

  test "DeviceState: reachable requires online to equal true or 1, not just be truthy" do
    ds = M::DeviceState.from_capabilities({ "online" => 2, "powerSwitch" => 1 }, zone_keys: [])
    assert_equal false, ds.reachable
    assert_equal false, ds.on
  end

  test "DeviceState: a lenient numeric powerSwitch string still turns the lamp on" do
    ds = M::DeviceState.from_capabilities({ "online" => true, "powerSwitch" => "1abc" }, zone_keys: [])
    assert_equal true, ds.on
  end

  test "DeviceState: a powerSwitch value outside 0/1 never turns the lamp on" do
    ds = M::DeviceState.from_capabilities({ "online" => true, "powerSwitch" => 2 }, zone_keys: [])
    assert_equal false, ds.on
  end

  test "DeviceState: a missing powerSwitch key defaults to off" do
    ds = M::DeviceState.from_capabilities({ "online" => true }, zone_keys: [])
    assert_equal false, ds.on
  end

  test "DeviceState: a lenient numeric colorRgb string is still parsed" do
    ds = M::DeviceState.from_capabilities({ "colorRgb" => "65280.9" }, zone_keys: [])
    assert_equal({ r: 0, g: 255, b: 0 }, ds.to_telemetry[:color])
  end

  test "DeviceState: colorRgb bits beyond the 24-bit range are masked to a valid byte" do
    rgb = (300 << 16) | (200 << 8) | 100
    ds = M::DeviceState.from_capabilities({ "colorRgb" => rgb }, zone_keys: [])
    assert_equal({ r: 44, g: 200, b: 100 }, ds.to_telemetry[:color])
  end

  test "DeviceState: full-intensity odd RGB bytes survive masking exactly" do
    ds = M::DeviceState.from_capabilities({ "colorRgb" => 0xFFFFFF }, zone_keys: [])
    assert_equal({ r: 255, g: 255, b: 255 }, ds.to_telemetry[:color])
  end

  test "DeviceState: an empty-string zone value is excluded, unlike other falsy-looking values" do
    ds = M::DeviceState.from_capabilities({ "rippleLightToggle" => "", "sideLightToggle" => 1 },
                                            zone_keys: [ "rippleLightToggle", "sideLightToggle" ])
    assert_equal({ "sideLightToggle" => true }, ds.to_telemetry[:zone_states])
  end

  test "DeviceState: a zone value outside 0/1 reports off, not on" do
    ds = M::DeviceState.from_capabilities({ "rippleLightToggle" => 2 }, zone_keys: [ "rippleLightToggle" ])
    assert_equal({ "rippleLightToggle" => false }, ds.to_telemetry[:zone_states])
  end

  test "DeviceState: a numeric-string zone value is coerced like an integer" do
    ds = M::DeviceState.from_capabilities({ "rippleLightToggle" => "1" }, zone_keys: [ "rippleLightToggle" ])
    assert_equal({ "rippleLightToggle" => true }, ds.to_telemetry[:zone_states])
  end

  test "DeviceState: a lenient numeric-string zone value with trailing garbage still reports on" do
    ds = M::DeviceState.from_capabilities({ "rippleLightToggle" => "1abc" }, zone_keys: [ "rippleLightToggle" ])
    assert_equal({ "rippleLightToggle" => true }, ds.to_telemetry[:zone_states])
  end

  test "DeviceState: no zone_states attribute when no zone reports a usable value" do
    ds = M::DeviceState.from_capabilities({}, zone_keys: [ "rippleLightToggle" ])
    refute ds.attributes.key?(:zone_states)
  end
end

class GoveesMessagesConfigTest < ActiveSupport::TestCase
  M = Govees::Messages

  Dev = Struct.new(:sku, :name, :supports_color, :supports_color_temp,
                   :color_temp_min_k, :color_temp_max_k, :zones, :scenes,
                   keyword_init: true)

  def build_dev(**overrides)
    Dev.new(sku: "H60B0", name: "Uplighter", supports_color: true,
            supports_color_temp: true, color_temp_min_k: 2700, color_temp_max_k: 6500,
            zones: [ "rippleLightToggle" ], scenes: [ "Sunset" ], **overrides)
  end

  test "from_device emits the curated wire fields" do
    w = M::Config.from_device(build_dev).to_wire
    assert_equal "H60B0", w["sku"]
    assert_equal true, w["supports_color"]
    assert_equal [ "rippleLightToggle" ], w["zones"]
    assert_equal [ "Sunset" ], w["scenes"]
  end

  test "from_device carries the color temperature range and round-trips through from_hash" do
    w = M::Config.from_device(build_dev).to_wire
    assert_equal 2700, w["color_temp_min_k"]
    assert_equal 6500, w["color_temp_max_k"]
    c = M::Config.from_hash(w)
    assert_equal 2700, c.color_temp_min_k
    assert_equal 6500, c.color_temp_max_k
  end

  test "from_hash defaults absent collections, flags and range" do
    c = M::Config.from_hash("sku" => "H60B0", "name" => "L")
    assert_equal [], c.zones
    assert_equal false, c.supports_color
    assert_nil c.color_temp_min_k
    assert_nil c.color_temp_max_k
  end
end
