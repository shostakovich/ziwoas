# Solakon Live Energy Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Home-Assistant-style live energy overview that uses Solakon Modbus readings for live PV, battery, and calculated grid values.

**Architecture:** Add a dedicated `solakon_readings` table/model, split Solakon monitoring from optional zero-export writing, expose a calculated `energy_flow` object through `/api/live`, then update the existing dashboard SVG/Stimulus logic in place. Solakon reads are persisted first; writes only happen from the control path when `control_enabled: true`.

**Tech Stack:** Rails, ActiveRecord, ActiveJob, Minitest, Stimulus, SVG/CSS animations, existing `SolakonClient`.

---

## File Structure

- Create `db/migrate/*_create_solakon_readings.rb`: schema for persisted Solakon live readings.
- Create `app/models/solakon_reading.rb`: validations, freshness lookup, and display sign conversion.
- Modify `lib/config_loader.rb`: replace `enabled`-centric Solakon config with `monitoring_enabled` and `control_enabled`, retaining old `enabled` as read-only monitoring fallback.
- Modify `config/ziwoas.example.yml`: document the new Solakon config keys.
- Modify `config/recurring.yml`: schedule `SolakonMonitorJob` instead of running the zero-export writer as the leading recurring job.
- Create `app/jobs/solakon_monitor_job.rb`: read once, persist, broadcast/prepare live state, optionally trigger control.
- Modify `app/jobs/zero_export_tick_job.rb`: allow control from a pre-read Solakon state/reading and gate writes on `control_enabled`.
- Modify `app/controllers/api_controller.rb`: return `energy_flow` from latest fresh Solakon reading plus current consumer samples.
- Modify `app/views/dashboard/index.html.erb`: replace the three-node SVG with four nodes and six paths while keeping the section location.
- Modify `app/javascript/controllers/dashboard_controller.js`: consume `energy_flow`, render live W values, and animate the six paths.
- Add `app/assets/images/icon_batterie.webp`: generated plush-style battery logo.
- Add/modify tests in `test/models`, `test/jobs`, `test/controllers`, and `test/controllers/dashboard_controller_test.rb`.

## Task 1: Solakon Reading Model And Migration

**Files:**
- Create: `db/migrate/*_create_solakon_readings.rb`
- Create: `app/models/solakon_reading.rb`
- Test: `test/models/solakon_reading_test.rb`

- [ ] **Step 1: Generate the model migration**

Run:

```bash
rtk bin/rails generate model SolakonReading taken_at:datetime active_power_w:float pv_power_w:float battery_power_w:float battery_soc_pct:integer
```

Expected: a migration, model, and fixture file are created.

- [ ] **Step 2: Edit the migration**

Set the migration body to:

```ruby
class CreateSolakonReadings < ActiveRecord::Migration[8.0]
  def change
    create_table :solakon_readings do |t|
      t.datetime :taken_at, null: false
      t.float :active_power_w, null: false
      t.float :pv_power_w, null: false
      t.float :battery_power_w, null: false
      t.integer :battery_soc_pct, null: false

      t.timestamps
    end

    add_index :solakon_readings, :taken_at
  end
end
```

- [ ] **Step 3: Write the failing model test**

Create `test/models/solakon_reading_test.rb`:

```ruby
require "test_helper"

class SolakonReadingTest < ActiveSupport::TestCase
  test "validates required fields" do
    reading = SolakonReading.new

    assert_not reading.valid?
    assert_includes reading.errors[:taken_at], "can't be blank"
    assert_includes reading.errors[:active_power_w], "can't be blank"
    assert_includes reading.errors[:pv_power_w], "can't be blank"
    assert_includes reading.errors[:battery_power_w], "can't be blank"
    assert_includes reading.errors[:battery_soc_pct], "can't be blank"
  end

  test "latest_fresh returns newest reading inside stale threshold" do
    old = SolakonReading.create!(
      taken_at: 5.minutes.ago,
      active_power_w: 100,
      pv_power_w: 120,
      battery_power_w: 0,
      battery_soc_pct: 80
    )
    fresh = SolakonReading.create!(
      taken_at: 10.seconds.ago,
      active_power_w: 220,
      pv_power_w: 260,
      battery_power_w: -40,
      battery_soc_pct: 81
    )

    assert_equal fresh, SolakonReading.latest_fresh(stale_after_s: 120, now: Time.current)
    travel 3.minutes do
      assert_nil SolakonReading.latest_fresh(stale_after_s: 120, now: Time.current)
    end
  end

  test "battery_display_power_w is positive while charging and negative while discharging" do
    charging = SolakonReading.new(battery_power_w: -50)
    discharging = SolakonReading.new(battery_power_w: 50)

    assert_equal 50, charging.battery_display_power_w
    assert_equal(-50, discharging.battery_display_power_w)
  end
end
```

- [ ] **Step 4: Run the model test and verify it fails**

Run:

```bash
rtk bin/rails test test/models/solakon_reading_test.rb
```

Expected: FAIL because validations and methods are missing.

- [ ] **Step 5: Implement the model**

Set `app/models/solakon_reading.rb` to:

```ruby
class SolakonReading < ApplicationRecord
  validates :taken_at, :active_power_w, :pv_power_w, :battery_power_w, :battery_soc_pct, presence: true
  validates :battery_soc_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :newest_first, -> { order(taken_at: :desc) }

  def self.latest_fresh(stale_after_s:, now: Time.current)
    newest_first.where("taken_at >= ?", now - stale_after_s.to_i.seconds).first
  end

  def battery_display_power_w
    -battery_power_w.to_f
  end
end
```

- [ ] **Step 6: Run migration and model test**

Run:

```bash
rtk bin/rails db:migrate
rtk bin/rails test test/models/solakon_reading_test.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
rtk git add db/migrate app/models/solakon_reading.rb test/models/solakon_reading_test.rb db/schema.rb
rtk git commit -m "feat: persist Solakon readings"
```

## Task 2: Solakon Config Flags

**Files:**
- Modify: `lib/config_loader.rb`
- Modify: `config/ziwoas.example.yml`
- Test: `test/config_loader_test.rb`

- [ ] **Step 1: Write failing config tests**

Append these tests near the existing Solakon tests in `test/config_loader_test.rb`:

```ruby
def test_solakon_parses_monitoring_and_control_flags
  yaml = valid_yaml + <<~YAML
    solakon:
      host: 192.168.1.50
      monitoring_enabled: true
      control_enabled: false
  YAML

  sol = load_yaml(yaml).solakon

  assert_equal true, sol.monitoring_enabled
  assert_equal false, sol.control_enabled
end

def test_solakon_old_enabled_is_read_only_monitoring_fallback
  yaml = valid_yaml + <<~YAML
    solakon:
      host: 192.168.1.50
      enabled: true
  YAML

  sol = load_yaml(yaml).solakon

  assert_equal true, sol.monitoring_enabled
  assert_equal false, sol.control_enabled
end

def test_solakon_new_flags_take_priority_over_old_enabled
  yaml = valid_yaml + <<~YAML
    solakon:
      host: 192.168.1.50
      enabled: true
      monitoring_enabled: false
      control_enabled: false
  YAML

  sol = load_yaml(yaml).solakon

  assert_equal false, sol.monitoring_enabled
  assert_equal false, sol.control_enabled
end
```

Update existing Solakon assertions to expect `monitoring_enabled` and `control_enabled` instead of `enabled`.

- [ ] **Step 2: Run config tests and verify failure**

Run:

```bash
rtk bin/rails test test/config_loader_test.rb
```

Expected: FAIL because `SolakonCfg` does not expose the new fields.

- [ ] **Step 3: Update `ConfigLoader::SolakonCfg`**

Change:

```ruby
SolakonCfg   = Struct.new(:host, :port, :unit_id, :enabled, :stale_after_s, keyword_init: true)
```

to:

```ruby
SolakonCfg   = Struct.new(:host, :port, :unit_id, :monitoring_enabled, :control_enabled,
                          :stale_after_s, keyword_init: true)
```

- [ ] **Step 4: Add boolean parsing helper**

Add this private helper near the other requirement helpers:

```ruby
def require_boolean(v, key)
  return v if [ true, false ].include?(v)

  raise Error, "#{key} must be true or false"
end
```

- [ ] **Step 5: Update `build_solakon`**

Replace the existing `SolakonCfg.new` block with:

```ruby
monitoring_enabled =
  if h.key?("monitoring_enabled")
    require_boolean(h["monitoring_enabled"], "solakon.monitoring_enabled")
  elsif h.key?("enabled")
    !!h["enabled"]
  else
    true
  end

control_enabled =
  if h.key?("control_enabled")
    require_boolean(h["control_enabled"], "solakon.control_enabled")
  else
    false
  end

SolakonCfg.new(
  host:               require_string(h["host"], "solakon.host"),
  port:               (h["port"] || 502).to_i,
  unit_id:            (h["unit_id"] || 1).to_i,
  monitoring_enabled: monitoring_enabled,
  control_enabled:    control_enabled,
  stale_after_s:      (h["stale_after_s"] || 120).to_i,
)
```

- [ ] **Step 6: Update example config**

In `config/ziwoas.example.yml`, make the Solakon block show:

```yml
# solakon:
#   host: 192.168.1.50
#   port: 502
#   unit_id: 1
#   stale_after_s: 120
#   monitoring_enabled: true
#   control_enabled: false
```

- [ ] **Step 7: Run tests**

Run:

```bash
rtk bin/rails test test/config_loader_test.rb
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
rtk git add lib/config_loader.rb config/ziwoas.example.yml test/config_loader_test.rb
rtk git commit -m "feat: split Solakon monitoring and control config"
```

## Task 3: Control Path From Pre-Read State

**Files:**
- Modify: `app/jobs/zero_export_tick_job.rb`
- Test: `test/jobs/zero_export_tick_job_test.rb`

- [ ] **Step 1: Update fake config/test helpers**

In `test/jobs/zero_export_tick_job_test.rb`, replace the `Sol` struct and `config` helper with:

```ruby
Sol = Struct.new(:host, :port, :unit_id, :monitoring_enabled, :control_enabled, :stale_after_s, keyword_init: true)
Cfg = Struct.new(:plugs, :solakon, keyword_init: true)

def config(monitoring_enabled: true, control_enabled: true, solakon: true)
  sol = solakon ? Sol.new(
    host: "h",
    port: 502,
    unit_id: 1,
    monitoring_enabled: monitoring_enabled,
    control_enabled: control_enabled,
    stale_after_s: 120
  ) : nil
  Cfg.new(plugs: [ Plug.new(id: "fridge", role: :consumer, name: "Kühlschrank") ], solakon: sol)
end
```

- [ ] **Step 2: Write failing tests for pre-read control**

Add:

```ruby
test "applies control from a pre-read state without calling control_tick" do
  now = Time.at(1_000_000)
  Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 250, aenergy_wh: 1)
  client = FakeClient.new(state: healthy_state)

  run_job(client: client, now: now, state: healthy_state)

  assert_equal [ [ :apply_power, 250, 10 ] ], client.calls
end

test "no-op when control is disabled" do
  client = FakeClient.new
  run_job(client: client, cfg: config(control_enabled: false))
  assert_empty client.calls
end
```

Update `run_job` to accept `state: nil`:

```ruby
def run_job(client:, now: Time.at(1_000_000), cfg: config, state: nil)
  Rails.stub(:cache, @cache) do
    ConfigLoader.stub(:app_config, cfg) do
      ZeroExportTickJob.new.perform(client: client, reader_now: now, state: state)
    end
  end
end
```

Update `FakeClient` with:

```ruby
def apply_control!(power_w:, min_soc:)
  @calls << [ :apply_power, power_w, min_soc ]
end
```

- [ ] **Step 3: Run job tests and verify failure**

Run:

```bash
rtk bin/rails test test/jobs/zero_export_tick_job_test.rb
```

Expected: FAIL because `perform` does not accept `state:` and the client does not have an apply-only path in production code.

- [ ] **Step 4: Add write-only helper to `SolakonClient`**

In `lib/solakon_client.rb`, add:

```ruby
def apply_control!(power_w:, min_soc:)
  with_connection do |c|
    current_min_soc = read_u16(c, REG_MINIMUM_SOC)
    write_u16(c, REG_REMOTE_CONTROL, 1)
    write_u16(c, REG_REMOTE_TIMEOUT, 60)
    write_u16(c, REG_MINIMUM_SOC, min_soc) unless current_min_soc == min_soc
    write_i32(c, REG_REMOTE_ACTIVE_POWER, power_w.to_i)
  end
rescue StandardError => e
  raise Error, e.message
end
```

Also add a client test in `test/solakon_client_test.rb` that mirrors the existing `control_tick!` write assertions but calls `apply_control!(power_w: -75, min_soc: 10)`.

- [ ] **Step 5: Refactor `ZeroExportTickJob#perform`**

Change the signature to:

```ruby
def perform(client: nil, reader_now: Time.now, state: nil)
```

Replace the old enabled guard with:

```ruby
return Rails.logger.info("zero_export: not configured") if solakon.nil?
return Rails.logger.info("zero_export: control disabled") unless solakon.control_enabled
```

Keep the consumption/floor/recovery/target calculation. Replace the `control_tick!` block with:

```ruby
client ||= SolakonClient.new(host: solakon.host, port: solakon.port, unit_id: solakon.unit_id)

begin
  state ||= client.read_state
  recovery = recovery_mode?(state.battery_soc)
  target = ZeroExportController.target_output_w(
    consumption_w: consumption,
    floor_w: floor,
    pv_power_w: state.pv_power_w,
    recovery: recovery
  )
  client.apply_control!(power_w: target, min_soc: ZeroExportController::MIN_SOC_PCT)
  reset_failures
  consumption_str = consumption.nil? ? "stale" : "#{consumption.round}W"
  Rails.logger.info(
    "zero_export: consumption=#{consumption_str} floor=#{floor.round}W target=#{target}W " \
    "recovery=#{recovery} soc=#{state.battery_soc}% active=#{state.active_power_w}W " \
    "pv=#{state.pv_power_w}W battery=#{state.battery_power_w}W"
  )
rescue SolakonClient::Error => e
  handle_failure(client, e)
end
```

- [ ] **Step 6: Run Solakon and job tests**

Run:

```bash
rtk bin/rails test test/solakon_client_test.rb test/jobs/zero_export_tick_job_test.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
rtk git add lib/solakon_client.rb app/jobs/zero_export_tick_job.rb test/solakon_client_test.rb test/jobs/zero_export_tick_job_test.rb
rtk git commit -m "feat: allow zero export from pre-read Solakon state"
```

## Task 4: Solakon Monitor Job

**Files:**
- Create: `app/jobs/solakon_monitor_job.rb`
- Modify: `config/recurring.yml`
- Test: `test/jobs/solakon_monitor_job_test.rb`

- [ ] **Step 1: Write failing monitor job tests**

Create `test/jobs/solakon_monitor_job_test.rb`:

```ruby
require "test_helper"

class SolakonMonitorJobTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls

    def initialize(state: nil, fail: false)
      @state = state
      @fail = fail
      @calls = []
    end

    def read_state
      @calls << :read_state
      raise SolakonClient::Error, "down" if @fail
      @state
    end
  end

  Plug = Struct.new(:id, :role, :name, keyword_init: true)
  Sol = Struct.new(:host, :port, :unit_id, :monitoring_enabled, :control_enabled, :stale_after_s, keyword_init: true)
  Cfg = Struct.new(:plugs, :solakon, keyword_init: true)

  def config(monitoring_enabled: true, control_enabled: false)
    Cfg.new(
      plugs: [ Plug.new(id: "fridge", role: :consumer, name: "Kühlschrank") ],
      solakon: Sol.new(
        host: "h",
        port: 502,
        unit_id: 1,
        monitoring_enabled: monitoring_enabled,
        control_enabled: control_enabled,
        stale_after_s: 120
      )
    )
  end

  def state
    SolakonClient::State.new(battery_soc: 84, active_power_w: 300, pv_power_w: 360, battery_power_w: -50)
  end

  test "persists a reading when monitoring is enabled" do
    client = FakeClient.new(state: state)

    ConfigLoader.stub(:app_config, config) do
      assert_difference -> { SolakonReading.count }, 1 do
        SolakonMonitorJob.new.perform(client: client, now: Time.zone.local(2026, 6, 18, 12, 0, 0))
      end
    end

    reading = SolakonReading.last
    assert_equal 300, reading.active_power_w
    assert_equal 360, reading.pv_power_w
    assert_equal(-50, reading.battery_power_w)
    assert_equal 84, reading.battery_soc_pct
    assert_equal [ :read_state ], client.calls
  end

  test "does not read when monitoring is disabled" do
    client = FakeClient.new(state: state)

    ConfigLoader.stub(:app_config, config(monitoring_enabled: false)) do
      assert_no_difference -> { SolakonReading.count } do
        SolakonMonitorJob.new.perform(client: client)
      end
    end

    assert_empty client.calls
  end

  test "does not persist or control after read failure" do
    client = FakeClient.new(fail: true)

    ConfigLoader.stub(:app_config, config(control_enabled: true)) do
      assert_no_difference -> { SolakonReading.count } do
        SolakonMonitorJob.new.perform(client: client)
      end
    end
  end

  test "triggers zero export after successful read when control is enabled" do
    client = FakeClient.new(state: state)
    calls = []

    ZeroExportTickJob.stub(:perform_now, ->(state:) { calls << state }) do
      ConfigLoader.stub(:app_config, config(control_enabled: true)) do
        SolakonMonitorJob.new.perform(client: client)
      end
    end

    assert_equal [ state ], calls
  end
end
```

- [ ] **Step 2: Run monitor job test and verify failure**

Run:

```bash
rtk bin/rails test test/jobs/solakon_monitor_job_test.rb
```

Expected: FAIL because the job does not exist.

- [ ] **Step 3: Implement `SolakonMonitorJob`**

Create `app/jobs/solakon_monitor_job.rb`:

```ruby
require "config_loader"
require "solakon_client"

class SolakonMonitorJob < ApplicationJob
  queue_as :default

  def perform(client: nil, now: Time.current)
    config = ConfigLoader.app_config
    solakon = config.solakon

    return Rails.logger.info("solakon_monitor: not configured") if solakon.nil?
    return Rails.logger.info("solakon_monitor: disabled") unless solakon.monitoring_enabled

    client ||= SolakonClient.new(host: solakon.host, port: solakon.port, unit_id: solakon.unit_id)
    state = client.read_state

    SolakonReading.create!(
      taken_at: now,
      active_power_w: state.active_power_w,
      pv_power_w: state.pv_power_w,
      battery_power_w: state.battery_power_w,
      battery_soc_pct: state.battery_soc
    )

    ActionCable.server.broadcast("dashboard", solakon: true)
    ZeroExportTickJob.perform_now(state: state) if solakon.control_enabled
  rescue SolakonClient::Error => e
    Rails.logger.warn("solakon_monitor: Modbus failure: #{e.message}")
  end
end
```

- [ ] **Step 4: Update recurring schedule**

In `config/recurring.yml`, replace the `zero_export_tick` class with `SolakonMonitorJob`, keeping the 30-second cadence. Name the entry `solakon_monitor`:

```yml
solakon_monitor:
  class: SolakonMonitorJob
  schedule: every 30 seconds
```

Remove the old `zero_export_tick` recurring entry so the writer is no longer the leading scheduled job.

- [ ] **Step 5: Run job tests**

Run:

```bash
rtk bin/rails test test/jobs/solakon_monitor_job_test.rb test/jobs/zero_export_tick_job_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add app/jobs/solakon_monitor_job.rb config/recurring.yml test/jobs/solakon_monitor_job_test.rb
rtk git commit -m "feat: add Solakon monitoring job"
```

## Task 5: Live API Energy Flow Object

**Files:**
- Modify: `app/controllers/api_controller.rb`
- Test: `test/controllers/api_controller_test.rb`

- [ ] **Step 1: Write failing API tests**

Add these tests to `test/controllers/api_controller_test.rb`:

```ruby
test "live includes Solakon energy flow when reading is fresh" do
  now = Time.zone.local(2026, 6, 18, 12, 0, 0)
  Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 120, aenergy_wh: 1)
  Sample.create!(plug_id: "desk", ts: now.to_i - 5, apower_w: 80, aenergy_wh: 1)
  SolakonReading.create!(
    taken_at: now - 10.seconds,
    active_power_w: 260,
    pv_power_w: 310,
    battery_power_w: -50,
    battery_soc_pct: 84
  )

  travel_to now do
    get "/api/live", as: :json
  end

  flow = response.parsed_body.fetch("energy_flow")
  assert_equal true, flow.fetch("solakon_online")
  assert_equal 200.0, flow.fetch("home_w")
  assert_equal 260.0, flow.fetch("solakon_ac_w")
  assert_equal 310.0, flow.fetch("solar_w")
  assert_equal 84, flow.fetch("battery_soc_pct")
  assert_equal 50.0, flow.fetch("battery_w")
  assert_equal(-60.0, flow.fetch("grid_w"))
end

test "live marks Solakon energy flow unavailable when reading is stale" do
  now = Time.zone.local(2026, 6, 18, 12, 0, 0)
  SolakonReading.create!(
    taken_at: now - 10.minutes,
    active_power_w: 260,
    pv_power_w: 310,
    battery_power_w: -50,
    battery_soc_pct: 84
  )

  travel_to now do
    get "/api/live", as: :json
  end

  flow = response.parsed_body.fetch("energy_flow")
  assert_equal false, flow.fetch("solakon_online")
  assert_nil flow.fetch("solakon_ac_w")
  assert_nil flow.fetch("grid_w")
end
```

- [ ] **Step 2: Run API tests and verify failure**

Run:

```bash
rtk bin/rails test test/controllers/api_controller_test.rb
```

Expected: FAIL because `energy_flow` is not returned.

- [ ] **Step 3: Implement live calculation in `ApiController#live`**

After `@plugs = ...`, add:

```ruby
consumer_w = @plugs
  .select { |p| p[:role].to_sym == :consumer && p[:online] }
  .sum { |p| p[:apower_w].to_f }

solakon_cfg = app_config.solakon
stale_after_s = solakon_cfg&.stale_after_s || threshold
reading = solakon_cfg&.monitoring_enabled ? SolakonReading.latest_fresh(stale_after_s: stale_after_s, now: Time.zone.at(@now_ts)) : nil

@energy_flow =
  if reading
    {
      solakon_online: true,
      home_w: consumer_w,
      solakon_ac_w: reading.active_power_w,
      solar_w: reading.pv_power_w,
      battery_soc_pct: reading.battery_soc_pct,
      battery_w: reading.battery_display_power_w,
      grid_w: consumer_w - reading.active_power_w
    }
  else
    {
      solakon_online: false,
      home_w: consumer_w,
      solakon_ac_w: nil,
      solar_w: nil,
      battery_soc_pct: nil,
      battery_w: nil,
      grid_w: nil
    }
  end
```

Ensure the JSON template for `/api/live` includes:

```ruby
json.energy_flow @energy_flow
```

If `/api/live` relies on Rails implicit JSON rendering, add or update `app/views/api/live.json.jbuilder` so it contains both `json.plugs @plugs` and `json.energy_flow @energy_flow`.

- [ ] **Step 4: Run API tests**

Run:

```bash
rtk bin/rails test test/controllers/api_controller_test.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
rtk git add app/controllers/api_controller.rb app/views/api/live.json.jbuilder test/controllers/api_controller_test.rb
rtk git commit -m "feat: expose live Solakon energy flow"
```

## Task 6: Dashboard SVG And Battery Asset

**Files:**
- Create: `app/assets/images/icon_batterie.webp`
- Modify: `app/views/dashboard/index.html.erb`
- Test: `test/controllers/dashboard_controller_test.rb`

- [ ] **Step 1: Generate the battery logo asset**

Use the `imagegen` skill/tool to create a transparent-background plush battery icon. Prompt:

```text
Small cute plush-style battery icon, soft rounded fabric, friendly stitched details, green battery body with subtle highlights, transparent background, centered, no text, no shadow, square icon, suitable for a 32px dashboard node.
```

Save the generated bitmap as:

```text
app/assets/images/icon_batterie.webp
```

- [ ] **Step 2: Write failing dashboard render test**

Add to `test/controllers/dashboard_controller_test.rb`:

```ruby
test "energy flow renders four nodes and six live flow targets" do
  get root_path

  assert_response :success
  assert_select "text", text: "Batterie"
  assert_select "image[href*='icon_batterie']"
  assert_select "[data-dashboard-target='efBatterySoc']"
  assert_select "[data-dashboard-target='efBatteryW']"
  assert_select "[data-dashboard-target='efDotsSolarHome']"
  assert_select "[data-dashboard-target='efDotsSolarGrid']"
  assert_select "[data-dashboard-target='efDotsSolarBattery']"
  assert_select "[data-dashboard-target='efDotsGridHome']"
  assert_select "[data-dashboard-target='efDotsGridBattery']"
  assert_select "[data-dashboard-target='efDotsBatteryHome']"
end
```

- [ ] **Step 3: Run dashboard controller test and verify failure**

Run:

```bash
rtk bin/rails test test/controllers/dashboard_controller_test.rb
```

Expected: FAIL because the battery node and new targets do not exist.

- [ ] **Step 4: Replace the SVG**

In `app/views/dashboard/index.html.erb`, replace the current energy-flow SVG with a four-node SVG using these stable coordinates:

```erb
<svg viewBox="0 0 400 320" style="width:100%;height:auto;display:block" aria-label="Live-Energiefluss">
  <defs>
    <clipPath id="ef-clip">
      <path fill-rule="evenodd" d="M 0,0 H 400 V 320 H 0 Z M 200,38 A 42,42 0 1,0 200,122 A 42,42 0 1,0 200,38 Z M 68,138 A 42,42 0 1,0 68,222 A 42,42 0 1,0 68,138 Z M 332,138 A 42,42 0 1,0 332,222 A 42,42 0 1,0 332,138 Z M 200,218 A 42,42 0 1,0 200,302 A 42,42 0 1,0 200,218 Z"/>
    </clipPath>
  </defs>

  <path data-dashboard-target="efLineSolarHome" d="M 200,122 C 205,150 250,176 290,180" fill="none" stroke="#f59f00" stroke-width="3" stroke-linecap="round"/>
  <path data-dashboard-target="efLineSolarGrid" d="M 200,122 C 195,150 150,176 110,180" fill="none" stroke="#8b5cf6" stroke-width="3" stroke-linecap="round"/>
  <path data-dashboard-target="efLineSolarBattery" d="M 200,122 L 200,218" fill="none" stroke="#ec4899" stroke-width="3" stroke-linecap="round"/>
  <path data-dashboard-target="efLineGridHome" d="M 110,180 L 290,180" fill="none" stroke="#3b82f6" stroke-width="3" stroke-linecap="round"/>
  <path data-dashboard-target="efLineGridBattery" d="M 104,206 C 135,235 160,255 200,218" fill="none" stroke="#94a3b8" stroke-width="3" stroke-linecap="round"/>
  <path data-dashboard-target="efLineBatteryHome" d="M 200,218 C 240,255 265,235 296,206" fill="none" stroke="#14b8a6" stroke-width="3" stroke-linecap="round"/>

  <g data-dashboard-target="efDotsSolarHome" clip-path="url(#ef-clip)"></g>
  <g data-dashboard-target="efDotsSolarGrid" clip-path="url(#ef-clip)"></g>
  <g data-dashboard-target="efDotsSolarBattery" clip-path="url(#ef-clip)"></g>
  <g data-dashboard-target="efDotsGridHome" clip-path="url(#ef-clip)"></g>
  <g data-dashboard-target="efDotsGridBattery" clip-path="url(#ef-clip)"></g>
  <g data-dashboard-target="efDotsBatteryHome" clip-path="url(#ef-clip)"></g>

  <circle cx="200" cy="80" r="40" fill="white" stroke="#f59f00" stroke-width="2.5"/>
  <image href="<%= asset_path @dashboard_weather_asset %>" x="184" y="53" width="32" height="32"/>
  <text data-dashboard-target="efPvW" x="200" y="104" text-anchor="middle" font-size="12" font-weight="600" fill="#7c5e00">— W</text>
  <text x="200" y="22" text-anchor="middle" font-size="11" fill="#6c757d">PV-Anlage</text>

  <circle cx="68" cy="180" r="40" fill="white" stroke="#3b82f6" stroke-width="2.5"/>
  <image href="<%= asset_path 'icon_netz.webp' %>" x="52" y="153" width="32" height="32"/>
  <text data-dashboard-target="efGridW" x="68" y="204" text-anchor="middle" font-size="12" font-weight="600" fill="#1d4ed8">— W</text>
  <text x="68" y="236" text-anchor="middle" font-size="11" fill="#6c757d">Stromnetz</text>

  <circle cx="332" cy="180" r="40" fill="white" stroke="#f59f00" stroke-width="2.5"/>
  <image href="<%= asset_path 'icon_haus.webp' %>" x="316" y="153" width="32" height="32"/>
  <text data-dashboard-target="efConsumerW" x="332" y="204" text-anchor="middle" font-size="12" font-weight="600" fill="#065f46">— W</text>
  <text x="332" y="236" text-anchor="middle" font-size="11" fill="#6c757d">Verbraucher</text>

  <circle cx="200" cy="260" r="40" fill="white" stroke="#ec4899" stroke-width="2.5"/>
  <image href="<%= asset_path 'icon_batterie.webp' %>" x="184" y="232" width="32" height="32"/>
  <text data-dashboard-target="efBatterySoc" x="200" y="273" text-anchor="middle" font-size="11" font-weight="600" fill="#be185d">— %</text>
  <text data-dashboard-target="efBatteryW" x="200" y="288" text-anchor="middle" font-size="11" font-weight="600" fill="#be185d">— W</text>
  <text x="200" y="316" text-anchor="middle" font-size="11" fill="#6c757d">Batterie</text>
</svg>
```

- [ ] **Step 5: Run dashboard controller test**

Run:

```bash
rtk bin/rails test test/controllers/dashboard_controller_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add app/assets/images/icon_batterie.webp app/views/dashboard/index.html.erb test/controllers/dashboard_controller_test.rb
rtk git commit -m "feat: add battery node to energy flow"
```

## Task 7: Dashboard Live JavaScript

**Files:**
- Modify: `app/javascript/controllers/dashboard_controller.js`

- [ ] **Step 1: Update target list**

Replace the energy-flow targets with:

```js
"efPvW", "efGridW", "efConsumerW", "efBatterySoc", "efBatteryW",
"efLineSolarHome", "efLineSolarGrid", "efLineSolarBattery",
"efLineGridHome", "efLineGridBattery", "efLineBatteryHome",
"efDotsSolarHome", "efDotsSolarGrid", "efDotsSolarBattery",
"efDotsGridHome", "efDotsGridBattery", "efDotsBatteryHome",
```

- [ ] **Step 2: Store `energy_flow` from broadcasts/fetches**

In `connect`, initialize:

```js
this.energyFlow = null
```

In `handleReading`, after plug handling:

```js
if (data.energy_flow) this.energyFlow = data.energy_flow
if (data.solakon) this.fetchLive()
```

In `fetchLive`, after validating `data.plugs`:

```js
if (data.energy_flow) this.energyFlow = data.energy_flow
```

- [ ] **Step 3: Update hero and live tiles to prefer Solakon flow**

In `updateHero`, use:

```js
const flow = this.energyFlow
const w = flow?.solakon_online ? Math.max(0, flow.solar_w || 0).toFixed(0) : "—"
this.heroValueTarget.innerHTML = `<span class="hero-number">${w}</span> <span class="hero-unit">W</span>`
```

In `updateLiveTiles`, compute:

```js
const flow = this.energyFlow
const consumers = plugs.filter(p => p.role === "consumer")
const conW = flow?.home_w ?? consumers.reduce((s, p) => s + (p.online ? p.apower_w : 0), 0)
const gridW = flow?.grid_w

if (this.hasTileConsumptionTarget)
  this.tileConsumptionTarget.textContent = flow?.solakon_online || plugs.some(p => p.online) ? conW.toFixed(0) + " W" : "—"
if (this.hasTileNetbalanceTarget)
  this.tileNetbalanceTarget.textContent = gridW == null ? "—" : (gridW <= 0 ? "+" : "−") + Math.abs(gridW).toFixed(0) + " W"
```

This keeps the existing tile meaning as "balance now": positive display means surplus, negative display means grid import.

- [ ] **Step 4: Replace `updateEnergyFlow`**

Use:

```js
updateEnergyFlow(plugs) {
  const flow = this.energyFlow
  const consumers = plugs.filter(p => p.role === "consumer")
  const fallbackHomeW = consumers.reduce((s, p) => s + (p.online ? p.apower_w : 0), 0)

  const online = !!flow?.solakon_online
  const homeW = online ? (flow.home_w || 0) : fallbackHomeW
  const solarW = online ? (flow.solar_w || 0) : null
  const solakonAcW = online ? (flow.solakon_ac_w || 0) : null
  const batteryW = online ? (flow.battery_w || 0) : null
  const gridW = online ? flow.grid_w : null

  if (this.hasEfPvWTarget)
    this.efPvWTarget.textContent = solarW == null ? "— W" : solarW.toFixed(0) + " W"
  if (this.hasEfConsumerWTarget)
    this.efConsumerWTarget.textContent = homeW.toFixed(0) + " W"
  if (this.hasEfGridWTarget)
    this.efGridWTarget.textContent = gridW == null ? "— W" :
      gridW > 0 ? "+" + gridW.toFixed(0) + " W" :
      gridW < 0 ? "−" + Math.abs(gridW).toFixed(0) + " W" : "0 W"
  if (this.hasEfBatterySocTarget)
    this.efBatterySocTarget.textContent = online && flow.battery_soc_pct != null ? `${flow.battery_soc_pct}%` : "— %"
  if (this.hasEfBatteryWTarget)
    this.efBatteryWTarget.textContent = batteryW == null ? "— W" :
      (batteryW >= 0 ? "+" : "−") + Math.abs(batteryW).toFixed(0) + " W"

  const batteryChargeW = Math.max(0, batteryW || 0)
  const batteryDischargeW = Math.max(0, -(batteryW || 0))
  const gridToHome = Math.max(0, gridW || 0)
  const exportW = Math.max(0, -(gridW || 0))
  const solarToBattery = batteryChargeW
  const batteryToHome = Math.min(batteryDischargeW, homeW)
  const solarAcW = Math.max(0, (solakonAcW || 0) - batteryDischargeW)
  const solarToHome = Math.max(0, Math.min(solarAcW, homeW - batteryToHome))
  const solarToGrid = exportW

  const paths = {
    solarHome: "M 200,122 C 205,150 250,176 290,180",
    solarGrid: "M 200,122 C 195,150 150,176 110,180",
    solarBattery: "M 200,122 L 200,218",
    gridHome: "M 110,180 L 290,180",
    gridBattery: "M 104,206 C 135,235 160,255 200,218",
    batteryHome: "M 200,218 C 240,255 265,235 296,206",
  }
  const lens = { solarHome: 145, solarGrid: 145, solarBattery: 96, gridHome: 180, gridBattery: 125, batteryHome: 125 }

  this._efSetDots("efDotsSolarHomeTarget", paths.solarHome, "#f59f00", solarToHome, lens.solarHome)
  this._efSetDots("efDotsSolarGridTarget", paths.solarGrid, "#8b5cf6", solarToGrid, lens.solarGrid)
  this._efSetDots("efDotsSolarBatteryTarget", paths.solarBattery, "#ec4899", solarToBattery, lens.solarBattery)
  this._efSetDots("efDotsGridHomeTarget", paths.gridHome, "#3b82f6", gridToHome, lens.gridHome)
  this._efSetDots("efDotsGridBatteryTarget", paths.gridBattery, "#94a3b8", 0, lens.gridBattery)
  this._efSetDots("efDotsBatteryHomeTarget", paths.batteryHome, "#14b8a6", batteryToHome, lens.batteryHome)
}
```

Remove the old three-line color changing and consumer breakdown ring logic, since the new diagram keeps all six static colored lines visible.

- [ ] **Step 5: Smoke-test the asset build and controller syntax**

Run:

```bash
rtk bin/rails test test/controllers/dashboard_controller_test.rb test/controllers/api_controller_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add app/javascript/controllers/dashboard_controller.js
rtk git commit -m "feat: render Solakon live energy flow"
```

## Task 8: End-To-End Verification

**Files:**
- No new files unless verification reveals a defect.

- [ ] **Step 1: Run focused backend tests**

Run:

```bash
rtk bin/rails test test/models/solakon_reading_test.rb test/config_loader_test.rb test/jobs/solakon_monitor_job_test.rb test/jobs/zero_export_tick_job_test.rb test/controllers/api_controller_test.rb test/controllers/dashboard_controller_test.rb test/solakon_client_test.rb
```

Expected: PASS.

- [ ] **Step 2: Run full test suite**

Run:

```bash
rtk bin/rails test
```

Expected: PASS.

- [ ] **Step 3: Start the app for manual UI verification**

Run:

```bash
rtk bin/rails server -p 51328
```

Open:

```text
http://localhost:51328/
```

Check:

- The live energy overview stayed in the same dashboard section.
- Solar, grid, and home use the existing icons.
- Battery uses `icon_batterie.webp`.
- All six colored lines are visible.
- Dots appear only on active flows.
- Battery shows a percentage and signed W value.
- With no fresh Solakon reading, Solakon-dependent values show dashes and flow dots stop.

- [ ] **Step 4: Commit verification fixes if needed**

If fixes were required:

```bash
rtk git status --short
rtk git add app/models/solakon_reading.rb app/jobs/solakon_monitor_job.rb app/jobs/zero_export_tick_job.rb app/controllers/api_controller.rb app/views/dashboard/index.html.erb app/javascript/controllers/dashboard_controller.js lib/config_loader.rb lib/solakon_client.rb config/recurring.yml config/ziwoas.example.yml test/models/solakon_reading_test.rb test/jobs/solakon_monitor_job_test.rb test/jobs/zero_export_tick_job_test.rb test/controllers/api_controller_test.rb test/controllers/dashboard_controller_test.rb test/config_loader_test.rb test/solakon_client_test.rb
rtk git commit -m "fix: polish Solakon live energy flow"
```

If no fixes were required, do not create an empty commit.

## Spec Coverage Self-Review

- Dedicated Solakon readings: Task 1.
- Config split and read/write safety: Task 2.
- Monitoring job reads then optional control: Tasks 3 and 4.
- Calculated grid value and live API: Task 5.
- Existing dashboard location, four nodes, six lines, existing logos, plush battery logo: Task 6.
- Live W values, battery SoC/sign, animated dots: Task 7.
- Error handling and stale data behavior: Tasks 4, 5, and 8.
- Testing and manual verification: all tasks include focused tests; Task 8 covers the final sweep.
