# TRMNL Sensor Widget — Design

**Status:** approved (brainstorm)
**Date:** 2026-05-12
**Scope:** Second TRMNL "full" e-paper widget (800 × 480) showing the current state of all SwitchBot sensors (2 indoor with CO₂, 1 outdoor) plus a 3-hour trend per sensor. Bundles two adjacent bug fixes: the energy-widget timestamp (UTC vs. local) and a broken Turbo broadcast in `SensorsBroadcaster.refresh` (missing partial path).

## Goal

Give the household a glanceable e-paper widget that answers:

- Wie ist die Luft in jedem Raum gerade? (CO₂ ppm + Ampel)
- Wohin geht's? (3-h-Trend pro Sensor)
- Wie warm/feucht ist es draußen?

It is a one-way mirror of data the existing Rails app already stores in `sensor_readings`. No interaction, no live readouts.

## Constraints

- **TRMNL refresh ≥ 15 min** — same as the energy widget. The "Stand HH:MM" timestamp is the freshness of the data, not the rendering time.
- **TRMNL webhook payload ≤ 2 kB** — trend data is encoded as bare integer arrays.
- **1-bit e-paper rendering** — solid black on white. The ampel uses solid/outline segments; the sparkline is a 2-px solid stroke.
- **App stays internal** — sensor widget is fed by push (webhook), not pull.
- **TRMNL Liquid renders in UTC** — we discovered the existing energy widget's `Stand` clock is off by the local-vs-UTC offset. Both widgets pre-format the timestamp in Ruby (see "Bug fix" below).

## User-facing layout

Single "full" layout, 800 × 480. Three sensor cards side-by-side in a `grid grid--cols-3 gap--large`, all centered (`align-center`).

```
┌────────────────────────────────────────────────────────────────┐
│       WOHNZIMMER             KÜCHE              BALKON         │
│                                                                │
│         1230                  740                12,4          │
│       ppm CO₂              ppm CO₂                °C           │
│                                                                │
│       ╱─ sparkline ╱       ─── flat ───       ╲─ sparkline ╲   │
│                                                                │
│        ▰ ▰ ▱                ▰ ▱ ▱             (no ampel)       │
│                                                                │
│      22,4 °C · 48 % rH    21,8 °C · 51 % rH   64 % rH          │
│        vor 4 Min            vor 3 Min          vor 5 Min       │
├────────────────────────────────────────────────────────────────┤
│  ZIPFELMAUS SENSOREN                             STAND 16:56   │
└────────────────────────────────────────────────────────────────┘
```

**Per card, in order:**

1. **Name** — `<span class="label">` (room name from config)
2. **Primary value** — `<span class="value value--large">`. CO₂ ppm for indoor sensors (`meter_pro_co2`), outdoor temperature in °C for `outdoor_meter`
3. **Unit label** — `<span class="label">` (`ppm CO₂` or `°C`)
4. **Mini-sparkline** — inline `<svg class="sparkline">` of the primary metric over the last 3 h, 12 points (15-min step). Polyline, solid black 2-px stroke, scaled to the card's min/max for that metric. On the outdoor card it shows °C; on indoor cards it shows ppm
5. **Ampel-bar** — three segments (custom CSS, 56 × 18 px each, 6-px gap). Levels: `gut` (<1000) = 1 segment filled; `warn` (1000–1400) = 2 segments filled; `schlecht` (>1400) = 3 segments filled. Outdoor card has the bar but with `visibility:hidden` so heights stay identical across cards
6. **Secondary metrics** — `<span class="label">`. Indoor: `22,4 °C · 48 % rH`. Outdoor: `64 % rH` (temp is already the primary value)
7. **Timestamp** — `<span class="label">vor X Min` from `taken_at`

**Footer** — framework `title_bar` with `title = "Zipfelmaus Sensoren"` and `instance = "Stand HH:MM"` (local time, pre-formatted in Ruby).

Numbers use German locale (`,` decimal separator). The card-internal column-stack is `align-center` so the trio sits symmetrically on the screen.

### Edge-case rendering

- **Offline sensor** (no reading within the last 30 min, or `latest_per_device` returns nothing): the card renders with `—` in place of the primary value, no sparkline, hidden ampel, and the timestamp says `keine Daten seit X h` (or `keine Daten` if we never had a reading)
- **Battery low** (`battery_pct ≤ 20`, same threshold as the existing dashboard): one extra `<span class="label">` between the secondary metrics and the timestamp: `⚠ Batterie 14 %`. The threshold matches `SensorsHelper::BATTERY_LOW_PCT`

## Architecture

```
SolidQueue recurring (every 15 min)
  └── SensorPollJob
        ├── polls SwitchBot, persists SensorReading rows
        ├── SensorsBroadcaster.refresh  (existing)
        └── TrmnlSensorPushJob.perform_later   ← new tail call
              └── TrmnlSensorPayloadBuilder
                    ├── latest SensorReading per device
                    └── 3-h, 15-min-bucket trend per primary metric
                  Net::HTTP POST application/json
                    → config.trmnl.sensors_webhook_url

TRMNL cloud
  └── stores merge_variables, renders Liquid template on each
      device refresh (≥ 15 min) → e-paper

config/ziwoas.yml
  trmnl:
    energy_webhook_url:  https://trmnl.com/api/custom_plugins/<uuid-1>
    sensors_webhook_url: https://trmnl.com/api/custom_plugins/<uuid-2>
```

The push piggybacks on the existing `SensorPollJob` cadence: every fresh sensor read immediately feeds a webhook push, so the e-paper never lags behind what the dashboard knows. No second cron entry is needed.

No public Rails endpoint is added. The widget is fed by push only.

## Config evolution

The flat `trmnl_webhook_url` key gets replaced by a nested `trmnl:` block carrying both URLs. The operator updates `config/ziwoas.yml` once; no backwards-compat shim.

```yaml
trmnl:
  energy_webhook_url:  https://trmnl.com/api/custom_plugins/<uuid-1>
  sensors_webhook_url: https://trmnl.com/api/custom_plugins/<uuid-2>
```

`ConfigLoader`:

- New `TrmnlCfg = Struct.new(:energy_webhook_url, :sensors_webhook_url, keyword_init: true)` replacing the old flat `trmnl_webhook_url` field on `Config`.
- `build_trmnl(h)`: if the `trmnl:` mapping is present, parse `energy_webhook_url` + `sensors_webhook_url` (both optional strings). If `trmnl:` is absent, return `TrmnlCfg.new(energy_webhook_url: nil, sensors_webhook_url: nil)`.
- Each absent URL → its push job is a no-op (no error). Same behaviour today's energy URL has when omitted.

`config/ziwoas.example.yml`: replace the existing `trmnl_webhook_url` comment block with the new nested example showing both URLs.

## Components

### `TrmnlSensorPayloadBuilder` (new, `app/models/`)

Pure Ruby object, no AR persistence. Constructed with `config:`, exposes `build` returning a `Hash` ready for JSON serialization.

Responsibilities:

- For each sensor in `config.sensors`, in config order:
  - Look up `latest = SensorReading.latest_per_device([sensor.id]).first`
  - Compute the 3-h trend: 12 buckets of 15 min each, in `Europe/Berlin`, aligned to the local-quarter-hour ending at the most recent bucket boundary. For each bucket, AVG of the primary metric (ppm for `meter_pro_co2`, temperature for `outdoor_meter`) across readings whose `taken_at` falls inside the bucket. Missing buckets carry `null` so the Liquid template can render gaps without confusing them with `0`.
- Compute the `stand` string: local-time `"%H:%M"` of the most recent `taken_at` across all sensors (fall back to `Time.current.in_time_zone(@tz).strftime("%H:%M")` if no readings exist).
- Output shape (~700–900 B for 3 sensors, well under the 2 kB cap):

  ```ruby
  {
    "merge_variables" => {
      "stand" => "16:56",
      "sensors" => [
        {
          "id"          => "ABCDEF123456",
          "name"        => "Wohnzimmer",
          "type"        => "indoor",            # "indoor" | "outdoor"
          "primary"     => 1230,                # ppm (Integer) or 12.4 (Float)
          "unit"        => "ppm CO₂",
          "ampel"       => "warn",              # "good" | "warn" | "bad"  (omitted for outdoor)
          "trend"       => [712,740,755, ... 12 values, null for missing],
          "temperature" => 22.4,
          "humidity"    => 48,
          "battery_low" => false,               # battery_pct ≤ 20
          "battery_pct" => 73,
          "age_label"   => "vor 4 Min",         # pre-formatted German
          "offline"     => false                # true when no reading in 30 min
        },
        # ... 2 more
      ]
    }
  }
  ```

  - `primary` is `Integer` for ppm, `Float` rounded to 1 decimal for °C
  - `trend` integers for ppm, floats for °C; `null` (Ruby `nil`) for empty buckets
  - `age_label` follows `SensorsHelper#relative_time` formatting (`vor X s` / `vor X Min` / `vor X h`)
  - `ampel` is omitted (or `nil`) for outdoor cards so the template can skip the ampel-bar
  - `offline = true` when the freshest reading is older than 30 min — template renders the dash state

Helper extraction: the existing `SensorsHelper#co2_level` / `#relative_time` / `#battery_low?` logic gets factored into a `Sensors::ReadingPresenter` PORO so both the web dashboard and the TRMNL builder reuse it without going through ActionView.

### `TrmnlSensorPushJob` (new, `app/jobs/`)

`ActiveJob::Base` subclass on the `default` queue. Mirrors `TrmnlPushJob` exactly:

- No-op if `app_config.trmnl.sensors_webhook_url.blank?`. Logs once at INFO: `"TRMNL sensor push skipped (no webhook URL configured)"`.
- Builds payload via `TrmnlSensorPayloadBuilder.new(config: app_config).build`.
- Asserts JSON byte length ≤ 2 048 (raise + log on overflow).
- POSTs with `Net::HTTP` to `sensors_webhook_url`, `Content-Type: application/json`, 10 s open/read timeout.
- Success: `Rails.logger.info "TRMNL sensor push: HTTP #{code}, #{bytes} B"`.
- Failure (non-2xx / exception): `Rails.logger.warn` with status / class / message. No ActiveJob retry — next scheduled run is the retry.

### `TrmnlPushJob` (existing, modified)

Switch from `app_config.trmnl_webhook_url` to `app_config.trmnl.energy_webhook_url`. No behavioural change beyond that.

### `SensorPollJob` (existing, modified)

After the SwitchBot polling loop, enqueue the TRMNL push **before** the Turbo broadcast — so that a broadcaster failure can't swallow the push:

```ruby
# perform, tail end
TrmnlSensorPushJob.perform_later   # new — independent of broadcast outcome
SensorsBroadcaster.refresh
```

Reasoning: `perform_later` returns the moment the job is enqueued, so reversing the order doesn't slow anything down; it just makes the push robust against bugs in the broadcaster path (we have one right now — see below).

### `SensorsBroadcaster.refresh` — bug fix

The current implementation broadcasts the `sensors/dashboard` partial through `Turbo::StreamsChannel.broadcast_replace_to`. This path **has no controller context**, so `<%= render "battery_warning" %>` inside `app/views/sensors/_dashboard.html.erb` resolves the relative partial path against the default lookup root (`application/`) and crashes with `Missing partial application/_battery_warning`.

Currently observed in production logs:

```
ActionView::Template::Error (Missing partial application/_battery_warning ...
  Did you mean? ... sensors/battery_warning)
  app/views/sensors/_dashboard.html.erb:9
  lib/sensors_broadcaster.rb:15
  app/jobs/sensor_poll_job.rb:32
```

Fix: qualify every relative `render` call in `_dashboard.html.erb` with the `sensors/` prefix.

```erb
<%= render "sensors/battery_warning", sensors: sensors, latest: latest %>
...
<%= render "sensors/card", sensor: s, reading: latest[s.id] %>
...
<%= render "sensors/charts" %>
```

The regular controller-driven page load (`SensorsController#index`) keeps working with the qualified paths — `render "sensors/foo"` resolves the same way regardless of context.

Add a test in `test/test_sensors_broadcaster.rb` (or extend `dashboard partial renders with only sensors and latest locals`) that exercises the broadcast through a **controller-less** rendering context, so a regression here gets caught in CI rather than in production.

### `TrmnlPayloadBuilder` (existing, modified) — bug fix

The existing widget shows `Stand 14:45` at 16:56 local because the Liquid template does `{{ ts | date: "%H:%M" }}` and TRMNL's Liquid renderer runs in UTC, not in `Europe/Berlin`.

Fix: pre-format the timestamp in Ruby and ship the formatted string in the payload. The unix `ts` field stays for any future trend logic but the template stops touching it.

- Add a new merge variable `"stand"` = local-time `"%H:%M"` (using `@tz.utc_to_local(Time.at(ts))`).
- Keep `"ts"` in the payload unchanged for backwards compatibility (no harm; it's ~12 bytes).
- The Liquid template `docs/trmnl/full.liquid` swaps `{{ ts | date: "%H:%M" }}` → `{{ stand }}`.

### `config/recurring.yml`

No new entry. `TrmnlSensorPushJob` is triggered by `SensorPollJob` (every 15 min) rather than scheduled directly. The existing `push_trmnl_widget` energy schedule stays unchanged.

### Liquid template — `docs/trmnl/sensors.liquid` (new)

Source-of-truth file in the repo. The TRMNL plugin UI hosts the executed copy; updates are copy-paste by the operator.

Loads `https://trmnl.com/css/latest/plugins.css` is implicit (TRMNL adds the framework on render). Uses framework classes:

- Outer: `<div class="layout layout--col layout--center">`
- Card grid: `<div class="grid grid--cols-3 gap--large">`
- Each card: `<div class="item align-center"><div class="content"> ... </div></div>` (with a custom `align-center` rule that sets `.content { align-items: center; text-align: center; }`)
- Typography: `value value--large` for the primary, `label` for everything else
- Footer: framework `title_bar` with `title` + `instance`

Custom CSS embedded in the template:

```css
.ampel-bar { display:inline-flex; gap:6px; margin-top:8px; }
.ampel-bar .seg { width:56px; height:18px; border:2px solid #000; box-sizing:border-box; }
.ampel-bar .seg.on { background:#000; }
.ampel-bar.is-hidden { visibility:hidden; }
.sparkline { display:block; width:180px; height:36px; margin:6px 0 2px; }
.sparkline polyline { fill:none; stroke:#000; stroke-width:2; stroke-linejoin:round; stroke-linecap:round; }
.trmnl .item.align-center .content { align-items:center; text-align:center; }
```

The template iterates `{% for s in sensors %}` and renders the card. For each:

- Name and primary value rendered straightforwardly
- Sparkline polyline: a small `{% capture %}` builds the `points="..."` string by mapping each trend index → `x = i * 15` (180 px / 12 points), and each trend value → `y = 36 - normalized * 32` where the normalization uses the min/max within that sensor's trend (Ruby pre-computes `trend_min` / `trend_max` per sensor to keep the Liquid simple — see addendum below)
- Ampel-bar: `{% if s.ampel %}` rendered with the right segments filled; else `is-hidden`
- Offline state: `{% if s.offline %}` swaps the value/sparkline/ampel block for a single `—` and the `age_label`

**Addendum to the payload to keep Liquid math trivial:** each sensor object also carries `"trend_min"` and `"trend_max"` (Numeric) so the template can compute `y` with one subtraction and one division per point. Adds ~30 bytes per sensor.

## Edge cases

- **Sensors webhook URL missing** — sensor job is a no-op, no error. Energy URL handled identically.
- **HTTP failure / network down / TRMNL 5xx** — warn-level log, no retry; next scheduled run replaces the attempt.
- **No readings at all** (first boot, all sensors offline) — `stand` falls back to `Time.current.in_time_zone(@tz)`; every card renders in offline state.
- **Sensor configured but never seen** — same as offline.
- **One sensor offline, others fine** — only that card shows the dash state.
- **Battery low + offline simultaneously** — offline takes precedence (no metrics, hence the battery line is suppressed too; the `age_label` already communicates the deeper problem).
- **DST transitions** — buckets bucketed in local time. The doubled or skipped quarter-hour appears as a slightly wider/narrower step twice per year; no special handling.
- **Payload > 2 kB** — raises in the job, gets logged loudly. With 3 sensors × ~250 B/sensor + ~100 B envelope we sit at ~850 B; we'd need ~6 sensors before this becomes a real concern.
- **Trend bucket empty** — `null` in the array; the Liquid template emits an `M ... L` gap so the polyline is interrupted rather than dropping to zero.

## Out of scope

- Other TRMNL sizes (`half_horizontal`, `half_vertical`, `quadrant`).
- Per-sensor history charts longer than 3 h on this widget (the web dashboard's 24-h chart covers that).
- More than 3 sensors. The current 3-column grid is fixed. Adding a 4th sensor requires a re-design pass.
- Pollutant types beyond CO₂ (the SwitchBot devices we use don't expose PM2.5/VOC).
- Two-way control of sensors from TRMNL.
- Automated upload of the Liquid templates — manual copy-paste accepted (same trade-off as the energy widget).
- Authentication on a Rails endpoint — there is no Rails endpoint.
