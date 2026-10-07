# Architecture

ZiWoAS is one Phoenix 1.8 application on one SQLite file. Device connections, recurring jobs
and the web endpoint run in the same VM under `Ziwoas.Application`. Domain vocabulary is in
[`CONTEXT.md`](../CONTEXT.md), decisions are in [`adr/`](adr/).

## Conventions

- **Contexts own the Repo.** Only a context's top module (or its private submodules) calls
  `Repo`; schemas hold fields, changesets and pure predicates; web code aliases contexts, never
  schemas or `Ecto.Query`. Jobs write through context functions.
- **No presentation in `lib/ziwoas`.** The domain returns numbers, atoms, dates and structs.
  Labels, units, CSS names, colours, chart payloads and German text live in `ZiwoasWeb`.
- **PubSub per context:** `Context.subscribe/0` (or `/1` for a key) and a private `broadcast`;
  topic strings exist only inside the context; messages are `{event, payload}` with
  context-specific event atoms.
- **Chart data only via LiveView:** `push_event(socket, "<hook>:data", payload)` on connected
  mount and on PubSub events; hooks only `handleEvent` and draw. No `fetch`, no `setInterval`,
  no JSON islands in the DOM, no resync event. Timers only where wall-clock time itself is the
  trigger (midnight, sliding 24 h window). Accepted exception: the energy-flow card's
  `data-state`, live state diffed into an attribute the `EnergyFlow` hook reads in `updated()`.
- **Ecto types:** dates are `:date`, closed string sets are `Ecto.Enum`. Queries are
  `Ecto.Query`; raw SQL only where Ecto cannot express it (`VACUUM INTO`).
- **Plain functions over service objects:** no `new/1` structs wrapping one field, no
  `*Builder`/`*Presenter`/`*Calculator`/`*Loader`/`Store` names; functions on the context.
- **Errors:** clients return `{:ok, _} | {:error, reason}` with atoms, tuples or exceptions as
  reasons, not strings; no `rescue` for control flow; bang variants only at the job boundary.
- **Slow work off the LiveView process:** `assign_async` for heavy mount data, `start_async`
  for device writes.
- **Navigation:** `<.link navigate={~p"…"}>` everywhere inside the `live_session`.

## Supervision tree

```
Ziwoas.Supervisor (one_for_one)
├── Ziwoas.Repo                 SQLite (ecto_sqlite3)
├── Phoenix.PubSub              Ziwoas.PubSub: live updates for the pages
├── Ziwoas.Collector            device connections (see Collector)
├── Ziwoas.Scheduler            recurring jobs (see Scheduler)
└── ZiwoasWeb.Endpoint          Bandit, last: it serves what the others started
```

`Ziwoas.Application.start/2` loads `config/ziwoas.yml` once and keeps the result
(`Ziwoas.Config.put/1`). If it does not load, the error is logged and the app serves pages
without the collector or the scheduler; `Config.fetch/0` answers the error. Collector and
scheduler get the config as their start option `config:`. Tests start neither
(`config :ziwoas, collector: false, scheduler: false` in `config/test.exs`, read at compile
time).

## Configuration

- **`config/ziwoas.yml`** (not in the repo; template `config/ziwoas.example.yml`) describes the
  devices: location, MQTT, plugs, Fritz!Box, Solakon, Govee, SwitchBot sensors, TRMNL webhooks.
  `Ziwoas.Config` reads it with `yamerl` and casts it into one embedded schema per section
  (`Ziwoas.Config` with `Ziwoas.Location`, `Ziwoas.Plugs.Plug`, `Config.Mqtt`, …; lenient
  scalar types in `Config.Types`). A config that does not validate is one message listing every
  error with its path (`plugs[1].role must be one of producer, consumer; …`). The loaded
  result lives in `:persistent_term`: `Config.fetch/0` gives `{:ok, config}` or
  `{:error, message}`, `Config.get/0` the config or raises `Config.Error`.
  `Config.plug_roster/1` gives the **plug roster**. Keys no schema knows are ignored, keys
  retired since the cutover among them; only `trmnl:` refuses unknown keys.
- **Cost items and electricity prices** live in the database (ADR-0004), maintained on
  `/solakon/wirtschaftlichkeit`.
- **Paths**: `ZIWOAS_CONFIG` and `ZIWOAS_DB` (`config/runtime.exs`). Development defaults to
  `config/ziwoas.yml` and `storage/development.sqlite3`, tests to
  `test/fixtures/ziwoas.test.yml` and `tmp/test.sqlite3`. A release needs both variables.
- **Time**: `Ziwoas.Clock` is the only source of "now" (`now/0,1`, `today/1`, `unix_now/0`). Its
  source is chosen at compile time (`config :ziwoas, :clock`): `DateTime`, in tests
  `Ziwoas.TestClock`, which can freeze it. Local days and zones come from `tz`
  (`Ziwoas.LocalDay`, `Ziwoas.Location`); Elixir itself only knows UTC.
- **Outbound HTTP**: `Req` via `Ziwoas.Http` (Bright Sky, SwitchBot, TRMNL, Fritz!Box, Govee
  Platform API). Bodies stay raw and each client decodes its own answers. Bright Sky, SwitchBot
  and TRMNL answer `{:ok, _} | {:error, reason}`, the reason an atom, a tuple
  (`{:http_status, 500}`) or Req's exception. In tests every client
  is a `Req.Test` stub under its module name (`config :ziwoas, http_stubs: true`, compile time).
- **Live updates**: each context owns its PubSub topic. `Ziwoas.Plugs.subscribe/0`
  (`{:live, deltas}`) and `Ziwoas.Plugs.subscribe(:aggregated)` (`{:aggregated, date}`),
  `Ziwoas.Solakon.subscribe/0` (`{:reading, reading}`, `{:snapshot, snapshot}`),
  `Ziwoas.Lights.subscribe/0,1` (`{:updated, key}`), `Ziwoas.Sensors.subscribe/0`
  (`{:polled, instant}`), `Ziwoas.Weather.subscribe/0` (`{:synced, date}`). The topic
  strings exist only inside the contexts.

## Collector

`Ziwoas.Collector` (`one_for_one`, high restart intensity so a crash-looping connection never
takes the endpoint down). It starts only the children the configuration asks for:

```
Ziwoas.Collector
├── ziwoas-phoenix-ingest    MQTT: Ziwoas.Collector.MqttRouter
│                            └── Ziwoas.Plugs.ShellyStatusHandler
├── Ziwoas.Solakon.Monitor   the Modbus TCP connection to the inverter
├── Ziwoas.Fritz.Bridge ×n   one per fritz_dect plug, recording in-process
├── Ziwoas.Govee.Tasks       Task.Supervisor for the bridge's Platform API calls
├── Ziwoas.Govee.Bridge      LAN (UDP 4002) + Platform API, in-process with Ziwoas.Lights
└── ziwoas-phoenix-command   MQTT publisher: plug switches
```

- **MQTT** is `tortoise311` (MQTT 3.1.1, QoS 0), wrapped by `Ziwoas.Mqtt`: `connection_spec/4` for
  a supervised connection, `publish/4` for a message, through the publisher chosen at compile
  time (`config :ziwoas, :mqtt_publisher`: `Mqtt.Broker`, in tests `Ziwoas.TestMqtt`). Tortoise
  reconnects with backoff (1 s to 60 s). Client ids are fixed, so two instances must not share
  a broker.
- **Plugs.** `Ziwoas.Plugs` owns samples, relay states, five-minute means and daily totals and
  answers every query on them (`latest_measurements/2,3`, `energy_wh/3`, `mean_power/4`,
  `samples_5min/2`, `daily_totals/2,3`, …); the counters' plausibility-capped steps are one
  Ecto query (`Plugs.EnergyDeltas`, window functions). Every reading goes through
  `Ziwoas.Plugs.Ingest`: a `samples` row (and `plug_states` when it carries an `output`), and a
  live delta per plug, sent at most every 5 s through `Plugs.notify_live/1`.
  Shelly plugs report `<prefix>/<plug>/status/switch:0` to `ShellyStatusHandler`; Fritz!DECT
  plugs are polled by `Ziwoas.Fritz.Bridge` through `Ziwoas.Fritz.DectClient` (AHA HTTP, MD5 or
  PBKDF2 challenge, `:xmerl`, `:crypto`; `{:error, reason, client}` with an atom, a tuple or
  Req's exception), which hands each reading to its own `Ingest` in-process, no MQTT.
- **Energy.** `Ziwoas.Energy` turns plug data into energy figures: today's balance
  (`today/2`, `%Energy.Balance{}`), the live picture with its energy flow (`live_state/3`),
  power series (`power_series/4`, `power_by_plug/4`), the daily summaries (`summarize_day/3`,
  `daily_summaries/0,2`, table `daily_energy_summary`) and the report over a range
  (`report/2`). Amounts are `Energy.Amount` (Wh). `Ziwoas.Economics` prices them
  (`savings_eur/3`, `total_savings_eur/2`, `overview/1`).
- **Lamps.** `Ziwoas.Govee.Bridge` talks to `Ziwoas.Lights` in-process, no MQTT: it loads the
  lamps from the Platform API (`PlatformApi`, `DeviceRegistry`) and hands each to
  `Lights.put_lamp/1`, discovers and polls them on the LAN (`Lan`, multicast
  239.255.255.250:4001, replies on UDP 4002, commands to 4003), keeps each lamp's state
  (`States`) and hands a changed one to `Lights.put_state/2`, which writes
  `lights`/`light_states` and tells `Lights`' subscribers. A command is
  `Bridge.command(key, verb)`, a call from `Lights`: `CommandRouter` (pure) sends it over the LAN
  at once or through the cloud; every Platform API call (bootstrap, polls, clarifications,
  controls) runs under `Ziwoas.Govee.Tasks` (`Task.Supervisor.async_nolink/2`), and an API
  control's optimistic state is recorded only once the call succeeded. `Govee.Types` is the
  lenient parsing of the wire (LAN replies, API states). The LAN multicast needs host
  networking.
- **Inverter.** `Ziwoas.Solakon.Monitor` holds the one Modbus TCP connection; every read and
  write goes through it, so requests never interleave. `Ziwoas.Solakon.Modbus` speaks FC03, FC06
  and FC16 on `:gen_tcp`; its connection (`%Modbus{}`) carries the transaction id, which every
  request moves on and hands back. `Ziwoas.Solakon.Client` knows the registers
  ([`solakon-modbus-protocol.md`](solakon-modbus-protocol.md), skill `solakon-modbus`) and
  threads that connection through a reading's many reads. After a failure the monitor backs off
  1 s → 60 s; a reused connection that fails is retried once on a fresh one.

## Scheduler

`Ziwoas.Scheduler` runs one `Ziwoas.Scheduler.Runner` per job of `Scheduler.jobs/1`, the table
below, and only the jobs the config enables. Schedules are data on the local wall clock of
`location.timezone` (`Ziwoas.Scheduler.Schedule`: `{:every, 30, :second}`,
`{:every, 3, :hour}`, `{:daily, ~T[03:15:00]}`), correct across DST. A job is
`{module, opts}`; the module implements `Ziwoas.Scheduler.Job.perform/1` and gets its opts
(always `:config`) plus the due instant as `:at`. A run that overlaps the next due instant
skips it, nothing is made up after downtime, and a failure is logged, not retried.

| Job | Schedule | Module | Runs when | Does |
| --- | --- | --- | --- | --- |
| `solakon_monitor` | every 30 s | `Solakon.MonitorJob` | `solakon.monitoring_enabled` | reading → `solakon_readings`, control tick, `Solakon` event |
| `solakon_snapshot` | every 2 min | `Solakon.SnapshotJob` | `solakon.monitoring_enabled` | full register snapshot → `solakon_snapshots`, `Solakon` event |
| `schedule_tick` | every minute | `Switching.ScheduleTickJob` | a switchable plug | switches due edges (ADR-0001) |
| `fetch_current_weather` | every 15 min | `Weather.CurrentJob` | coordinates | Bright Sky current conditions |
| `fetch_today_weather` | every hour | `Weather.TodayJob` | coordinates | today's hours |
| `fetch_weather_forecast` | every 3 h | `Weather.ForecastJob` | coordinates | forecast hours |
| `fetch_historic_weather` | 3:45 daily | `Weather.HistoricJob` | coordinates | yesterday's observations, backfill of days with energy totals (also after a failed yesterday) |
| `poll_sensors` | every 15 min | `Sensors.PollJob` | SwitchBot and sensors | SwitchBot → `sensor_readings`, `Sensors` event, TRMNL sensor push |
| `push_trmnl_widget` | every 15 min | `Trmnl.EnergyPushJob` | `trmnl.energy_webhook_url` | TRMNL energy widget |
| `aggregate_energy_samples` | 3:15 daily | `Plugs.AggregatorJob` | always | daily roll-up, backup (into `backup_dir`), PV hours |

- **Weather.** `Ziwoas.Weather` owns `weather_records` (`kind` an `Ecto.Enum` of `:current`,
  `:forecast`, `:historic`, keyed by kind, location and timestamp): it stores
  (`replace_current/2`, `put_forecast/2`, `put_historic/2`, each in one transaction) and answers
  the queries; `Weather.historic_records/3` is the one query for observations in a time range.
  `Weather.Sync` fetches through `BrightskyClient` (a 404 for a date ends the range), stores
  through `Weather`, and tells `Weather`'s subscribers; a failed sync is logged and tells nobody.
  Icon file names and German labels are the web's (`ZiwoasWeb.WeatherIcon`).
- **Sensors.** `Ziwoas.Sensors` owns `sensor_readings` (`create_reading/3`, the queries) and
  what a reading means: `co2_level/1`, `battery_low?/1`, `offline?/2`, `age_s/2`. `PollJob`
  stores through it, then tells `Sensors`' subscribers (the Sensoren and Wetter pages).
- **Aggregation.** `Ziwoas.Plugs.aggregate/3` (`Plugs.Aggregator`, plain functions) folds each
  finished local day of `samples` into `samples_5min` and `daily_totals` (Ecto queries over
  `EnergyDeltas`, inserted in SQLite) and `daily_energy_summary` (`Energy.summarize_day/3`, in the
  same transaction), purges raw samples older than 7 days and tells `Plugs.subscribe(:aggregated)`'s subscribers
  `{:aggregated, today}`. `Plugs.backup!/3` writes `VACUUM INTO` copies to `config :ziwoas, :backup_dir`
  (`backup/` next to the database) and keeps seven. `Ziwoas.Solakon.PvHourAggregator` condenses
  the day's readings and snapshots into `solakon_pv_hours` (Ecto queries, grouped by the local
  clock hour).
- **TRMNL.** `Ziwoas.Trmnl.EnergyPayload` and `SensorPayload` build the `merge_variables` (the
  e-ink display's text wire format, read through the contexts); `Ziwoas.Trmnl.Push` posts them
  once, without retry, logs the outcome and answers `{:ok, :sent | :skipped}` or
  `{:error, reason}`, `{:payload_too_large, bytes}` above 2 kB. The Liquid templates are in
  [`trmnl/`](trmnl/).

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
   `Ziwoas.Solakon.Control` reads and writes that row. `Control.Outcome` is what the monitor logs.

The PV page's switches go through the context: `Ziwoas.Solakon.set_eps_output/2` (the outdoor
socket, through the monitor) and `set_control_active/2` (pausing the control).

## Solakon and PV analysis

`Ziwoas.Solakon` is the inverter's context: readings, snapshots and PV hours, the decoded status
(`Solakon.Alarms` turns the status and alarm registers into condition atoms; the German lines
are in `ZiwoasWeb.SolakonComponents`), the control's switches and the Solakon-Verlauf
(`Solakon.history/3`, a `Solakon.History` of power series in W, the energy balance and the
outlet's mean power; one query for the snapshots, at most one more for readings standing in for a
missing active power). The domain returns numbers; labels, units and the chart payload are web.

- **Sun**: `Ziwoas.Sun` answers position, sunrise, sunset, daytime and a day's path for a
  location; `Sun.Position` is the NOAA computation. Without coordinates there is no sun and it is
  always day.
- **Sun calendar**: `Ziwoas.SunCalendar.year/3` builds a year of strips (PV power, irradiance,
  cloud cover per day × local hour), the daily energy and the sun lines (`SunCalendar.SunLines`);
  before the first PV hour the producer plugs' five-minute energy stands in.
- **Shading**: `Ziwoas.Shading.report/2` puts every PV hour against the station's irradiance and
  the sun's position: the yield map (`Shading.YieldMap`, with `SunPaths`), the monthly profiles
  (`DailyProfiles`) and the panel comparison (`PanelCurves`).
- **Charts**: the SVG geometry lives in pure modules under `ZiwoasWeb.Charts` (`Plot`, `Ramp`,
  `SunCalendar`, `YieldMap`, `DailyProfiles`, `PanelCurves`, `Text`); one component per chart
  under `ZiwoasWeb.Components` (`SunCalendar`, `Shading` with `YieldMap`, `DailyProfiles`,
  `PanelCurves`, parts in `ChartParts`) only renders it.

## Switching and lamps

- **Schedule.** `switch_rules` hold the switch times; `Ziwoas.Switching` is the context (rules
  and their forms, the page's `rows/3`, commands, the tick's watermarks), `Schedule` groups the
  rules into time windows and single switches for the page. `Rule.action`,
  `Command.action` and `Command.source` are `Ecto.Enum`s over the stored text. `ScheduleTickJob` asks
  `Edges` for the latest edge per switchable plug between its watermark
  (`scheduler_states`) and now, skips it when a manual command came later, and makes up a missed
  edge only within the grace (`ScheduleTickJob.grace_s/0`, 10 min).
- **Commands.** `Switching.switch/4` (`Commander`, guarded to `:on`/`:off` and
  `:manual`/`:schedule`) publishes a plug switch over the command connection and logs it to
  `switch_commands` once sent; errors are tuples. `Lights.command/3` casts a lamp command's
  parameters with a schemaless changeset, hands the verb to `Govee.Bridge.command/3` and records
  the optimistic power and zone bits.

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
| `/` | `DashboardLive` | `Plugs` (`{:live, deltas}`; `subscribe(:aggregated)`: `{:aggregated, date}`), `Solakon` (`{:reading, _}`); day tiles recomputed on plug events at most once a minute and at local midnight; charts as `"today_chart:data"` (also hourly, the 24 h window sliding), `"today_chart:deltas"`, `"history_chart:data"` |
| `/solakon` | `SolakonLive` | `Plugs`, `Solakon`; sun calendar, shading and Wirtschaftlichkeit by `assign_async`; EPS and control switches as events, written by `start_async` |
| `/solakon/history` | `SolakonHistoryLive` | `Solakon` (a snapshot refreshes it); `?range=24h|7d|30d` |
| `/solakon/wirtschaftlichkeit` | `EconomicsLive` | cost items and electricity prices, changeset forms |
| `/weather` | `WeatherLive` | `Weather` (`{:synced, date}`), `Sensors` (`{:polled, instant}`, the outdoor sensor) |
| `/reports` | `ReportsLive` | none; range in the query (`ZiwoasWeb.ReportRange`, an embedded schema); charts as `"energy_report:data"` (`ZiwoasWeb.Charts.EnergyReport`) |
| `/sensors` | `SensorsLive` | `Sensors` (`{:polled, instant}`); chart data as `"sensors_chart:data"` |
| `/switches` | `SwitchesLive` | `Plugs` (plug rows), `Lights` (lamp tiles); plug button (`start_async`), schedule editor and lamp tiles as events |
| `/lights/:key` | `LightLive` | `Lights` for its key; commands (`ZiwoasWeb.LightEvents`), sliders as debounced forms, tabs as an assign, settings sheet |

The one plain controller: `GET /up` (`HealthController`:
`{"status":"up"}`, or 503 with the config error). Without a loaded device config every page
is a 503 naming the error (`ZiwoasWeb.Plugs.RequireConfig` in `:browser`). In production `ZiwoasWeb.ForwardedSSL` treats a request the
reverse proxy forwarded as HTTPS (`X-Forwarded-Proto`) as HTTPS, with HSTS and Secure cookies;
plain HTTP straight to port 3000 stays HTTP.

**Hooks** (`assets/js/hooks/`, registered in `assets/js/app.js`): `EnergyFlow`, `TodayChart`,
`HistoryChart`, `LiveFreshness` (dashboard, PV page), `SolakonHistory`, `EnergyReport`,
`SensorsChart`, `LightDetail` (the colour wheel only), `SettingsSheet`. `TodayChart`, `HistoryChart`,
`EnergyReport` and `SensorsChart` only draw what their LiveView pushes (`push_event` on
connected mount and on PubSub events); they fetch nothing and keep no timer. The dashboard's and
the report's payloads are built in the web (`ZiwoasWeb.Charts.Dashboard`,
`ZiwoasWeb.Charts.EnergyReport`). `LiveFreshness` only dims the page once the beats stop; a
rejoined LiveView pushes its charts afresh. The Solakon-Verlauf is `ZiwoasWeb.SolakonHistoryComponent`, shared by both Solakon pages:
it pushes `"solakon_history:data"` (`%{range, times, datasets}`, times in epoch ms) on connect,
on a range tab and on every stored snapshot, and `SolakonHistory` only draws it. Charts are Chart.js
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
| `daily_energy_summary` | `Energy.DailySummary` | produced, consumed, self-consumed Wh per day; `date` a `:date` (ISO text, as in `daily_totals` and `electricity_prices`) |
| `plug_states` | `Plugs.State` | last relay output per plug |
| `switch_rules` | `Switching.Rule` | switch times |
| `switch_commands` | `Switching.Command` | every switch sent, manual or scheduled |
| `scheduler_states` | `Switching.SchedulerState` | watermark per plug |
| `lights`, `light_states` | `Lights.Light`, `Lights.State` | lamps and their last state |
| `sensor_readings` | `Sensors.Reading` | SwitchBot readings |
| `weather_records` | `Weather.Record` | Bright Sky hours; `kind` as `Ecto.Enum`, stored as text |
| `solakon_readings` | `Solakon.Reading` | 30 s readings |
| `solakon_snapshots` | `Solakon.Snapshot` | 2 min snapshots incl. the four panels |
| `solakon_pv_hours` | `Solakon.PvHour` | hourly PV means |
| `solakon_control_states` | `Solakon.Control.State` | the control's single row |
| `cost_items`, `electricity_prices` | `Economics.CostItem`, `Economics.ElectricityPrice` | ADR-0004 |

- **Timestamps** are `:utc_datetime_usec` (`inserted_at`, `updated_at`, stamped through
  `Ziwoas.Clock`) and stored as ISO 8601 with microseconds and `Z`. Compare times through typed
  fields or `type(^t, :utc_datetime_usec)`: the text compares like the instant only at that one
  width.
- **SQLite pragmas** (`config/config.exs`): WAL, `synchronous=NORMAL`, 15 s busy timeout, foreign
  keys, transactions `IMMEDIATE`, so a read-then-write transaction waits for the write lock.
- **Migrations** start from a baseline that reproduces the schema the former Rails app left
  behind (`create_if_not_exists`), then normalise it. They are recorded in production's
  `schema_migrations`: never edit or delete one, add a new one. A release migrates through
  `bin/migrate` (`Ziwoas.Release.migrate/0`).

## Release

`mix release` (`rel/`): `bin/migrate` migrates, `bin/server` starts with
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
- **The app's config**: the test fixture, loaded at boot. `Ziwoas.TestConfigs.put/1` makes
  another config (or `{:error, message}`) the one `Config.get/0` answers until the test ends;
  such a test module is not async.
- **Fakes**: `Ziwoas.FakeModbusServer` (Modbus TCP), `Ziwoas.FakeMqttBroker` (Tortoise against a
  socket), `Ziwoas.TestMqtt.record/1` (records publishes), `Ziwoas.TestClock.freeze/1`, `Req.Test`
  stubs for HTTP. Jobs are called with their opts (`config:`, the monitor jobs `monitor:`); the
  aggregator backs up only with a `backup_dir:`.
- **Migrations** run on an empty file in `Ziwoas.MigrationsTest` (`Ziwoas.TestMigrations`).
- LiveViews are tested with `Phoenix.LiveViewTest` (`lazy_html`): broadcast on the topic, then
  `render/1`.
