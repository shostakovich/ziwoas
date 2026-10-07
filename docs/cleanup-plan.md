# Cleanup plan: ZiWoAS as an experienced Elixir developer would have built it

After the cutover (2026-10-07, PR #159) the app is a faithful port: correct, but still shaped like
Rails. This plan removes the remaining deviations from idiomatic Phoenix 1.8 / Elixir / OTP.
Source: the audit of 2026-10-07 (three read-only reviews: domain, OTP, web; core claims
re-checked). Each finding below names its package.

## Decisions

- `/api/*` has no consumer outside this repo → the JSON API goes away (Robert, 2026-10-07).
- Nothing outside the app reads `govees/*` → the Govee MQTT contract goes away; bridge and
  lamps talk in-process (Robert, 2026-10-07).
- The Fritz bridge's Shelly-shaped MQTT status is internal too → in-process (veto: Robert).
- Degraded boot stays (`/up` 503 with the error was wanted) but becomes real: config is loaded
  once at boot, every page shows the error instead of crashing.
- Home-grown scheduler stays (no Oban, no Quantum). YAML device config stays. No new runtime
  dependencies; Mox only if a test truly needs it.
- Migrations stay as they are (they are recorded in production `schema_migrations`).
- Rails adoption code goes only in wave 4, after stable days in production (Robert gives the go).

## Target conventions (set in wave 1, followed by every slice)

- **Contexts own the Repo.** Only a context's top module (or its private submodules) calls
  `Repo`; schemas hold fields, changesets and pure predicates; web code aliases contexts, never
  schemas or `Ecto.Query`. Jobs write through context functions.
- **No presentation in `lib/ziwoas`.** The domain returns numbers, atoms, dates and structs.
  Labels, units, CSS names, colours, chart payloads and German text live in `ZiwoasWeb`.
- **PubSub per context:** `Context.subscribe/0` (or `/1` for a key) and a private `broadcast`;
  topic strings exist only inside the context; messages are `{event, payload}` with
  context-specific event atoms. `Ziwoas.Live` is removed.
- **Chart data only via LiveView:** `push_event(socket, "<hook>:data", payload)` on connected
  mount and on PubSub events; hooks only `handleEvent` and draw. No `fetch`, no `setInterval`,
  no JSON islands in the DOM, no resync event. Timers only where wall-clock time itself is the
  trigger (midnight, sliding 24 h window).
- **Ecto types:** dates are `:date`, closed string sets are `Ecto.Enum` (stored text unchanged,
  so no migration). Queries are `Ecto.Query`; raw SQL only where Ecto cannot express it
  (`VACUUM INTO`).
- **Plain functions over service objects:** no `new/1` structs wrapping one field, no
  `*Builder`/`*Presenter`/`*Calculator`/`*Loader`/`Store` names; functions on the context.
- **Errors:** clients return `{:ok, _} | {:error, reason}` with atoms/tuples/exceptions as
  reasons, not strings; no `rescue` for control flow; bang variants only at the job boundary.
- **Slow work off the LiveView process:** `assign_async` for heavy mount data,
  `start_async` for device writes.
- **Navigation:** `<.link navigate={~p"…"}>` everywhere inside the `live_session`.

## Waves

| Wave | Packages | Parallel |
| --- | --- | --- |
| 1 | F1 Foundation core · F2 Foundation web | yes, disjoint paths |
| 2 | S1 Solakon & PV · S2 Energy & Plugs · S3 Switching, Lights & Govee · S4 Weather & Sensors | yes, vertical slices |
| 3 | R Review (report only) → X Fix | sequential |
| 4 | L Rails leftovers and docs | after Robert's go |

### F1 Foundation core

- **Config lifecycle** (audit OTP #1, #5): `Application.start/2` loads once;
  `:persistent_term` holds `{:ok, config} | {:error, message}`; `Config.get/0` returns the
  config or raises `Config.Error`, `Config.fetch/0` returns the tuple. Remove lazy load, the
  per-path cache and `Config.reset/0`; tests put a loaded config through a test helper.
  Collector and Scheduler get the config through start opts.
- **Config validation** as one `embedded_schema` per section (`cast_embed`, `validate_*`,
  cross-field checks, one `traverse_errors` message listing every error). Keep the retired-key
  messages until wave 4.
- **Test seams out of production paths:** `Clock` and the MQTT publisher chosen with
  `Application.compile_env` (behaviour + test implementation); remove the per-call
  `get_env` branches, `:mqtt_recorder` arity juggling, `boot_config(load \\ …)`, the dead
  `:solakon_monitor` and `config :ziwoas, env:`.
- **Scheduler as data** (OTP #2): schedules `{:every, n, unit}` / `{:daily, ~T[…]}`, parser
  removed; jobs `{module, opts}`; `Scheduler.children(config)` starts only jobs the config
  enables (no "disabled" log every 30 s); callback `perform(opts)` without the test-only
  context keys; keep `Schedule.next_after/3` and its DST tests.
- **Supervision:** Endpoint is the last child.
- **Shared domain entry points** the slices build on (move, don't redesign):
  `Ziwoas.Plugs` facade with `latest_measurements/2` (the duplicated "latest sample per plug"
  SQL from `plugs/measurement.ex` and `switching/row.ex`, as `Ecto.Query`);
  `Ziwoas.Weather.historic_records/3` (the query written in `shading/builder.ex`,
  `sun_calendar/builder.ex`, `energy_report/weather_loader.ex`).
- **PubSub skeleton:** `subscribe/0,1` + private `broadcast` on each context
  (`Plugs`, `Solakon`, `Lights`, `Sensors`, `Weather`); old topics keep working until the
  slices switch their LiveViews; `Ziwoas.Live` deleted in wave 2.

### F2 Foundation web

- **Navigation** (web #1): layout nav, brand and lamp tiles as `<.link navigate={~p"…"}>`;
  hard-coded paths to `~p`.
- **`ZiwoasWeb.Format`** (web #10, domain #3): `number/2`, `eur/1`, `date/1`, `day_month/1`,
  `clock/2`; absorbs `Ziwoas.GermanNumber`; imported via `html_helpers`. Replace the scattered
  `Calendar.strftime` / `de_number` / `money` / `measure` / `watts` wrappers.
- **Look into the web:** `Ziwoas.Look` → `ZiwoasWeb.Look` (tokens, no hex); the look toggle as a
  client-side `JS.dispatch` like the 1.8 generator's theme toggle (cookie set client-side), no
  `PATCH /look` round trip.
- **Shared widgets** out of page modules: `tile`, `energy_flow` (with its own hook root) into
  `ZiwoasWeb.Components.*` or `CoreComponents`; `<.header>` used by every page (fix its markup
  so pages look unchanged), unused `translate_errors/2` removed.
- **Health:** one `GET /up`, JSON `{"status":"up"}` / 503 `{"status":"down","error":…}`; drop
  `/up.json`, the green/red HTML pages and the `:health` pipeline (Docker only curls `/up`).
- **404:** delete `ZiwoasWeb.NotFoundError`; `Lights.get_by_key!/1` raising
  `Ecto.NoResultsError`.
- **Degraded mode in the web:** with `Config.fetch/0` an error, every page renders a 503 page
  naming the config error (plug in `:browser` + `on_mount` halt), coordinated with F1.
- **Rails wording** in moduledocs (`application.html.erb`, `Date.current`, …).

### S1 Solakon & PV analysis

- `Ziwoas.Solakon` becomes the context: readings, snapshots, control state, history; queries
  move off `Reading`/`Snapshot`/`Control.State`; alarm labels to `Solakon.Alarms` (labels for
  the UI in the web).
- `Solakon.History` returns data only; German labels, roles and formatting move to
  `SolakonComponents`; fix the N+1 in `outlet_power_w/1` (one query for the range).
- `PvHourAggregator` as Ecto queries; delete `Repo.dump_time/1`.
- Sun & PV analysis grouped: `Ziwoas.Sun` (+ `Sun.Position` from `SunCalc`), SunCalendar and
  Shading builders become context functions returning plain structs (no closures).
- `SunChartComponents` (1289 lines) split per chart; geometry in pure
  `ZiwoasWeb.Charts.*` modules (`Plot`, `Ramp` move here), components only render;
  `co2`-style random ids replaced by an `id` attr where applicable.
- `SolakonLive`: `assign_async` for sun calendar, shading, economics overview; `start_async`
  for EPS/control writes; switches as `<button role="switch">`, `attempts` workaround gone;
  history refresh driven by `Solakon.subscribe/0` instead of a minute timer;
  `SolakonHistoryLive` and `SolakonLive` share the history via a component, not via each
  other's public functions; `SolakonHistory` hook on `push_event`.
- Modbus/Monitor: thread the transaction counter instead of `:atomics`; error tuples.

### S2 Energy & Plugs

- `Ziwoas.Energy` becomes the context for energy figures: today's balance (`EnergySummary`),
  power series, flow, live state, reports, daily summary schema. The current `Ziwoas.Energy`
  value struct becomes `Energy.Amount`. `Ziwoas.Plugs` owns samples, states, daily totals,
  measurements, roster, aggregation.
- `Plugs.Aggregator` as plain functions (`aggregate_day/3`), `SavingsCalculator` folded into
  `Economics` (`savings_eur/…`), `EnergyDeltas` without string concatenation and hand-built
  placeholders (`with_cte`/`over` or one SQL module); `DailyTotal.date`,
  `DailyEnergySummary.date` as `:date`.
- `EnergyReport`: params via an embedded-schema changeset in `ReportsLive`; flash text and
  chart payload into the web; fix the N+1 in `consumer_daily_series`.
- Dashboard: `TodayChart`/`HistoryChart` on `push_event`; summary tiles recomputed on plug
  events (throttled) plus a midnight timer; `LiveFreshness` keeps the stale display, loses the
  resync; `ReportsLive`/`EnergyReport` hook on `push_event`.
- Delete `ApiController`, the `:api` pipeline and `/api/*`.
- `Fritz.Bridge` hands readings to `Plugs` in-process (same code path as Shelly status), no
  MQTT publish, its MQTT connection removed; `DectClient` error tuples.
- `Trmnl.EnergyPayload` reads through contexts.

### S3 Switching, Lights & Govee

- `Ziwoas.Switching` facade: rules, rows, commands, schedule tick; queries off
  `Command`/`SchedulerState`; `Row` uses `Plugs.latest_measurements/2` and the measurement
  offline rule instead of its own; `Command.action/source`, `Rule.action` as `Ecto.Enum`;
  `Commander.switch` with a guard instead of `raise`.
- Govee in-process: `Govee.Bridge` updates `Lights` directly (no `govees/*` config/state
  publish, no `GoveeSubscriber`), `Lights` sends commands to the bridge directly (no
  `CommandHandler`, no `govees/+/set`); remove the extra MQTT connections; supervised tasks
  (`Task.Supervisor.async_nolink`) for Platform API calls, and none inline.
- `Govee.Types` only where the Govee wire protocol needs lenient parsing; LiveView params via
  schemaless changesets.
- `LightDetail` hook reduced to the colour wheel: tabs via `JS` commands or assigns,
  brightness/temperature as a form with `phx-debounce`; `LightLive` reads config in mount,
  not render; presentation (`plush_image`, `color_hex`) into the web.
- `SwitchesLive` without the catch-all `handle_info`; subscribes via contexts.

### S4 Weather & Sensors

- `Ziwoas.Weather` owns records and queries; `Record.kind` as `Ecto.Enum`; `Weather.Icon` and
  `dashboard_icon` file names into the web.
- `BrightskyClient`, `SwitchBotClient`, `Trmnl.Push`: `{:ok, _} | {:error, reason}`, no
  rescue on `=~ "404"`, no raise inside `Push` for an oversized payload (error tuple), callers
  match.
- `Sensors`: `create_reading/…` used by the poll job; `ReadingPresenter` split into
  `Sensors.co2_level/offline?` and web labels.
- `SensorsChart` on `push_event`; delete `SensorsController` and `/sensors/series`; the poll
  job broadcasts on `Sensors` only (not on `weather`).
- `WeatherLive`: no `String.to_integer` on client params.

### R Review, X Fix

- R reads the whole diff against `main` and reports only: blockers, should-fix, nits, each
  with file:line and a reproduction; checks the target conventions above.
- X fixes every finding, one test per finding that was red before.

### L Rails leftovers and docs (after Robert's go)

- Delete `Release.adopt_rails_database!`, `mix ziwoas.adopt` and its alias,
  `test/support/rails_database.ex`, `test/fixtures/rails_schema.sql`,
  `schema_parity_test.exs`, `timestamps_migration_test.exs`, the adoption half of
  `release_test.exs`; config shims (`migration:`, `electricity_price_eur_per_kwh`,
  `timezone`/`weather`, `solakon.enabled`) once the production yml has none of them.
- `docs/port-plan.md` and this plan removed; `architecture.md`, `README.md`, `CLAUDE.md`
  updated; `cutover.md` B.8 done; close #158.

## Working rules for subagents

- One package per agent, Opus, `isolation: "worktree"`. First check `git log -1`; if it is not
  the coordinator's branch head, `git reset --hard <sha>` given in the briefing.
- Commit in the own worktree (WIP commits are fine); the coordinator takes packages over with
  `--ff-only`, parallel packages rebase one after another.
- Paths are disjoint per package. Shared files (`router.ex`, `layouts.ex`,
  `core_components.ex`, `application.ex`, `config/*.exs`, `assets/js/app.js`, `ziwoas_web.ex`)
  get only additive, local edits in wave 2. Wave 1 public signatures are frozen for wave 2.
- Gates, each checked by exit code (`set -o pipefail`, never `| tail` alone):
  `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix test`, and `mix assets.setup && mix assets.deploy` when JS changed.
- Tests: every behaviour change has a test; LiveView tests use `has_element?` and
  `assert_push_event` rather than `html =~`; chart hooks covered by `assert_push_event`.
- Code and comments in English and sparse; UI text German. No changes to `CONTEXT.md` unless
  Robert asks. No new runtime dependencies.
- Each slice updates its part of `docs/architecture.md`.
- Behaviour visible in the UI stays the same unless the plan says otherwise; the coordinator
  walks every page in the browser after wave 2 and after X.

## Status

| Package | State |
| --- | --- |
| F1 | open |
| F2 | open |
| S1 | open |
| S2 | open |
| S3 | open |
| S4 | open |
| R / X | open |
| L | waiting for Robert's go |
