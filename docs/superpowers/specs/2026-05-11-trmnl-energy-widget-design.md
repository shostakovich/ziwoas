# TRMNL Energy Widget — Design

**Status:** approved (brainstorm)
**Date:** 2026-05-11
**Scope:** Single TRMNL "full" e-paper widget (800 × 480) showing today's energy story for the Zipfelmaus apartment.

## Goal

Give the household a glanceable e-paper widget that answers:

- How much PV did we make today? At what cost/savings?
- How did the last 24 h look hourly — and how much of that PV was used vs. fed back?
- Where do we stand on autarky and self-consumption right now?

It is a one-way mirror of data the existing Rails app already computes. No interaction, no live readouts.

## Constraints

- **TRMNL refresh ≥ 15 min** — no "live" values. Any timestamp shown is the freshness of the data, not the moment of viewing.
- **TRMNL webhook payload ≤ 2 kB** — time-series data is encoded as bare integer arrays.
- **1-bit e-paper rendering** — solid fills, hatched fills, dashed strokes are the only visual differentiators. No color, no gradients, no anti-aliased detail.
- **App stays internal** — TRMNL must receive data via push (webhook), not pull a public Rails endpoint.

## User-facing layout

Single "full" layout, 800 × 480. Other TRMNL sizes (half_horizontal, half_vertical, quadrant) are out of scope for this iteration.

```
┌────────────────────────────────────────────────────────────────┐
│  PV HEUTE                                  BILANZ HEUTE        │
│  3,42 kWh                                  −1,76 kWh           │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │   ░██ ░██   .         . ░██ ░██ ░██ ░██               │  │
│  │  ░░██░██░██ .  . . . ░██░██░██░██░██░██░██░██░██░██   │  │
│  │  ██ ██ ██ ██ . . . ░██ ██ ██ ██ ██ ██ ██ ██ ██ ██ ██   │  │
│  │  ─────────────────────────────────────────────────────  │  │
│  │  −24h         −18h         −12h         −6h        jetzt│  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  VERBRAUCHT HEUTE   AUTARKIE       EIGENVERBRAUCH              │
│  5,18 kWh           61 %           82 %                        │
├────────────────────────────────────────────────────────────────┤
│  ZIPFELMAUS ENERGIE                              STAND 14:23   │
└────────────────────────────────────────────────────────────────┘
```

- **Hero row** — `PV heute` (left, large) and `Bilanz heute` (right, slightly smaller). Both reference the local calendar day. `Bilanz` follows the existing dashboard convention: `produced_kwh − consumed_kwh`, signed (negative when the home consumed more than the PV produced).
- **Chart** — 24 hourly bars covering the rolling last 24 h. Each bar is split into two stacked segments:
  - solid lower segment = energy that was self-consumed in that hour (Wh)
  - hatched upper segment = energy that was fed to the grid in that hour (Wh)
  - bars whose hour produced no PV render as a flat 2-px tick
  - tiny legend in top-right of chart explains the two fills
  - axis labels at −24 h, −18 h, −12 h, −6 h, jetzt
- **Footer row** — `Verbraucht heute` (consumed kWh, calendar day) · `Autarkie` (% of consumption covered by own PV) · `Eigenverbrauch` (% of PV that we used ourselves).
- **Title bar** — `ZIPFELMAUS ENERGIE` left, `STAND HH:MM` right. The timestamp is the local time of the most recent sample that fed the payload, not the rendering time.

Numbers are in German locale (comma decimal separator). Currency uses `€` suffix. Percentages use no decimals.

## Architecture

```
SolidQueue recurring (every 15 min)
  └── TrmnlPushJob
        ├── TrmnlPayloadBuilder
        │     ├── EnergySummary#compute_today    (today aggregates)
        │     └── hourly rolling-24h aggregation  (new logic)
        └── Net::HTTP POST application/json
              → config.trmnl_webhook_url
                   = https://trmnl.com/api/custom_plugins/<uuid>

TRMNL cloud
  └── stores merge_variables, renders Liquid template on each
      device refresh (≥ 15 min) → e-paper

config/ziwoas.yml
  trmnl_webhook_url: <full URL incl. UUID>  # optional; absent = job no-op
```

No public Rails endpoint is added. The widget is fed by push only.

## Components

### `Ziwoas::Config`

- New optional field `trmnl_webhook_url` (String). Loaded from `config/ziwoas.yml`.
- `config/ziwoas.example.yml` gets a commented example block.
- Absent / empty / nil → push job is a no-op.

### `TrmnlPayloadBuilder` (new, `app/models/`)

Pure ruby object, no AR persistence. Constructed with `config:`, exposes a single `build` method returning a `Hash` ready for JSON serialization.

Responsibilities:

- Call `EnergySummary.new(config:).compute_today` for the hero/footer aggregates and ratios.
- Compute the rolling 24 h hourly buckets in local time:
  - 24 buckets, each aligned to the local-hour boundary; oldest first, newest last.
  - Each bucket carries `eigenverbrauch_wh` and `einspeisung_wh` as integers.
  - `eigenverbrauch_wh` per bucket = min(producer power, consumer power) integrated over the bucket (same overlap logic `EnergySummary#compute_self_consumed_wh` already uses, parameterised by start/end and bucket size = 3600 s).
  - `einspeisung_wh` per bucket = total producer energy − `eigenverbrauch_wh`, floored at 0.
- Capture `meta.sample_ts` = unix-seconds of the most recent `Sample.ts` used in the computation; fall back to `Time.now.to_i` when no samples exist.
- Output shape:

  ```ruby
  {
    "merge_variables" => {
      "ts"         => 1715425380,
      "pv_kwh"     => 3.42,
      "cons_kwh"   => 5.18,
      "bilanz_kwh" => -1.76,
      "autarky"    => 61,
      "self_use"   => 82,
      "ev"         => [120,80,40,10,0,0,0,0,0,0,0,0,40,180,420,640,720,750,720,620,480,320,180,80],
      "es"         => [40,20,5,0,0,0,0,0,0,0,0,0,0,80,200,320,360,400,360,300,220,140,80,30]
    }
  }
  ```

  - `pv_kwh`, `cons_kwh`, `bilanz_kwh` rounded to 2 decimals.
  - `bilanz_kwh` is signed (negative when more was consumed than produced).
  - `autarky`, `self_use` rounded to integer %.
  - `ev`, `es` integer Wh per hour.

Bilanz definition (consistent with the existing dashboard "Bilanz heute" tile in `app/javascript/controllers/dashboard_controller.js:275`): `(produced_wh − consumed_wh) / 1000.0`.

### `TrmnlPushJob` (new, `app/jobs/`)

`ActiveJob::Base` subclass, runs in the `default` queue.

- No-op if `app_config.trmnl_webhook_url.blank?`. Logs once at INFO level: `"TRMNL push skipped (no webhook URL configured)"`.
- Builds payload via `TrmnlPayloadBuilder.new(config: app_config).build`.
- Serialises to JSON, asserts byte length ≤ 2 048 (raise + log if exceeded — a regression we want loud, not silent).
- POSTs with `Net::HTTP` to `trmnl_webhook_url`, `Content-Type: application/json`, 10 s open/read timeout.
- Success path: `Rails.logger.info "TRMNL push: HTTP #{code}, #{bytes} B"`.
- Failure path (non-2xx or exception): `Rails.logger.warn` with status / class / message. No ActiveJob retry — the next scheduled run is the retry.

### `config/recurring.yml`

Add inside the `aggregator_schedule` anchor:

```yaml
push_trmnl_widget:
  class: TrmnlPushJob
  queue: default
  schedule: every 15 minutes
```

The wetter-fetch jobs already pace at this cadence, so we follow the same pattern.

### Liquid template — `docs/trmnl/full.liquid`

Source-of-truth file kept in the repo. The TRMNL plugin UI hosts the executed copy; updates are a copy-paste step performed by the operator (rare).

Template uses TRMNL framework classes (`layout`, `columns`, `title_bar`, `value`, `label`) and renders:

- Hero row from `pv_kwh`, `bilanz_kwh`.
- Footer row from `cons_kwh`, `autarky`, `self_use`.
- 24 bars by iterating `(0..23)` and reading `ev[i]`, `es[i]`. Each bar's total height is `ev[i] + es[i]` (Wh); the y-axis maximum is `max_i (ev[i] + es[i])` so the day's peak hour fills the chart vertically. When that maximum is 0 (no PV in 24 h), all bars render as the flat 2-px tick.
- Axis labels derived in Liquid from `ts` (e.g. `{{ ts | minus: 21600 | date: "%-H h" }}`).
- Title-bar right-side renders `STAND {{ ts | date: "%H:%M" }}` (TRMNL's Liquid runtime is configured to the device's local timezone, matching the user's `Europe/Berlin`).

## Edge cases

- **Webhook URL missing** — job is a no-op, no error.
- **HTTP failure / network down / TRMNL 5xx** — warn-level log, no retry; next 15-min run replaces the attempt.
- **No samples in the last 24 h** (first boot, sensors offline) — all 24 entries in `ev` / `es` are 0; `ts = Time.now.to_i`; widget shows an empty chart instead of crashing.
- **Partial coverage** (some producer or consumer plugs offline) — handled the same way `EnergySummary` already handles missing rows: missing data contributes 0 to the affected bucket.
- **DST transitions** — buckets are bucketed in local time. The doubled or skipped hour appears as a slightly wider/narrower bar twice per year; no special handling.
- **Payload > 2 kB** — raises in the job, gets logged loudly. Unlikely with the current schema but worth surfacing as a regression check.

## Out of scope

- Other TRMNL sizes (`half_horizontal`, `half_vertical`, `quadrant`).
- PV forecast (the D2 variant with hollow forecast bars). Variant D3 was picked.
- Per-plug breakdown on the widget.
- Two-way control of plugs from TRMNL.
- Automated upload of the Liquid template — manual copy-paste accepted.
- Authentication on a Rails endpoint — there is no Rails endpoint.
