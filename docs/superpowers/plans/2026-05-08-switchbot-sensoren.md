# SwitchBot-Sensoren Integration – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate two SwitchBot Meter Pro CO₂ Monitors and one SwitchBot Outdoor Meter into ZiWoAS via the SwitchBot Cloud API v1.1, with a new "Sensoren" tab showing live values + 24h charts and outdoor temperature feeding the Wetter tab.

**Architecture:** A `SensorPollJob` (every 15 min via SolidQueue) calls a `SwitchBotClient` (HMAC-signed cloud API), persists `SensorReading` rows, and broadcasts a Turbo stream. A new `SensorsController` renders the tab; `WeatherController` reuses the latest outdoor reading.

**Tech Stack:** Rails 8.1, SQLite, SolidQueue, Net::HTTP (no Faraday), Turbo Streams, Chart.js (vendored), Stimulus, Minitest + WebMock.

**Spec:** `docs/superpowers/specs/2026-05-08-switchbot-sensoren-design.md`

---

## File Map

**New files:**

- `db/migrate/<TS>_create_sensor_readings.rb` — table for all polled readings
- `app/models/sensor_reading.rb` — AR model + `latest_per_device` helper
- `lib/switch_bot_client.rb` — Cloud-API client with HMAC signing
- `app/jobs/sensor_poll_job.rb` — orchestrator: poll → persist → broadcast
- `lib/sensors_broadcaster.rb` — Turbo stream broadcasts (mirrors `lib/weather_broadcaster.rb`)
- `app/controllers/sensors_controller.rb` — `index` (HTML) + `series` (JSON for charts)
- `app/helpers/sensors_helper.rb` — CO₂-Ampel logic + asset path helper
- `app/views/sensors/index.html.erb`
- `app/views/sensors/_indoor.html.erb`
- `app/views/sensors/_outdoor.html.erb`
- `app/views/sensors/_card.html.erb`
- `app/views/sensors/_battery_warning.html.erb`
- `app/views/sensors/_charts.html.erb`
- `app/javascript/controllers/sensors_chart_controller.js` — Stimulus + Chart.js
- `app/assets/stylesheets/sensors.css` — sensor-tab specific styles
- `lib/tasks/switchbot.rake` — `bin/rails switchbot:list_devices`
- Tests: `test/test_switch_bot_client.rb`, `test/models/sensor_reading_test.rb`, `test/jobs/sensor_poll_job_test.rb`, `test/controllers/sensors_controller_test.rb`, `test/helpers/sensors_helper_test.rb`, `test/test_sensors_broadcaster.rb`

**Modified files:**

- `lib/config_loader.rb` — add `room` to `PlugCfg`, add `Switchbot`/`Sensor` structs and validators
- `config/ziwoas.example.yml` — example block
- `config/ziwoas.test.yml` — test fixtures
- `config/recurring.yml` — `poll_sensors` schedule
- `config/routes.rb` — `resources :sensors, only: [:index]` + `get "/sensors/series"`
- `app/views/layouts/application.html.erb` — nav link
- `app/controllers/weather_controller.rb` — fetch latest outdoor reading
- `app/views/weather/_current.html.erb` — prefer sensor temp over Brightsky when fresh
- `test/test_config_loader.rb` — new tests for room/switchbot/sensors

**Image assets** (placed by user before/during implementation):

- `app/assets/images/co2_good.png`
- `app/assets/images/co2_warn.png`
- `app/assets/images/co2_bad.png`

---

## Task 1: Migration `sensor_readings`

**Files:**
- Create: `db/migrate/20260508000000_create_sensor_readings.rb`

- [ ] **Step 1: Write the migration**

```ruby
class CreateSensorReadings < ActiveRecord::Migration[8.1]
  def change
    create_table :sensor_readings do |t|
      t.string   :device_id,        null: false
      t.datetime :taken_at,         null: false
      t.float    :temperature
      t.integer  :humidity
      t.integer  :co2
      t.integer  :battery_pct
      t.string   :firmware_version
      t.timestamps
    end

    add_index :sensor_readings, [ :device_id, :taken_at ]
    add_index :sensor_readings, :taken_at
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: `==  CreateSensorReadings: migrated`

- [ ] **Step 3: Verify schema**

Run: `bin/rails runner "puts SensorReading.connection.columns(:sensor_readings).map(&:name)"`
Expected: prints `id device_id taken_at temperature humidity co2 battery_pct firmware_version created_at updated_at` (note: this requires the model file from Task 2 — if not yet created, instead use `bin/rails runner "puts ActiveRecord::Base.connection.columns(:sensor_readings).map(&:name)"`).

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260508000000_create_sensor_readings.rb db/schema.rb
git commit -m "Add sensor_readings table for SwitchBot integration"
```

---

## Task 2: `SensorReading` model + tests

**Files:**
- Create: `app/models/sensor_reading.rb`
- Create: `test/models/sensor_reading_test.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/models/sensor_reading_test.rb
require "test_helper"

class SensorReadingTest < ActiveSupport::TestCase
  test "for_device scope filters by device_id" do
    a = SensorReading.create!(device_id: "AAA", taken_at: 1.hour.ago, temperature: 20.0)
    SensorReading.create!(device_id: "BBB", taken_at: 1.hour.ago, temperature: 21.0)
    assert_equal [ a.id ], SensorReading.for_device("AAA").pluck(:id)
  end

  test "since scope returns rows at-or-after timestamp" do
    cutoff = 30.minutes.ago
    older  = SensorReading.create!(device_id: "X", taken_at: 2.hours.ago, temperature: 1.0)
    newer  = SensorReading.create!(device_id: "X", taken_at: 10.minutes.ago, temperature: 2.0)
    ids = SensorReading.since(cutoff).pluck(:id)
    refute_includes ids, older.id
    assert_includes ids, newer.id
  end

  test "latest_per_device returns one row per device with max taken_at" do
    SensorReading.create!(device_id: "A", taken_at: 2.hours.ago, temperature: 18.0)
    a_new = SensorReading.create!(device_id: "A", taken_at: 5.minutes.ago, temperature: 22.0)
    b_new = SensorReading.create!(device_id: "B", taken_at: 10.minutes.ago, temperature: 14.0)

    rows = SensorReading.latest_per_device([ "A", "B" ]).order(:device_id)
    assert_equal [ a_new.id, b_new.id ], rows.pluck(:id)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/sensor_reading_test.rb`
Expected: FAIL with `uninitialized constant SensorReading`

- [ ] **Step 3: Implement model**

```ruby
# app/models/sensor_reading.rb
class SensorReading < ApplicationRecord
  scope :for_device, ->(id) { where(device_id: id) }
  scope :since,      ->(t)  { where("taken_at >= ?", t) }

  def self.latest_per_device(device_ids)
    return none if device_ids.blank?
    where(device_id: device_ids)
      .where("taken_at = (SELECT MAX(taken_at) FROM sensor_readings sr2
                          WHERE sr2.device_id = sensor_readings.device_id)")
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/sensor_reading_test.rb`
Expected: 3 runs, 0 failures, 0 errors

- [ ] **Step 5: Commit**

```bash
git add app/models/sensor_reading.rb test/models/sensor_reading_test.rb
git commit -m "Add SensorReading model with latest_per_device helper"
```

---

## Task 3: `ConfigLoader` – add optional `room` to plugs

**Files:**
- Modify: `lib/config_loader.rb`
- Modify: `test/test_config_loader.rb`

- [ ] **Step 1: Write failing test**

Append to `test/test_config_loader.rb` before final `end`:

```ruby
  def test_loads_optional_plug_room
    yaml = valid_yaml.sub("name: Balkonkraftwerk\n          role: producer",
                          "name: Balkonkraftwerk\n          role: producer\n          room: Balkon")
    cfg = load_yaml(yaml)
    plug = cfg.plugs.find { |p| p.id == "bkw" }
    assert_equal "Balkon", plug.room
  end

  def test_plug_room_is_optional_and_defaults_to_nil
    cfg = load_yaml(valid_yaml)
    plug = cfg.plugs.find { |p| p.id == "fridge" }
    assert_nil plug.room
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/test_config_loader.rb -n test_loads_optional_plug_room`
Expected: FAIL with `wrong number of arguments` or `undefined method room`

- [ ] **Step 3: Add `room` to `PlugCfg` struct and `PlugValidator`**

Modify `lib/config_loader.rb`:

Replace the `PlugCfg` line (around line 7) with:
```ruby
  PlugCfg     = Struct.new(:id, :name, :role, :ain, :driver, :room, keyword_init: true)
```

Replace `build_plug` in `PlugValidator` (around lines 54-62) with:
```ruby
    def build_plug(id, name, role, driver)
      room = @h["room"].nil? ? nil : require_string(@h["room"], "plugs[#{@index}].room")
      if driver == :shelly
        raise ConfigLoader::Error, "plugs[#{@index}].ain must not be set for driver: shelly" if @h["ain"]
        ConfigLoader::PlugCfg.new(id: id, name: name, role: role, driver: :shelly, ain: nil, room: room)
      else
        raise ConfigLoader::Error, "plugs[#{@index}].ain is required for driver: fritz_dect" if @h["ain"].nil? || @h["ain"].to_s.empty?
        ConfigLoader::PlugCfg.new(id: id, name: name, role: role, driver: :fritz_dect, ain: @h["ain"].to_s, room: room)
      end
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/test_config_loader.rb`
Expected: all tests pass (including pre-existing ones)

- [ ] **Step 5: Commit**

```bash
git add lib/config_loader.rb test/test_config_loader.rb
git commit -m "Add optional room field to plug config"
```

---

## Task 4: `ConfigLoader` – add `switchbot:` and `sensors:` blocks

**Files:**
- Modify: `lib/config_loader.rb`
- Modify: `test/test_config_loader.rb`

- [ ] **Step 1: Write failing tests**

Append to `test/test_config_loader.rb`:

```ruby
  def test_loads_switchbot_and_sensors
    cfg = load_yaml(valid_yaml + <<~YAML)
      switchbot:
        token: "tok-abc"
        secret: "sec-xyz"
      sensors:
        - id: "ABCDEF"
          name: "Wohnzimmer"
          type: meter_pro_co2
          room: "Wohnzimmer"
        - id: "FEDCBA"
          name: "Schlafzimmer"
          type: meter_pro_co2
        - id: "112233"
          name: "Balkon"
          type: outdoor_meter
    YAML

    assert_equal "tok-abc", cfg.switchbot.token
    assert_equal "sec-xyz", cfg.switchbot.secret

    assert_equal 3, cfg.sensors.length
    s = cfg.sensors.first
    assert_equal "ABCDEF", s.id
    assert_equal "Wohnzimmer", s.name
    assert_equal :meter_pro_co2, s.type
    assert_equal "Wohnzimmer", s.room

    assert_nil cfg.sensors[1].room
    assert_equal :outdoor_meter, cfg.sensors[2].type
  end

  def test_switchbot_and_sensors_are_optional
    cfg = load_yaml(valid_yaml)
    assert_nil cfg.switchbot
    assert_equal [], cfg.sensors
  end

  def test_rejects_switchbot_missing_token
    err = assert_raises(ConfigLoader::Error) do
      load_yaml(valid_yaml + <<~YAML)
        switchbot:
          secret: "sec-only"
      YAML
    end
    assert_match(/switchbot\.token/i, err.message)
  end

  def test_rejects_unknown_sensor_type
    err = assert_raises(ConfigLoader::Error) do
      load_yaml(valid_yaml + <<~YAML)
        switchbot:
          token: "t"
          secret: "s"
        sensors:
          - id: "X"
            name: "X"
            type: foo_meter
      YAML
    end
    assert_match(/sensors\[0\]\.type/i, err.message)
  end

  def test_rejects_duplicate_sensor_ids
    err = assert_raises(ConfigLoader::Error) do
      load_yaml(valid_yaml + <<~YAML)
        switchbot:
          token: "t"
          secret: "s"
        sensors:
          - id: "DUP"
            name: "A"
            type: meter_pro_co2
          - id: "DUP"
            name: "B"
            type: meter_pro_co2
      YAML
    end
    assert_match(/duplicate sensor id/i, err.message)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/test_config_loader.rb -n /switchbot|sensors/`
Expected: FAIL — `undefined method switchbot`, etc.

- [ ] **Step 3: Implement config loader changes**

Modify `lib/config_loader.rb`:

Replace `Config = Struct.new(...)` (around line 13-15) with:
```ruby
  SwitchbotCfg = Struct.new(:token, :secret, keyword_init: true)
  SensorCfg    = Struct.new(:id, :name, :type, :room, keyword_init: true)
  Config       = Struct.new(:electricity_price_eur_per_kwh, :timezone,
                            :mqtt, :fritz_poll, :plugs, :fritz_box, :weather,
                            :switchbot, :sensors,
                            keyword_init: true)
```

Add constant near `VALID_DRIVERS`:
```ruby
  VALID_SENSOR_TYPES = %i[meter_pro_co2 outdoor_meter].freeze
```

Add `build_switchbot` and `build_sensors` calls in `#build` (after `weather = build_weather(...)`):
```ruby
    switchbot = build_switchbot(@raw["switchbot"])
    sensors   = build_sensors(@raw["sensors"])
```

Pass them to `Config.new(...)`:
```ruby
    Config.new(
      electricity_price_eur_per_kwh: price,
      timezone:   tz,
      mqtt:       mqtt,
      fritz_poll: fritz_poll,
      plugs:      plugs,
      fritz_box:  fritz_box,
      weather:    weather,
      switchbot:  switchbot,
      sensors:    sensors,
    )
```

Add private methods near `build_weather`:
```ruby
  def build_switchbot(h)
    return nil if h.nil?
    h = require_hash(h, "switchbot")
    SwitchbotCfg.new(
      token:  require_string(h["token"],  "switchbot.token"),
      secret: require_string(h["secret"], "switchbot.secret"),
    )
  end

  def build_sensors(list)
    return [] if list.nil?
    raise Error, "sensors must be a list" unless list.is_a?(Array)

    seen = []
    list.map.with_index do |h, i|
      raise Error, "sensors[#{i}] must be a mapping" unless h.is_a?(Hash)
      id   = require_string(h["id"],   "sensors[#{i}].id")
      name = require_string(h["name"], "sensors[#{i}].name")
      type = require_string(h["type"], "sensors[#{i}].type").to_sym
      raise Error, "sensors[#{i}].type must be one of #{VALID_SENSOR_TYPES}" unless VALID_SENSOR_TYPES.include?(type)
      raise Error, "duplicate sensor id '#{id}'" if seen.include?(id)
      seen << id
      room = h["room"].nil? ? nil : require_string(h["room"], "sensors[#{i}].room")
      SensorCfg.new(id: id, name: name, type: type, room: room)
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/test_config_loader.rb`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/config_loader.rb test/test_config_loader.rb
git commit -m "Add switchbot and sensors blocks to config loader"
```

---

## Task 5: `SwitchBotClient` – HMAC + `device_status`

**Files:**
- Create: `lib/switch_bot_client.rb`
- Create: `test/test_switch_bot_client.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/test_switch_bot_client.rb
require "test_helper"
require "switch_bot_client"

class SwitchBotClientTest < Minitest::Test
  TOKEN  = "tok-123"
  SECRET = "sec-xyz"

  def setup
    @client = SwitchBotClient.new(token: TOKEN, secret: SECRET)
  end

  def test_device_status_meter_pro_co2_normalizes_fields
    stub_request(:get, "https://api.switch-bot.com/v1.1/devices/ABC/status")
      .to_return(status: 200, body: {
        statusCode: 100,
        message: "success",
        body: {
          deviceId: "ABC", deviceType: "MeterPro(CO2)", hubDeviceId: "HUB",
          temperature: 21.4, humidity: 52, CO2: 612, battery: 85, version: "V1.2"
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    data = @client.device_status("ABC")

    assert_in_delta 21.4, data[:temperature]
    assert_equal 52,  data[:humidity]
    assert_equal 612, data[:co2]
    assert_equal 85,  data[:battery_pct]
    assert_equal "V1.2", data[:firmware_version]
  end

  def test_device_status_outdoor_meter_has_nil_co2
    stub_request(:get, "https://api.switch-bot.com/v1.1/devices/OUT/status")
      .to_return(status: 200, body: {
        statusCode: 100,
        message: "success",
        body: {
          deviceId: "OUT", deviceType: "WoIOSensor", hubDeviceId: "HUB",
          temperature: 12.3, humidity: 71, battery: 100, version: "V4.2"
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    data = @client.device_status("OUT")

    assert_nil data[:co2]
    assert_in_delta 12.3, data[:temperature]
    assert_equal 71, data[:humidity]
    assert_equal 100, data[:battery_pct]
  end

  def test_device_status_sends_signed_headers
    captured = nil
    stub_request(:get, "https://api.switch-bot.com/v1.1/devices/X/status")
      .with { |req| captured = req.headers; true }
      .to_return(status: 200, body: { statusCode: 100, body: {
        deviceType: "MeterPro(CO2)", temperature: 1, humidity: 1, CO2: 1, battery: 1
      } }.to_json)

    @client.device_status("X")

    assert_equal TOKEN, captured["Authorization"]
    refute_nil captured["T"] || captured["t"]
    refute_nil captured["Nonce"] || captured["nonce"]
    refute_nil captured["Sign"] || captured["sign"]
  end

  def test_device_status_raises_on_non_success_status_code
    stub_request(:get, "https://api.switch-bot.com/v1.1/devices/X/status")
      .to_return(status: 200, body: { statusCode: 161, message: "device offline", body: {} }.to_json)

    err = assert_raises(SwitchBotClient::Error) { @client.device_status("X") }
    assert_match(/device offline/i, err.message)
  end

  def test_device_status_raises_on_http_error
    stub_request(:get, "https://api.switch-bot.com/v1.1/devices/X/status")
      .to_return(status: 500, body: "")

    err = assert_raises(SwitchBotClient::Error) { @client.device_status("X") }
    assert_match(/http 500/i, err.message)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/test_switch_bot_client.rb`
Expected: FAIL — `cannot load such file -- switch_bot_client`

- [ ] **Step 3: Implement client**

```ruby
# lib/switch_bot_client.rb
require "json"
require "net/http"
require "uri"
require "openssl"
require "base64"
require "securerandom"

class SwitchBotClient
  BASE_URL = "https://api.switch-bot.com"

  class Error < StandardError; end

  def initialize(token:, secret:, http_timeout: 4)
    @token        = token
    @secret       = secret
    @http_timeout = http_timeout
  end

  # Returns Hash:
  #   { temperature:, humidity:, co2:, battery_pct:, firmware_version:, raw: }
  def device_status(device_id)
    body = get_json("/v1.1/devices/#{device_id}/status")
    normalize_status(body.fetch("body", {}))
  end

  private

  def get_json(path)
    uri = URI(BASE_URL + path)
    response = Net::HTTP.start(uri.host, uri.port,
                               use_ssl: true,
                               read_timeout: @http_timeout,
                               open_timeout: @http_timeout) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      signed_headers.each { |k, v| req[k] = v }
      http.request(req)
    end
    raise Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    json = JSON.parse(response.body)
    code = json["statusCode"]
    raise Error, "SwitchBot API: #{json["message"] || "status #{code}"}" unless code == 100
    json
  rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    raise Error, e.message
  end

  def signed_headers
    t     = (Time.now.to_f * 1000).to_i.to_s
    nonce = SecureRandom.uuid
    sign  = Base64.strict_encode64(
              OpenSSL::HMAC.digest("SHA256", @secret, "#{@token}#{t}#{nonce}")
            )
    {
      "Authorization" => @token,
      "t"             => t,
      "nonce"         => nonce,
      "sign"          => sign,
      "Content-Type"  => "application/json"
    }
  end

  def normalize_status(b)
    {
      temperature:      b["temperature"],
      humidity:         b["humidity"],
      co2:              b["CO2"],                        # nil for WoIOSensor
      battery_pct:      b["battery"],
      firmware_version: b["version"],
      raw:              b
    }
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/test_switch_bot_client.rb`
Expected: 5 runs, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/switch_bot_client.rb test/test_switch_bot_client.rb
git commit -m "Add SwitchBotClient with device_status and HMAC signing"
```

---

## Task 6: `SwitchBotClient#list_sensor_devices`

**Files:**
- Modify: `lib/switch_bot_client.rb`
- Modify: `test/test_switch_bot_client.rb`

- [ ] **Step 1: Write failing test**

Append to `test/test_switch_bot_client.rb`:

```ruby
  def test_list_sensor_devices_filters_to_meters
    stub_request(:get, "https://api.switch-bot.com/v1.1/devices")
      .to_return(status: 200, body: {
        statusCode: 100,
        body: {
          deviceList: [
            { deviceId: "AAA", deviceName: "Wohnzimmer", deviceType: "MeterPro(CO2)" },
            { deviceId: "BBB", deviceName: "Balkon",     deviceType: "WoIOSensor" },
            { deviceId: "HUB", deviceName: "Hub Wohn",   deviceType: "Hub 2" }
          ]
        }
      }.to_json)

    devices = @client.list_sensor_devices

    assert_equal 2, devices.length
    assert_equal({ id: "AAA", name: "Wohnzimmer", type: :meter_pro_co2 }, devices[0])
    assert_equal({ id: "BBB", name: "Balkon",     type: :outdoor_meter }, devices[1])
  end

  def test_list_all_devices_returns_full_list
    stub_request(:get, "https://api.switch-bot.com/v1.1/devices")
      .to_return(status: 200, body: {
        statusCode: 100,
        body: {
          deviceList: [
            { deviceId: "HUB", deviceName: "Hub", deviceType: "Hub 2" }
          ]
        }
      }.to_json)

    all = @client.list_all_devices
    assert_equal 1, all.length
    assert_equal "Hub", all[0][:name]
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/test_switch_bot_client.rb -n /list_/`
Expected: FAIL — `undefined method list_sensor_devices`

- [ ] **Step 3: Implement methods**

Add to `lib/switch_bot_client.rb` (public area, before `private`):

```ruby
  TYPE_MAP = {
    "MeterPro(CO2)" => :meter_pro_co2,
    "WoIOSensor"    => :outdoor_meter
  }.freeze

  def list_all_devices
    body = get_json("/v1.1/devices")
    body.fetch("body", {}).fetch("deviceList", []).map do |d|
      { id: d["deviceId"], name: d["deviceName"], device_type: d["deviceType"] }
    end
  end

  def list_sensor_devices
    list_all_devices.filter_map do |d|
      type = TYPE_MAP[d[:device_type]]
      next nil unless type
      { id: d[:id], name: d[:name], type: type }
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/test_switch_bot_client.rb`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/switch_bot_client.rb test/test_switch_bot_client.rb
git commit -m "Add list_sensor_devices and list_all_devices to SwitchBotClient"
```

---

## Task 7: `SensorsBroadcaster` module

**Files:**
- Create: `lib/sensors_broadcaster.rb`
- Create: `test/test_sensors_broadcaster.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/test_sensors_broadcaster.rb
require "test_helper"
require "sensors_broadcaster"

class SensorsBroadcasterTest < ActiveSupport::TestCase
  test "broadcasts replace to sensors stream targeting the dashboard" do
    calls = []
    Turbo::StreamsChannel.stub(:broadcast_replace_to,
                               ->(stream, **opts) { calls << [ stream, opts[:target] ] }) do
      SensorsBroadcaster.refresh
    end
    assert_includes calls, [ "sensors", "sensors_dashboard" ]
  end
end
```

- [ ] **Step 2: Run test to verify failure**

Run: `bin/rails test test/test_sensors_broadcaster.rb`
Expected: FAIL — `cannot load such file -- sensors_broadcaster`

- [ ] **Step 3: Implement module**

```ruby
# lib/sensors_broadcaster.rb
require "config_loader"

module SensorsBroadcaster
  STREAM = "sensors".freeze

  module_function

  def refresh
    config = load_config
    return if config.nil? || config.sensors.empty?

    latest = SensorReading.latest_per_device(config.sensors.map(&:id)).index_by(&:device_id)

    Turbo::StreamsChannel.broadcast_replace_to(
      STREAM,
      target: "sensors_dashboard",
      partial: "sensors/dashboard",
      locals: { sensors: config.sensors, latest: latest }
    )
  end

  def load_config
    path = Rails.root.join("config", Rails.env.test? ? "ziwoas.test.yml" : "ziwoas.yml").to_s
    ConfigLoader.load(path)
  rescue Errno::ENOENT
    nil
  end
end
```

- [ ] **Step 4: Run test to verify pass**

Run: `bin/rails test test/test_sensors_broadcaster.rb`
Expected: 1 run, 0 failures (the test stubs the channel; it does need the config + model — see note below)

Note: this test depends on `config/ziwoas.test.yml` having a `switchbot:` and `sensors:` block. If the test fails because the config has no sensors, defer this test until Task 19 has run, or add the config block now via:

```bash
# in config/ziwoas.test.yml — append before running test:
cat >> config/ziwoas.test.yml <<'YAML'
switchbot:
  token: "test-tok"
  secret: "test-sec"
sensors:
  - id: "TEST_INDOOR"
    name: "Test Wohnzimmer"
    type: meter_pro_co2
    room: "Wohnzimmer"
  - id: "TEST_OUTDOOR"
    name: "Test Balkon"
    type: outdoor_meter
YAML
```

- [ ] **Step 5: Commit**

```bash
git add lib/sensors_broadcaster.rb test/test_sensors_broadcaster.rb config/ziwoas.test.yml
git commit -m "Add SensorsBroadcaster for Turbo stream updates"
```

---

## Task 8: `SensorPollJob`

**Files:**
- Create: `app/jobs/sensor_poll_job.rb`
- Create: `test/jobs/sensor_poll_job_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/jobs/sensor_poll_job_test.rb
require "test_helper"

class SensorPollJobTest < ActiveJob::TestCase
  def fake_config(switchbot:, sensors:)
    Struct.new(:switchbot, :sensors).new(switchbot, sensors)
  end

  def fake_sb(token:, secret:)
    Struct.new(:token, :secret).new(token, secret)
  end

  def fake_sensor(id, type)
    Struct.new(:id, :name, :type, :room).new(id, "name-#{id}", type, nil)
  end

  test "creates a SensorReading for each sensor" do
    config = fake_config(
      switchbot: fake_sb(token: "t", secret: "s"),
      sensors: [ fake_sensor("A", :meter_pro_co2), fake_sensor("B", :outdoor_meter) ]
    )

    fake_client = Object.new
    def fake_client.device_status(id)
      { temperature: 20.0, humidity: 50, co2: (id == "A" ? 600 : nil),
        battery_pct: 80, firmware_version: "V1", raw: {} }
    end

    ConfigLoader.stub(:load, config) do
      SwitchBotClient.stub(:new, fake_client) do
        SensorsBroadcaster.stub(:refresh, nil) do
          assert_difference "SensorReading.count", 2 do
            SensorPollJob.perform_now
          end
        end
      end
    end

    rows = SensorReading.order(:device_id)
    assert_equal "A", rows[0].device_id
    assert_equal 600, rows[0].co2
    assert_nil rows[1].co2
  end

  test "isolates per-sensor errors so the job continues" do
    config = fake_config(
      switchbot: fake_sb(token: "t", secret: "s"),
      sensors: [ fake_sensor("A", :meter_pro_co2), fake_sensor("B", :outdoor_meter) ]
    )

    fake_client = Object.new
    def fake_client.device_status(id)
      raise SwitchBotClient::Error, "boom" if id == "A"
      { temperature: 12.0, humidity: 60, co2: nil, battery_pct: 100, firmware_version: "V1", raw: {} }
    end

    ConfigLoader.stub(:load, config) do
      SwitchBotClient.stub(:new, fake_client) do
        SensorsBroadcaster.stub(:refresh, nil) do
          assert_difference "SensorReading.count", 1 do
            SensorPollJob.perform_now
          end
        end
      end
    end

    assert_equal "B", SensorReading.last.device_id
  end

  test "no-ops when switchbot config is missing" do
    config = fake_config(switchbot: nil, sensors: [])
    ConfigLoader.stub(:load, config) do
      assert_no_difference "SensorReading.count" do
        SensorPollJob.perform_now
      end
    end
  end

  test "broadcasts after polling" do
    config = fake_config(
      switchbot: fake_sb(token: "t", secret: "s"),
      sensors: [ fake_sensor("A", :meter_pro_co2) ]
    )
    fake_client = Object.new
    def fake_client.device_status(_)
      { temperature: 1, humidity: 1, co2: 1, battery_pct: 1, firmware_version: "V", raw: {} }
    end

    called = false
    ConfigLoader.stub(:load, config) do
      SwitchBotClient.stub(:new, fake_client) do
        SensorsBroadcaster.stub(:refresh, -> { called = true }) do
          SensorPollJob.perform_now
        end
      end
    end
    assert called, "expected SensorsBroadcaster.refresh to be called"
  end
end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `bin/rails test test/jobs/sensor_poll_job_test.rb`
Expected: FAIL — `uninitialized constant SensorPollJob`

- [ ] **Step 3: Implement job**

```ruby
# app/jobs/sensor_poll_job.rb
require "switch_bot_client"
require "sensors_broadcaster"
require "config_loader"

class SensorPollJob < ApplicationJob
  queue_as :default

  def perform
    config = load_config
    return Rails.logger.info("sensors: not configured") if config.switchbot.nil? || config.sensors.empty?

    client = SwitchBotClient.new(token: config.switchbot.token, secret: config.switchbot.secret)
    now    = Time.current

    config.sensors.each do |sensor|
      begin
        data = client.device_status(sensor.id)
        SensorReading.create!(
          device_id:        sensor.id,
          taken_at:         now,
          temperature:      data[:temperature],
          humidity:         data[:humidity],
          co2:              data[:co2],
          battery_pct:      data[:battery_pct],
          firmware_version: data[:firmware_version],
        )
      rescue SwitchBotClient::Error => e
        Rails.logger.warn("SensorPoll[#{sensor.id}]: #{e.message}")
      end
    end

    SensorsBroadcaster.refresh
  end

  private

  def load_config
    path = Rails.root.join("config", Rails.env.test? ? "ziwoas.test.yml" : "ziwoas.yml").to_s
    ConfigLoader.load(path)
  end
end
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bin/rails test test/jobs/sensor_poll_job_test.rb`
Expected: 4 runs, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/jobs/sensor_poll_job.rb test/jobs/sensor_poll_job_test.rb
git commit -m "Add SensorPollJob with per-sensor error isolation"
```

---

## Task 9: Recurring schedule

**Files:**
- Modify: `config/recurring.yml`

- [ ] **Step 1: Add the schedule entry**

In `config/recurring.yml`, inside the `aggregator_schedule: &aggregator_schedule` block, add:

```yaml
  poll_sensors:
    class: SensorPollJob
    queue: default
    schedule: every 15 minutes
```

- [ ] **Step 2: Verify the file parses as valid YAML**

Run: `bin/rails runner "puts YAML.load_file('config/recurring.yml').dig('production', 'poll_sensors', 'class')"`
Expected: `SensorPollJob`

- [ ] **Step 3: Commit**

```bash
git add config/recurring.yml
git commit -m "Schedule SensorPollJob every 15 minutes"
```

---

## Task 10: Routes + `SensorsController#index` + tests

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/sensors_controller.rb`
- Create: `test/controllers/sensors_controller_test.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/controllers/sensors_controller_test.rb
require "test_helper"

class SensorsControllerTest < ActionDispatch::IntegrationTest
  test "GET /sensors returns 200" do
    get "/sensors"
    assert_response :success
  end

  test "GET /sensors renders empty state when no readings exist" do
    SensorReading.delete_all
    get "/sensors"
    assert_response :success
    assert_match(/Noch keine Sensordaten/i, @response.body)
  end

  test "GET /sensors renders cards when readings exist" do
    SensorReading.create!(device_id: "TEST_INDOOR", taken_at: 1.minute.ago,
                          temperature: 21.4, humidity: 52, co2: 612, battery_pct: 85)
    get "/sensors"
    assert_match(/21,4/, @response.body)  # German formatting
    assert_match(/612/,   @response.body)
  end
end
```

- [ ] **Step 2: Add routes**

Modify `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  root "dashboard#index"

  get "/reports", to: "reports#index"
  get "/weather", to: "weather#index"
  get "/sensors", to: "sensors#index"
  get "/sensors/series", to: "sensors#series"

  get "/api/today", to: "api#today"
  get "/api/today/summary", to: "api#today_summary"
  get "/api/history", to: "api#history"
  get "/api/live", to: "api#live"

  get "up" => "rails/health#show", as: :rails_health_check
end
```

- [ ] **Step 3: Run test to verify failure**

Run: `bin/rails test test/controllers/sensors_controller_test.rb`
Expected: FAIL — `uninitialized constant SensorsController`

- [ ] **Step 4: Implement controller**

```ruby
# app/controllers/sensors_controller.rb
require "config_loader"

class SensorsController < ApplicationController
  def index
    config = ConfigLoader.load(config_path)
    @sensors = config.sensors
    @latest  = SensorReading.latest_per_device(@sensors.map(&:id)).index_by(&:device_id)
    @indoor  = @sensors.select { |s| s.type == :meter_pro_co2 }
    @outdoor = @sensors.select { |s| s.type == :outdoor_meter }
  end

  def series
    config = ConfigLoader.load(config_path)
    since  = 24.hours.ago
    rows = SensorReading.where(device_id: config.sensors.map(&:id)).since(since).order(:taken_at)
    grouped = rows.group_by(&:device_id)

    payload = {
      temperature: build_series(grouped, config.sensors, :temperature),
      humidity:    build_series(grouped, config.sensors, :humidity),
      co2:         build_series(grouped, config.sensors.select { |s| s.type == :meter_pro_co2 }, :co2),
    }
    render json: payload
  end

  private

  def config_path
    Rails.root.join("config", Rails.env.test? ? "ziwoas.test.yml" : "ziwoas.yml").to_s
  end

  def build_series(grouped, sensors, attr)
    sensors.map do |s|
      points = (grouped[s.id] || []).map { |r| [ r.taken_at.to_i * 1000, r.public_send(attr) ] }.reject { |_, v| v.nil? }
      { device_id: s.id, name: s.name, points: points }
    end
  end
end
```

- [ ] **Step 5: Run tests to verify pass**

Run: `bin/rails test test/controllers/sensors_controller_test.rb`
Expected: 3 runs, 0 failures (the third test asserts presence of values; the empty-state assert depends on the view from Task 12 — if it's not yet present this test will fail. **Defer Step 5 of Task 10 until after Task 12 finishes**, OR run only the first test now: `-n test_GET__sensors_returns_200`)

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/sensors_controller.rb test/controllers/sensors_controller_test.rb
git commit -m "Add SensorsController with index and series endpoints"
```

---

## Task 11: `SensorsHelper` – CO₂ ampel + tests

**Files:**
- Create: `app/helpers/sensors_helper.rb`
- Create: `test/helpers/sensors_helper_test.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/helpers/sensors_helper_test.rb
require "test_helper"

class SensorsHelperTest < ActionView::TestCase
  test "co2_level returns :good below 1000 ppm" do
    assert_equal :good, helper.co2_level(0)
    assert_equal :good, helper.co2_level(999)
  end

  test "co2_level returns :warn between 1000 and 1400" do
    assert_equal :warn, helper.co2_level(1000)
    assert_equal :warn, helper.co2_level(1400)
  end

  test "co2_level returns :bad above 1400" do
    assert_equal :bad, helper.co2_level(1401)
    assert_equal :bad, helper.co2_level(9999)
  end

  test "co2_level returns nil for nil input" do
    assert_nil helper.co2_level(nil)
  end

  test "co2_icon_path maps level to asset filename" do
    assert_equal "co2_good.png", helper.co2_icon_path(:good)
    assert_equal "co2_warn.png", helper.co2_icon_path(:warn)
    assert_equal "co2_bad.png",  helper.co2_icon_path(:bad)
  end

  test "battery_low? returns true below 20" do
    assert helper.battery_low?(19)
    refute helper.battery_low?(20)
    refute helper.battery_low?(nil)
  end
end
```

- [ ] **Step 2: Run test to verify failure**

Run: `bin/rails test test/helpers/sensors_helper_test.rb`
Expected: FAIL — `uninitialized constant SensorsHelper`

- [ ] **Step 3: Implement helper**

```ruby
# app/helpers/sensors_helper.rb
module SensorsHelper
  CO2_WARN_PPM = 1000
  CO2_BAD_PPM  = 1400
  BATTERY_LOW_PCT = 20

  def co2_level(ppm)
    return nil if ppm.nil?
    return :bad  if ppm > CO2_BAD_PPM
    return :warn if ppm >= CO2_WARN_PPM
    :good
  end

  def co2_icon_path(level)
    "co2_#{level}.png"
  end

  def battery_low?(pct)
    return false if pct.nil?
    pct < BATTERY_LOW_PCT
  end

  def relative_time(time)
    return "—" if time.nil?
    delta = (Time.current - time).to_i
    return "vor #{delta} s" if delta < 60
    return "vor #{delta / 60} Min" if delta < 3600
    "vor #{delta / 3600} h"
  end
end
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bin/rails test test/helpers/sensors_helper_test.rb`
Expected: 6 runs, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/helpers/sensors_helper.rb test/helpers/sensors_helper_test.rb
git commit -m "Add SensorsHelper with CO2 traffic-light thresholds"
```

---

## Task 12: Sensor views

**Files:**
- Create: `app/views/sensors/index.html.erb`
- Create: `app/views/sensors/_dashboard.html.erb`
- Create: `app/views/sensors/_battery_warning.html.erb`
- Create: `app/views/sensors/_indoor.html.erb`
- Create: `app/views/sensors/_outdoor.html.erb`
- Create: `app/views/sensors/_card.html.erb`
- Create: `app/views/sensors/_charts.html.erb`

- [ ] **Step 1: Create `index.html.erb`**

```erb
<%# app/views/sensors/index.html.erb %>
<% content_for :title, "Sensoren" %>
<%= turbo_stream_from "sensors" %>

<div class="sensors-page">
  <%= render "dashboard", sensors: @sensors, latest: @latest, indoor: @indoor, outdoor: @outdoor %>
</div>
```

- [ ] **Step 2: Create `_dashboard.html.erb`**

```erb
<%# app/views/sensors/_dashboard.html.erb %>
<%= turbo_frame_tag "sensors_dashboard" do %>
  <% if latest.empty? %>
    <section class="chart-card empty-state">
      <h2>Noch keine Sensordaten</h2>
      <p>Die Sensoransicht erscheint, sobald die SwitchBot-API Daten geliefert hat.</p>
    </section>
  <% else %>
    <%= render "battery_warning", sensors: sensors, latest: latest %>
    <%= render "indoor",  sensors: indoor,  latest: latest %>
    <%= render "outdoor", sensors: outdoor, latest: latest %>
    <%= render "charts" %>
  <% end %>
<% end %>
```

- [ ] **Step 3: Create `_battery_warning.html.erb`**

```erb
<%# app/views/sensors/_battery_warning.html.erb %>
<% low = sensors.filter_map { |s| latest[s.id] }.select { |r| battery_low?(r.battery_pct) } %>
<% if low.any? %>
  <% names = low.map { |r| sensors.find { |s| s.id == r.device_id }&.name }.compact.join(", ") %>
  <section class="sensor-warning">
    ⚠ Batterie schwach: <%= names %>
  </section>
<% end %>
```

- [ ] **Step 4: Create `_indoor.html.erb` and `_outdoor.html.erb`**

```erb
<%# app/views/sensors/_indoor.html.erb %>
<% if sensors.any? %>
  <div class="section-label">Innenräume</div>
  <section class="sensor-cards">
    <% sensors.each do |s| %>
      <%= render "card", sensor: s, reading: latest[s.id] %>
    <% end %>
  </section>
<% end %>
```

```erb
<%# app/views/sensors/_outdoor.html.erb %>
<% if sensors.any? %>
  <div class="section-label">Außen</div>
  <section class="sensor-cards">
    <% sensors.each do |s| %>
      <%= render "card", sensor: s, reading: latest[s.id] %>
    <% end %>
  </section>
<% end %>
```

- [ ] **Step 5: Create `_card.html.erb`**

```erb
<%# app/views/sensors/_card.html.erb %>
<article class="sensor-card chart-card">
  <header class="sensor-card-head">
    <h3 class="sensor-card-name"><%= sensor.name %></h3>
    <% if reading&.battery_pct %>
      <span class="sensor-card-battery <%= "is-low" if battery_low?(reading.battery_pct) %>">
        🔋 <%= reading.battery_pct %> %
      </span>
    <% end %>
  </header>

  <% if reading.nil? %>
    <p class="muted-text">Keine Daten</p>
  <% else %>
    <div class="sensor-card-body">
      <ul class="sensor-card-values">
        <% if reading.temperature %>
          <li><strong><%= number_with_precision(reading.temperature, precision: 1, delimiter: ".", separator: ",") %></strong> °C</li>
        <% end %>
        <% if reading.humidity %>
          <li><strong><%= reading.humidity %></strong> % rH</li>
        <% end %>
        <% if sensor.type == :meter_pro_co2 && reading.co2 %>
          <li><strong><%= reading.co2 %></strong> ppm</li>
        <% end %>
      </ul>

      <% if sensor.type == :meter_pro_co2 && reading.co2 %>
        <div class="sensor-card-ampel">
          <%= image_tag co2_icon_path(co2_level(reading.co2)),
                        class: "sensor-ampel-icon",
                        alt: "CO2-Ampel #{co2_level(reading.co2)}" %>
        </div>
      <% end %>
    </div>

    <footer class="sensor-card-foot muted-text">
      <%= relative_time(reading.taken_at) %>
    </footer>
  <% end %>
</article>
```

- [ ] **Step 6: Create `_charts.html.erb`**

```erb
<%# app/views/sensors/_charts.html.erb %>
<div class="section-label">Tagesverlauf</div>
<section class="sensor-charts"
         data-controller="sensors-chart"
         data-sensors-chart-url-value="<%= sensors_series_path %>">
  <article class="chart-card">
    <h3>Temperatur (24 h)</h3>
    <canvas data-sensors-chart-target="temperature"></canvas>
  </article>
  <article class="chart-card">
    <h3>Luftfeuchtigkeit (24 h)</h3>
    <canvas data-sensors-chart-target="humidity"></canvas>
  </article>
  <article class="chart-card">
    <h3>CO₂ (24 h)</h3>
    <canvas data-sensors-chart-target="co2"></canvas>
  </article>
</section>
```

Note: `sensors_series_path` requires a named route. Update `config/routes.rb` Task 10:

Replace `get "/sensors/series", to: "sensors#series"` with `get "/sensors/series", to: "sensors#series", as: :sensors_series`.

- [ ] **Step 7: Run controller tests to verify pass**

Run: `bin/rails test test/controllers/sensors_controller_test.rb`
Expected: 3 runs, 0 failures

- [ ] **Step 8: Commit**

```bash
git add app/views/sensors config/routes.rb
git commit -m "Add Sensoren tab views (cards + charts container)"
```

---

## Task 13: `#series` JSON endpoint test

**Files:**
- Modify: `test/controllers/sensors_controller_test.rb`

- [ ] **Step 1: Write failing test**

Append to `test/controllers/sensors_controller_test.rb` before final `end`:

```ruby
  test "GET /sensors/series returns JSON with three series" do
    SensorReading.delete_all
    SensorReading.create!(device_id: "TEST_INDOOR",  taken_at: 30.minutes.ago,
                          temperature: 21.0, humidity: 50, co2: 700, battery_pct: 90)
    SensorReading.create!(device_id: "TEST_OUTDOOR", taken_at: 30.minutes.ago,
                          temperature: 12.0, humidity: 70, battery_pct: 100)

    get "/sensors/series"
    assert_response :success
    body = JSON.parse(@response.body)
    assert body.key?("temperature")
    assert body.key?("humidity")
    assert body.key?("co2")

    indoor_temp = body["temperature"].find { |s| s["device_id"] == "TEST_INDOOR" }
    assert_equal 1, indoor_temp["points"].length
    assert_equal 21.0, indoor_temp["points"][0][1]

    co2_devices = body["co2"].map { |s| s["device_id"] }
    refute_includes co2_devices, "TEST_OUTDOOR"  # outdoor must not appear in CO2 chart
  end
```

- [ ] **Step 2: Run test to verify pass**

Run: `bin/rails test test/controllers/sensors_controller_test.rb -n test_GET__sensors_series_returns_JSON_with_three_series`
Expected: 1 run, 0 failures (the implementation from Task 10 already covers this)

- [ ] **Step 3: Commit**

```bash
git add test/controllers/sensors_controller_test.rb
git commit -m "Test sensors#series JSON endpoint"
```

---

## Task 14: Stimulus chart controller

**Files:**
- Create: `app/javascript/controllers/sensors_chart_controller.js`

- [ ] **Step 1: Create the controller**

```javascript
// app/javascript/controllers/sensors_chart_controller.js
import { Controller } from "@hotwired/stimulus"
import "chart.js"

// Connects to data-controller="sensors-chart"
// Builds three line charts (temperature, humidity, CO2) of the last 24h.
// Refreshes every 15 minutes; reloads on visibility change and bfcache restore.
export default class extends Controller {
  static targets = ["temperature", "humidity", "co2"]
  static values  = {
    url:             String,
    refreshInterval: { type: Number, default: 900_000 }, // 15 min
  }

  connect() {
    this.charts = {}
    this.load()
    this.refreshTimer = setInterval(() => this.load(), this.refreshIntervalValue)
    this._onVisibility = () => { if (document.visibilityState === "visible") this.load() }
    document.addEventListener("visibilitychange", this._onVisibility)
    this._onPageShow = (e) => { if (e.persisted) this.load() }
    window.addEventListener("pageshow", this._onPageShow)
  }

  disconnect() {
    clearInterval(this.refreshTimer)
    document.removeEventListener("visibilitychange", this._onVisibility)
    window.removeEventListener("pageshow", this._onPageShow)
    Object.values(this.charts).forEach(c => c?.destroy())
    this.charts = {}
  }

  async load() {
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!res.ok) return
      const data = await res.json()
      this._render("temperature", this.temperatureTarget, data.temperature, "°C")
      this._render("humidity",    this.humidityTarget,    data.humidity,    "%")
      this._renderCo2(this.co2Target, data.co2)
    } catch (e) {
      console.error("sensors-chart load failed:", e)
    }
  }

  _render(key, canvas, series, unit) {
    if (!canvas) return
    const datasets = series.map((s, i) => ({
      label: s.name,
      data:  s.points.map(([x, y]) => ({ x, y })),
      borderColor:     this._color(i),
      backgroundColor: this._color(i, 0.15),
      tension: 0.25,
      borderWidth: 2,
      pointRadius: 0,
    }))
    this.charts[key]?.destroy()
    this.charts[key] = new Chart(canvas, {
      type: "line",
      data: { datasets },
      options: this._opts(unit),
    })
  }

  _renderCo2(canvas, series) {
    if (!canvas) return
    const datasets = series.map((s, i) => ({
      label: s.name,
      data:  s.points.map(([x, y]) => ({ x, y })),
      borderColor:     this._color(i),
      backgroundColor: this._color(i, 0.15),
      tension: 0.25,
      borderWidth: 2,
      pointRadius: 0,
    }))
    // Pettenkofer threshold lines as additional non-interactive datasets
    datasets.push(this._thresholdLine(series, 1000, "#fbbf24")) // warn
    datasets.push(this._thresholdLine(series, 1400, "#ef4444")) // bad
    this.charts.co2?.destroy()
    this.charts.co2 = new Chart(canvas, {
      type: "line",
      data: { datasets },
      options: this._opts("ppm"),
    })
  }

  _thresholdLine(series, value, color) {
    const xs = series.flatMap(s => s.points.map(p => p[0]))
    if (xs.length === 0) return { data: [] }
    const xmin = Math.min(...xs), xmax = Math.max(...xs)
    return {
      label: `${value} ppm`,
      data:  [ { x: xmin, y: value }, { x: xmax, y: value } ],
      borderColor:   color,
      borderDash:    [ 4, 4 ],
      borderWidth:   1,
      pointRadius:   0,
      fill: false,
      tension: 0,
    }
  }

  _opts(unit) {
    return {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      scales: {
        x: { type: "time", time: { unit: "hour" } },
        y: { title: { display: true, text: unit } },
      },
      plugins: { legend: { position: "bottom" } },
    }
  }

  _color(i, alpha = 1) {
    const palette = [
      `rgba(37, 99, 235, ${alpha})`,   // blue
      `rgba(16, 185, 129, ${alpha})`,  // green
      `rgba(217, 70, 239, ${alpha})`,  // magenta
    ]
    return palette[i % palette.length]
  }
}
```

- [ ] **Step 2: Verify Chart.js time scale**

Open `vendor/javascript/chart.min.js` (or wherever the vendored bundle lives) and check that `Chart.js` includes the time scale (it does in the standard UMD bundle from chartjs.org). If not, the `x: { type: "time" }` will silently fail to render labels — the chart will still draw.

Run: `grep -l "_adapters.date\|TimeScale" vendor/javascript/chart.min.js public/javascripts/chart.min.js 2>/dev/null`
Expected: at least one match. If empty, the time scale isn't bundled — fall back to `type: "linear"` and pre-format labels in JS. (Note this in the implementation if needed.)

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/sensors_chart_controller.js
git commit -m "Add sensors-chart Stimulus controller (Chart.js)"
```

---

## Task 15: Sensors CSS

**Files:**
- Create: `app/assets/stylesheets/sensors.css`

- [ ] **Step 1: Create the stylesheet**

```css
/* app/assets/stylesheets/sensors.css */

.sensors-page { display: flex; flex-direction: column; gap: 1.5rem; }

.sensor-warning {
  background: #fef3c7;
  border: 1px solid #fcd34d;
  color: #78350f;
  padding: .75rem 1rem;
  border-radius: .5rem;
  font-weight: 600;
}

.sensor-cards {
  display: grid;
  gap: 1rem;
  grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
}

.sensor-card {
  display: flex;
  flex-direction: column;
  padding: 1rem;
}

.sensor-card-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: .5rem;
}

.sensor-card-name { margin: 0; font-size: 1rem; }

.sensor-card-battery { font-size: .85rem; color: #6b7280; }
.sensor-card-battery.is-low { color: #b91c1c; font-weight: 600; }

.sensor-card-body {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.sensor-card-values {
  list-style: none;
  margin: 0;
  padding: 0;
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: .25rem;
  font-size: 1.25rem;
}

.sensor-card-values strong { font-size: 1.5rem; }

.sensor-card-ampel {
  flex: 0 0 auto;
}

.sensor-ampel-icon {
  height: 72px;
  width: auto;
  object-fit: contain;
  display: block;
}

.sensor-card-foot { margin-top: .5rem; font-size: .85rem; }

.sensor-charts {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.sensor-charts .chart-card {
  padding: 1rem;
  height: 280px;
  display: flex;
  flex-direction: column;
}

.sensor-charts .chart-card h3 { margin: 0 0 .5rem; font-size: 1rem; }
.sensor-charts canvas { flex: 1; min-height: 0; }
```

- [ ] **Step 2: Verify Propshaft picks it up**

Propshaft is configured to include all `app/assets/stylesheets/*.css`. Confirm `application.css` either uses `@import` or that the layout already loads all stylesheets.

Run: `grep -E "stylesheet_link_tag|require" app/assets/stylesheets/application.css app/views/layouts/application.html.erb`
Expected: see how existing CSS files (e.g. weather styles) are wired in. If `application.css` uses `@import "weather"`, add `@import "sensors";`. If the layout uses `stylesheet_link_tag :application`, it auto-includes app/assets/stylesheets/*.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/sensors.css app/assets/stylesheets/application.css
git commit -m "Add sensors.css with card and chart styling"
```

(Only include `application.css` if it was actually edited.)

---

## Task 16: Navigation link

**Files:**
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Add the nav link**

Replace the `<nav>` block in `app/views/layouts/application.html.erb`:

```erb
      <nav class="app-nav" aria-label="Hauptnavigation">
        <%= link_to "Dashboard", root_path, class: [ "app-nav-link", ("active" if current_page?(root_path)) ] %>
        <%= link_to "Berichte",  reports_path,  class: [ "app-nav-link", ("active" if current_page?(reports_path)) ] %>
        <%= link_to "Wetter",    weather_path,  class: [ "app-nav-link", ("active" if current_page?(weather_path)) ] %>
        <%= link_to "Sensoren",  sensors_path,  class: [ "app-nav-link", ("active" if current_page?(sensors_path)) ] %>
      </nav>
```

Note: `sensors_path` requires the route to be named. Update Task 10 routes:

```ruby
get "/sensors", to: "sensors#index", as: :sensors
get "/sensors/series", to: "sensors#series", as: :sensors_series
```

- [ ] **Step 2: Smoke-test the layout**

Run: `bin/rails test test/controllers/sensors_controller_test.rb`
Expected: still passing (no regressions)

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb config/routes.rb
git commit -m "Add Sensoren nav link"
```

---

## Task 17: Wetter-Tab integration – use sensor temp when fresh

**Files:**
- Modify: `app/controllers/weather_controller.rb`
- Modify: `app/views/weather/_current.html.erb`
- Modify: `test/controllers/weather_controller_test.rb` (create if missing)

- [ ] **Step 1: Write failing test**

Check whether `test/controllers/weather_controller_test.rb` exists; if not, create:

```ruby
# test/controllers/weather_controller_test.rb
require "test_helper"

class WeatherControllerTest < ActionDispatch::IntegrationTest
  test "GET /weather returns 200" do
    get "/weather"
    assert_response :success
  end

  test "uses outdoor sensor temperature when reading is fresh" do
    SensorReading.delete_all
    SensorReading.create!(device_id: "TEST_OUTDOOR", taken_at: 5.minutes.ago,
                          temperature: 7.7, humidity: 80, battery_pct: 100)
    WeatherRecord.delete_all
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405,
                          timestamp: Time.current, temperature: 99.9, daytime: "day")

    get "/weather"
    assert_match("7,7", @response.body)
    refute_match("99,9", @response.body)
  end

  test "falls back to brightsky temperature when sensor reading is stale" do
    SensorReading.delete_all
    SensorReading.create!(device_id: "TEST_OUTDOOR", taken_at: 2.hours.ago,
                          temperature: 7.7, humidity: 80, battery_pct: 100)
    WeatherRecord.delete_all
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405,
                          timestamp: Time.current, temperature: 99.9, daytime: "day")

    get "/weather"
    assert_match("99,9", @response.body)
    refute_match("7,7",  @response.body)
  end
end
```

- [ ] **Step 2: Run test to verify failure**

Run: `bin/rails test test/controllers/weather_controller_test.rb`
Expected: tests 2 and 3 fail (current_weather is rendered with Brightsky temp regardless)

- [ ] **Step 3: Modify controller**

```ruby
# app/controllers/weather_controller.rb
require "config_loader"

class WeatherController < ApplicationController
  SENSOR_FRESHNESS = 30.minutes

  def index
    @current_weather = WeatherRecord.latest_current
    @today_weather = WeatherRecord.today_hourly
    @future_weather = WeatherRecord.future_days
    @outdoor_sensor_reading = fresh_outdoor_sensor_reading
  end

  private

  def fresh_outdoor_sensor_reading
    config = ConfigLoader.load(config_path)
    outdoor_ids = config.sensors.select { |s| s.type == :outdoor_meter }.map(&:id)
    return nil if outdoor_ids.empty?
    SensorReading
      .where(device_id: outdoor_ids)
      .where("taken_at >= ?", SENSOR_FRESHNESS.ago)
      .order(taken_at: :desc)
      .first
  rescue Errno::ENOENT
    nil
  end

  def config_path
    Rails.root.join("config", Rails.env.test? ? "ziwoas.test.yml" : "ziwoas.yml").to_s
  end
end
```

- [ ] **Step 4: Modify `_current.html.erb`**

Adjust the temperature line and add a small source label. Replace the `weather-current-temp` div in `_current.html.erb`:

```erb
          <% if local_assigns[:outdoor_sensor_reading] || @outdoor_sensor_reading %>
            <% sensor = local_assigns[:outdoor_sensor_reading] || @outdoor_sensor_reading %>
            <div class="weather-current-temp"><%= number_with_precision(sensor.temperature, precision: 1, delimiter: ".", separator: ",") %> °C</div>
            <div class="muted-text"><%= current_weather.condition || "Wetter" %> · Wind <%= number_with_precision(current_weather.wind_speed || 0, precision: 0, delimiter: ".", separator: ",") %> km/h · <span class="weather-source">eigener Sensor</span></div>
          <% else %>
            <div class="weather-current-temp"><%= number_with_precision(current_weather.temperature, precision: 1, delimiter: ".", separator: ",") %> °C</div>
            <div class="muted-text"><%= current_weather.condition || "Wetter" %> · Wind <%= number_with_precision(current_weather.wind_speed || 0, precision: 0, delimiter: ".", separator: ",") %> km/h · <span class="weather-source">DWD</span></div>
          <% end %>
```

Also pass the sensor reading through `app/views/weather/index.html.erb` if needed — check that the existing `render "current"` call doesn't restrict locals; if it does, change to:

```erb
<%= render "current", current_weather: @current_weather, outdoor_sensor_reading: @outdoor_sensor_reading %>
```

(Look at the current `index.html.erb` for the exact call signature first.)

- [ ] **Step 5: Update broadcaster to pass the sensor reading**

`WeatherBroadcaster.broadcast_current` currently passes `locals: { current_weather: WeatherRecord.latest_current }`. Update it to also include the fresh sensor reading so live-updates from `WeatherCurrentJob` show the right value.

Modify `lib/weather_broadcaster.rb` `broadcast_current` to:

```ruby
  def broadcast_current
    Turbo::StreamsChannel.broadcast_replace_to(
      STREAM,
      target: "weather_current",
      partial: "weather/current",
      locals: {
        current_weather: WeatherRecord.latest_current,
        outdoor_sensor_reading: latest_fresh_outdoor_reading
      }
    )
    broadcast_empty_state
  end

  def latest_fresh_outdoor_reading
    config = load_config
    return nil if config.nil?
    outdoor_ids = config.sensors.select { |s| s.type == :outdoor_meter }.map(&:id)
    return nil if outdoor_ids.empty?
    SensorReading
      .where(device_id: outdoor_ids)
      .where("taken_at >= ?", 30.minutes.ago)
      .order(taken_at: :desc)
      .first
  end

  def load_config
    require "config_loader"
    path = Rails.root.join("config", Rails.env.test? ? "ziwoas.test.yml" : "ziwoas.yml").to_s
    ConfigLoader.load(path)
  rescue Errno::ENOENT
    nil
  end
```

Also: when a new `SensorPollJob` finishes, the weather card should update too. Modify `SensorsBroadcaster.refresh` (Task 7) to additionally call `WeatherBroadcaster.broadcast_current` so the weather tab picks up the new outdoor temp:

```ruby
# lib/sensors_broadcaster.rb (extend)
require "weather_broadcaster"

module SensorsBroadcaster
  # ...

  def refresh
    # existing body ...
    WeatherBroadcaster.broadcast_current
  end
end
```

- [ ] **Step 6: Run tests to verify pass**

Run: `bin/rails test test/controllers/weather_controller_test.rb test/test_weather_broadcaster.rb`
Expected: all tests pass. If `test/test_weather_broadcaster.rb` breaks because broadcast now hits `WeatherRecord` and `SensorReading` — adjust stubs accordingly.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/weather_controller.rb app/views/weather/_current.html.erb lib/weather_broadcaster.rb lib/sensors_broadcaster.rb test/controllers/weather_controller_test.rb test/test_weather_broadcaster.rb
git commit -m "Use outdoor sensor temperature in weather tab when fresh"
```

---

## Task 18: Rake task `switchbot:list_devices`

**Files:**
- Create: `lib/tasks/switchbot.rake`
- Create: `test/tasks/switchbot_rake_test.rb` *(optional — can be skipped if rake-task tests aren't established in the repo)*

- [ ] **Step 1: Create the rake task**

```ruby
# lib/tasks/switchbot.rake
require "switch_bot_client"
require "config_loader"

namespace :switchbot do
  desc "List all SwitchBot devices and emit a config snippet for ziwoas.yml"
  task list_devices: :environment do
    path   = Rails.root.join("config", "ziwoas.yml").to_s
    config = ConfigLoader.load(path)

    if config.switchbot.nil?
      abort "switchbot: token/secret missing in config/ziwoas.yml. Add a 'switchbot:' block first."
    end

    client = SwitchBotClient.new(token: config.switchbot.token, secret: config.switchbot.secret)
    all     = client.list_all_devices
    sensors = client.list_sensor_devices

    puts ""
    puts "Gefundene Geräte:"
    puts "─" * 60
    all.each do |d|
      tag = sensors.any? { |s| s[:id] == d[:id] } ? "" : "(kein Sensor)"
      puts "  #{d[:id].ljust(16)}  #{d[:name].to_s.ljust(20)}  #{d[:device_type].ljust(20)} #{tag}"
    end
    puts "─" * 60

    if sensors.empty?
      puts ""
      puts "Keine Meter Pro CO2 oder Outdoor Meter gefunden."
      next
    end

    puts ""
    puts "Konfigurations-Vorschlag für config/ziwoas.yml:"
    puts ""
    puts "sensors:"
    sensors.each do |s|
      puts "  - id: \"#{s[:id]}\""
      puts "    name: \"#{s[:name]}\""
      puts "    type: #{s[:type]}"
      puts "    room: \"#{s[:name]}\"     # ggf. anpassen" if s[:type] == :meter_pro_co2
      puts ""
    end
  end
end
```

- [ ] **Step 2: Smoke-test the task definition is loaded**

Run: `bin/rails -T switchbot`
Expected: shows `rails switchbot:list_devices  # List all SwitchBot devices ...`

- [ ] **Step 3: Commit**

```bash
git add lib/tasks/switchbot.rake
git commit -m "Add switchbot:list_devices rake task with YAML output"
```

---

## Task 19: Update example & test config files

**Files:**
- Modify: `config/ziwoas.example.yml`
- Modify: `config/ziwoas.test.yml` (if not yet updated in Task 7)

- [ ] **Step 1: Append example block to `ziwoas.example.yml`**

```yaml
# Append to config/ziwoas.example.yml:

# SwitchBot integration. Token and secret come from the SwitchBot app:
# Profil → Einstellungen → 10× auf "App-Version" tippen → Entwickleroptionen.
# switchbot:
#   token: "..."
#   secret: "..."
#
# sensors:
#   - id: "ABCDEF123456"          # 'bin/rails switchbot:list_devices' shows IDs
#     name: "Wohnzimmer"
#     type: meter_pro_co2          # meter_pro_co2 | outdoor_meter
#     room: "Wohnzimmer"           # optional, gruppiert in V2-Berichten
#
#   - id: "112233445566"
#     name: "Balkon"
#     type: outdoor_meter
```

- [ ] **Step 2: Verify `ziwoas.test.yml` has a sensors block**

Check `config/ziwoas.test.yml`. If Task 7 already appended the test block (`switchbot:` + `sensors:` with `TEST_INDOOR` / `TEST_OUTDOOR`), no change needed. Otherwise append the test block from Task 7 Step 4 note.

- [ ] **Step 3: Run full test suite**

Run: `bin/rails test`
Expected: all tests pass. Investigate any regressions.

- [ ] **Step 4: Commit**

```bash
git add config/ziwoas.example.yml config/ziwoas.test.yml
git commit -m "Document SwitchBot config block in example yml"
```

---

## Task 20: Manual smoke test

**Files:** none — pure verification

- [ ] **Step 1: Start the dev stack**

```bash
bin/dev
```

- [ ] **Step 2: Visit /sensors in a browser**

Open `http://localhost:3000/sensors`.

Expected behaviors before any data:
- Empty state: "Noch keine Sensordaten" card
- Nav link "Sensoren" highlighted

- [ ] **Step 3: Trigger a manual poll**

Run: `bin/rails runner "SensorPollJob.perform_now"`

Expected:
- 3 new rows in `sensor_readings` (assuming 3 sensors configured & online)
- Sensor cards now visible in the browser (Turbo updated automatically)
- Three line charts render with one data point each
- CO₂ ampel icon visible on each indoor card

- [ ] **Step 4: Visit /weather**

Open `http://localhost:3000/weather`. Expected: "aktuell" tile shows the sensor outdoor temperature with label "eigener Sensor".

- [ ] **Step 5: Wait 15 minutes, observe automatic update**

Or trigger the job again and confirm cards & charts update without a page reload (Turbo Stream).

- [ ] **Step 6: Run rake task end-to-end**

Run: `bin/rails switchbot:list_devices`

Expected: prints the device list and the YAML config snippet.

(No commit for this task — it's verification only.)

---

## Self-review notes (recorded after the plan was written)

- **Spec coverage:** Every section of the spec maps to at least one task.
  Architecture → Tasks 1–8. Datenmodell → Task 1–2. Konfiguration → Tasks 3–4, 19.
  SwitchBotClient → Tasks 5–6. SensorPollJob → Task 8. Scheduling → Task 9.
  Rake-Task → Task 18. UI Sensoren-Tab → Tasks 10–15. Wetter-Tab Anpassung →
  Task 17. Header-Nav → Task 16. CO₂-Ampel-Schwellen → Task 11. Battery-Anzeige
  → Tasks 11 + 12.
- **Placeholders:** none — all code blocks contain final code.
- **Type consistency:** `co2` (lowercase) is used in DB, model, JSON, controller,
  and view consistently. `battery_pct` is used everywhere. Sensor `type` is
  always `:meter_pro_co2` / `:outdoor_meter` (symbols).
- **Cross-task contract:** `SwitchBotClient#device_status` returns
  `{ temperature:, humidity:, co2:, battery_pct:, firmware_version:, raw: }` —
  `SensorPollJob` reads exactly these keys.
