# Architecture

ZiWoAS is one Phoenix 1.8 application on one SQLite file. Device connections, recurring jobs
and the web endpoint run in the same VM under `Ziwoas.Application`. Domain vocabulary is in
[`CONTEXT.md`](../CONTEXT.md), decisions are in [`adr/`](adr/).

## Supervision tree

```
Ziwoas.Supervisor (one_for_one)
├── Ziwoas.Repo                 SQLite (ecto_sqlite3)
├── Phoenix.PubSub              Ziwoas.PubSub: live updates for the pages
├── ZiwoasWeb.Endpoint          Bandit
├── Ziwoas.Collector            device connections (see Collector)
└── Ziwoas.Scheduler            recurring jobs (see Scheduler)
```

`Ziwoas.Application.boot_config/0` reads `config/ziwoas.yml` once at boot. If it does not load,
the error is logged and the app serves pages without the collector or the scheduler. Tests start
neither (`config :ziwoas, collector: false, scheduler: false` in `config/test.exs`).

## Configuration

- **`config/ziwoas.yml`** (not in the repo; template `config/ziwoas.example.yml`) describes the
  devices: location, MQTT, plugs, Fritz!Box, Solakon, Govee, SwitchBot sensors, TRMNL webhooks.
  `Ziwoas.Config` reads it with `yamerl`, checks it and turns it into structs (`Ziwoas.Config`,
  `Ziwoas.Plugs.Plug`, `Ziwoas.Location`, …). `Config.app_config/0` keeps it in
  `:persistent_term` per path. `Config.plug_roster/1` gives the **plug roster**. Retired keys
  are refused with a pointer to their new place, and the old `electricity_price_eur_per_kwh`
  key and a `migration:` block are ignored with a warning.
- **Cost items and electricity prices** live in the database (ADR-0004), maintained on
  `/solakon/wirtschaftlichkeit`.
- **Paths**: `ZIWOAS_CONFIG` and `ZIWOAS_DB` (`config/runtime.exs`). Development defaults to
  `config/ziwoas.yml` and `storage/development.sqlite3`, tests to
  `test/fixtures/ziwoas.test.yml` and `tmp/test.sqlite3`. A release needs both variables.
- **Time**: `Ziwoas.Clock` is the only source of "now" (`now/0,1`, `today/1`, `unix_now/0`). Tests
  freeze it through `config :ziwoas, frozen_clock:` (`Ziwoas.TestClock`). Local days and zones
  come from `tz` (`Ziwoas.LocalDay`, `Ziwoas.Location`); Elixir itself only knows UTC.
- **Outbound HTTP**: `Req` via `Ziwoas.Http` (Bright Sky, SwitchBot, TRMNL, Fritz!Box, Govee
  Platform API). Bodies stay raw and each client decodes its own answers. In tests every client
  is a `Req.Test` stub under its module name (`config :ziwoas, http_stubs: true`).

## Collector

`Ziwoas.Collector` (`one_for_one`, high restart intensity so a crash-looping connection never
takes the endpoint down). It starts only the children the configuration asks for:

```
Ziwoas.Collector
├── ziwoas-phoenix-ingest    MQTT: Ziwoas.Collector.MqttRouter
│                            ├── Ziwoas.Plugs.ShellyStatusHandler
│                            └── Ziwoas.Lights.GoveeSubscriber
├── Ziwoas.Solakon.Monitor   the Modbus TCP connection to the inverter
├── ziwoas-phoenix-fritz     MQTT publisher for the Fritz bridges
├── Ziwoas.Fritz.Bridge ×n   one per fritz_dect plug
├── Ziwoas.Govee.Bridge      LAN (UDP 4002) + Platform API
├── ziwoas-phoenix-govee     MQTT: govees/+/set in (Ziwoas.Govee.CommandHandler)
└── ziwoas-phoenix-command   MQTT publisher: plug switches and lamp commands
```

- **MQTT** is `tortoise311` (MQTT 3.1.1, QoS 0), wrapped by `Ziwoas.Mqtt`: `connection_spec/4` for
  a supervised connection, `publish` for a message. Tortoise reconnects with backoff (1 s to
  60 s). Client ids are fixed, so two instances must not share a broker.
- **Plugs.** Shelly plugs report `<prefix>/<plug>/status/switch:0`. `ShellyStatusHandler` writes
  a `samples` row per status (and `plug_states` when the status carries `output`), collects live
  deltas per plug and sends them at most every 5 s as `{:dashboard_live, deltas}` on `dashboard`.
  Fritz!DECT plugs are polled by `Ziwoas.Fritz.Bridge` through `Ziwoas.Fritz.DectClient` (AHA
  HTTP, MD5 or PBKDF2 challenge, `:xmerl`, `:crypto`) and published as Shelly-shaped status, so
  they take the same path.
- **Lamps.** `Ziwoas.Govee.Bridge` owns the `govees/<key>/{config,state,set}` contract: it loads
  the lamps from the Platform API (`PlatformApi`, `DeviceRegistry`), discovers and polls them on
  the LAN (`Lan`, multicast 239.255.255.250:4001, replies on UDP 4002, commands to 4003), keeps
  the published state (`StateStore`) and publishes config and state retained. A `set` verb goes
  through `CommandRouter` to the LAN or the cloud. `GoveeSubscriber` turns `config`/`state` into
  `lights`/`light_states` rows and sends `{:light_updated, key}` on `light_<key>` and `lights`.
  The LAN multicast needs host networking.
- **Inverter.** `Ziwoas.Solakon.Monitor` holds the one Modbus TCP connection; every read and
  write goes through it, so requests never interleave. `Ziwoas.Solakon.Modbus` speaks FC03, FC06
  and FC16 on `:gen_tcp`; `Ziwoas.Solakon.Client` knows the registers
  ([`solakon-modbus-protokoll.md`](solakon-modbus-protokoll.md), skill `solakon-modbus`). After a
  failure the monitor backs off 1 s → 60 s; a reused connection that fails is retried once on a
  fresh one.

## Scheduler

`Ziwoas.Scheduler` runs one `Ziwoas.Scheduler.Runner` per job from `config :ziwoas,
Ziwoas.Scheduler, jobs:` (`config/config.exs`). Schedules are a small natural language on the
local wall clock of `location.timezone` (`Ziwoas.Scheduler.Schedule`: `every 30 seconds`,
`every 3 hours`, `at 3:15am every day`), correct across DST. A job implements
`Ziwoas.Scheduler.Job.perform/1` and gets the due instant as `:at`. A run that overlaps the next
due instant skips it, nothing is made up after downtime, and a failure is logged, not retried.

| Job | Schedule | Module | Does |
| --- | --- | --- | --- |
| `solakon_monitor` | every 30 s | `Solakon.MonitorJob` | reading → `solakon_readings`, control tick, `{:solakon_reading, id}` on `solakon` |
| `solakon_snapshot` | every 2 min | `Solakon.SnapshotJob` | full register snapshot → `solakon_snapshots` |
| `schedule_tick` | every minute | `Switching.ScheduleTickJob` | switches due edges (ADR-0001) |
| `fetch_current_weather` | every 15 min | `Weather.CurrentJob` | Bright Sky current conditions |
| `fetch_today_weather` | every hour | `Weather.TodayJob` | today's hours |
| `fetch_weather_forecast` | every 3 h | `Weather.ForecastJob` | forecast hours |
| `fetch_historic_weather` | 3:45 daily | `Weather.HistoricJob` | yesterday's observations, backfill of days with energy totals |
| `poll_sensors` | every 15 min | `Sensors.PollJob` | SwitchBot → `sensor_readings`, TRMNL sensor push, `sensors`/`weather` broadcast |
| `push_trmnl_widget` | every 15 min | `Trmnl.EnergyPushJob` | TRMNL energy widget |
| `aggregate_energy_samples` | 3:15 daily | `Plugs.AggregatorJob` | daily roll-up, backup, PV hours |

- **Weather.** `Ziwoas.Weather.Sync` over `BrightskyClient` writes `weather_records` (kinds
  `current`, `forecast`, `historic`, keyed by kind, location and timestamp) and broadcasts
  `{:weather_updated}` on `weather`. Without coordinates nothing is fetched.
- **Aggregation.** `Ziwoas.Plugs.Aggregator` folds each finished local day of `samples` into
  `samples_5min`, `daily_totals` and `daily_energy_summary` (in SQL), and purges raw samples older
  than 7 days. `Aggregator.backup!/3` writes `VACUUM INTO` copies to `config :ziwoas, :backup_dir`
  (`backup/` next to the database) and keeps seven. `Ziwoas.Solakon.PvHourAggregator` condenses
  the day's readings and snapshots into `solakon_pv_hours`.
- **TRMNL.** `Ziwoas.Trmnl.EnergyPayload` and `SensorPayload` build the `merge_variables`;
  `Ziwoas.Trmnl.Push` posts them once, without retry, and raises above 2 kB. The Liquid templates
  are in [`trmnl/`](trmnl/).

## Solakon control

ADR-0002. `MonitorJob` runs `Ziwoas.Solakon.Control.Tick` after each reading while
`solakon.control_enabled` is set:

1. `Control.LoadReader` reads the household: the live consumption of fresh plug measurements,
   else the guaranteed floor of the last 24 h.
2. `Control.Policy.decide` is the pure state machine: load following, surplus control, probe,
   low-SoC and thermal protection.
3. `Client.apply_control/4` writes minimum SoC (only if it differs), 46001, 46002 and the target
   in 46003 through the monitor, every tick, which re-arms the inverter's 150 s watchdog.
4. `Control.State` (`solakon_control_states`, one row) stores pause flag, the last decision that
   reached the inverter and the consecutive write failures; three failures release control.
   `Control.Outcome` is what the monitor logs.

The PV page's switches (EPS output, pausing the control) go through `Ziwoas.Solakon.Control`.

## Switching and lamps

- **Schedule.** `switch_rules` hold the switch times; `Ziwoas.Switching.Rules` and `Schedule`
  group them into time windows and single switches for the page. `ScheduleTickJob` asks
  `EdgeCalculator` for the latest edge per switchable plug between its watermark
  (`scheduler_states`) and now, skips it when a manual command came later, and makes up a missed
  edge only within the grace (`ScheduleTickJob.grace_s/0`, 10 min).
- **Commands.** `Ziwoas.Switching.Commander` publishes a plug switch over the command connection
  and logs it to `switch_commands` once sent. `Ziwoas.Lights.Commands` coerces a lamp command,
  records the optimistic state and `Ziwoas.Lights.Commander` publishes it on `govees/<key>/set`; the bridge does the rest.

## Web

Router: `lib/ziwoas_web/router.ex`. Every page is a LiveView in `live_session :default`
(`on_mount: ZiwoasWeb.Nav` assigns `@look` and `@current_path`); navigation, brand and lamp tiles
are `<.link navigate={~p"…"}>`, so moving between pages never reloads. A page's markup lives in
one `ZiwoasWeb.<Page>Components` module; shared pieces (`card`, `header`, `tile`, `input`,
`button`, `flash`, …) are in `ZiwoasWeb.CoreComponents` on felt-css classes (ADR-0005), the
Energiefluss card of dashboard and PV page in `ZiwoasWeb.Components.EnergyFlow`. Every page
title is `<.header>`.

- **Text formatting**: `ZiwoasWeb.Format` (`number/2`, `flow/2`, `eur/1`, `date/1`,
  `day_month/1`, `clock/2`) is imported into every component and LiveView; its JavaScript twin
  is `assets/js/lib/format.js`.
- **Look**: the header's toggle dispatches `ziwoas:set-look` (`assets/js/lib/look.js` sets
  `data-look` on `<html>`, the `look` cookie and the browser chrome's colour from
  `--felt-body-bg`) and pushes `"set_look"`, which `ZiwoasWeb.Nav` answers on every page. The
  server only reads the cookie (`ZiwoasWeb.Look`), and the socket's connect params carry the
  current look to every LiveView that joins later.
- **Not found**: a record the URL names raises `Ecto.NoResultsError` (`Lights.get_by_key!/1`),
  which `phoenix_ecto` turns into a 404.

| Route | LiveView | Live updates (PubSub topic) |
| --- | --- | --- |
| `/` | `DashboardLive` | `dashboard`, `solakon`; day tiles refreshed by a minute timer |
| `/solakon` | `SolakonLive` | `dashboard`, `solakon`; EPS and control switches as events |
| `/solakon/history` | `SolakonHistoryLive` | reloads every minute; `?range=24h|7d|30d` |
| `/solakon/wirtschaftlichkeit` | `EconomicsLive` | cost items and electricity prices, changeset forms |
| `/weather` | `WeatherLive` | `weather` |
| `/reports` | `ReportsLive` | none; range in the query |
| `/sensors` | `SensorsLive` | `sensors` |
| `/switches` | `SwitchesLive` | `dashboard` (plug rows), `lights` (lamp tiles); plug button, schedule editor and lamp tiles as events |
| `/lights/:key` | `LightLive` | `light_<key>`; commands (`ZiwoasWeb.LightEvents`), settings sheet |

Plain controllers: `GET /api/today`, `/api/today/summary`, `/api/history` (`ApiController`,
JSON, internal consumers only), `GET /sensors/series` (the sensor chart's data), `GET /up` and
`/up.json` (`HealthController`). In production `ZiwoasWeb.ForwardedSSL` treats a request the
reverse proxy forwarded as HTTPS (`X-Forwarded-Proto`) as HTTPS, with HSTS and Secure cookies;
plain HTTP straight to port 3000 stays HTTP.

**Hooks** (`assets/js/hooks/`, registered in `assets/js/app.js`): `EnergyFlow`, `TodayChart`,
`HistoryChart`, `LiveFreshness` (dashboard, PV page), `SolakonHistory`, `EnergyReport`,
`SensorsChart`, `LightDetail`, `SettingsSheet`. Charts are Chart.js
(`assets/vendor/chart.umd.js`), painted through `assets/js/lib/chart_theme.js` and updated in
place; canvas containers carry `phx-update="ignore"`.

**Assets**: esbuild as a standalone binary (no Node) bundles `assets/js/app.js` and
`assets/css/app.css` into `priv/static/assets/` (`mix assets.build`, `mix assets.deploy` with
`phx.digest`). felt-css comes from its CDN. Images are under `priv/static/images/`.

## Data model

Ecto migrations in `priv/repo/migrations/` own the schema. Schemas `use Ziwoas.Schema`.

| Table | Schema | Contents |
| --- | --- | --- |
| `samples` | `Plugs.Sample` | raw measurements; key `(plug_id, ts)`, `ts` in Unix seconds |
| `samples_5min` | `Plugs.Sample5min` | five-minute means; `bucket_ts` in Unix seconds |
| `daily_totals` | `Plugs.DailyTotal` | energy per plug and local day |
| `daily_energy_summary` | `EnergyReport.DailyEnergySummary` | produced, consumed, self-consumed Wh per day |
| `plug_states` | `Plugs.State` | last relay output per plug |
| `switch_rules` | `Switching.Rule` | switch times |
| `switch_commands` | `Switching.Command` | every switch sent, manual or scheduled |
| `scheduler_states` | `Switching.SchedulerState` | watermark per plug |
| `lights`, `light_states` | `Lights.Light`, `Lights.State` | lamps and their last state |
| `sensor_readings` | `Sensors.Reading` | SwitchBot readings |
| `weather_records` | `Weather.Record` | Bright Sky hours |
| `solakon_readings` | `Solakon.Reading` | 30 s readings |
| `solakon_snapshots` | `Solakon.Snapshot` | 2 min snapshots incl. the four panels |
| `solakon_pv_hours` | `Solakon.PvHour` | hourly PV means |
| `solakon_control_states` | `Solakon.Control.State` | the control's single row |
| `cost_items`, `electricity_prices` | `Economics.CostItem`, `Economics.ElectricityPrice` | ADR-0004 |

- **Timestamps** are `:utc_datetime_usec` (`inserted_at`, `updated_at`, stamped through
  `Ziwoas.Clock`) and stored as ISO 8601 with microseconds and `Z`. Compare times through typed
  fields or `type(^t, :utc_datetime_usec)`; raw SQL takes `Ziwoas.Repo.dump_time/1`, because the
  text compares like the instant only at that one width.
- **SQLite pragmas** (`config/config.exs`): WAL, `synchronous=NORMAL`, 15 s busy timeout, foreign
  keys, transactions `IMMEDIATE`, so a read-then-write transaction waits for the write lock.
- **Adoption.** `Ziwoas.Release.adopt_rails_database!/0` takes over a database the former Rails
  app left behind: it checks the tables and drops Rails' `schema_migrations` and
  `ar_internal_metadata`, so the baseline migration finds every table in place. `mix ecto.migrate`
  runs it first (`mix ziwoas.adopt`), a release through `bin/migrate` (`Release.migrate/0`).

## Release

`mix release` (`rel/`): `bin/migrate` adopts and migrates, `bin/server` starts with
`PHX_SERVER=true`. Environment: `ZIWOAS_DB`, `ZIWOAS_CONFIG`, `SECRET_KEY_BASE` (required),
`PHX_HOST`, `PORT` (default 4000), `POOL_SIZE` (5). VM flags in `rel/vm.args.eex` turn
busy-waiting off. The image needs `ca-certificates` (Req verifies TLS against the system store)
and host networking for the Govee LAN multicast.

## Tests

- ExUnit mirrors `lib/`. `mix test` creates and migrates `tmp/test.sqlite3` first.
- **Database tests** `use Ziwoas.DataCase` or `ZiwoasWeb.ConnCase`: each test runs in a
  transaction of the Ecto SQL sandbox. SQLite has one writer, so these cases refuse
  `async: true`; pure tests stay async. Processes a test starts with `$callers` share its
  connection, others need `Sandbox.allow/3` or `@moduletag :shared_sandbox`.
- **Device configs**: `test/fixtures/ziwoas.test.yml` by default, `ziwoas.inverter.yml` with an
  inverter (`Ziwoas.TestConfigs`).
- **Fakes**: `Ziwoas.FakeModbusServer` (Modbus TCP), `Ziwoas.FakeMqttBroker` (Tortoise against a
  socket), `Ziwoas.TestMqtt.record/1` (records publishes), `Ziwoas.TestClock.freeze/1`, `Req.Test`
  stubs for HTTP. Jobs take `:config` (and the aggregator `:backup_dir` or `:backup`) in their
  context.
- **Adoption** is tested against `test/fixtures/rails_schema.sql`, the frozen last Rails schema
  (`Ziwoas.RailsDatabase`, `Ziwoas.ReleaseTest`).
- LiveViews are tested with `Phoenix.LiveViewTest` (`lazy_html`): broadcast on the topic, then
  `render/1`.
