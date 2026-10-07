# ZiWoAS on Elixir/Phoenix

Strangler-fig port of the Rails app next door ([ADR-0006](adr/0006-migrate-to-elixir-phoenix.md),
issue #158). Same SQLite file, Rails as the oracle.

- **Phase 1** (done): read-only skeleton, calculation cores proven against `../test/vectors/`.
- **Phase 2** (done): Phoenix renders every route marked `ported: true` in
  `../script/golden_routes.yml` — `/api/*`, both TRMNL payloads, `/`, `/weather`, `/reports`,
  `/sensors`, `/sensors/series`, `/solakon`, `/solakon/history`, `/up`.
- **Phase 3** (done): the recurring jobs with external data — weather (Bright Sky), the
  SwitchBot sensor poll with its TRMNL sensor push, the TRMNL energy push and the nightly
  aggregator — run in shadow or as owner (see Jobs below).
- **Phase 4** (shadow first): the collector's ingest — MQTT (Shelly status, Govee
  config/state), the Solakon Modbus monitor, the Fritz!DECT bridge, the Govee bridge — as a
  supervision tree under `Ziwoas.Collector` (see Collector).
- **Who serves what** is the routes' `serve:` field, apart from parity: the reverse proxy sends a
  route to Phoenix only where it says `phoenix`. `/solakon` says `rails` until `solakon_control`
  moves (see Solakon control): Rails' page PATCHes Rails' `/solakon/eps` and `/solakon/control`
  with Rails' CSRF token, Phoenix's page switches through LiveView events.
- **Phase 5** (ported, `serve: rails`): `/solakon/wirtschaftlichkeit` with the Kostenposten and
  Strompreise (task `economics`), `/switches` with the Zeitfenster and Einzelschaltungen under
  `/plugs/:plug_id/switch_windows|switch_rules` (`switch_schedule`), `/lights/:key` with its
  settings (`light_settings`). Every write route answers like Rails, Turbo Streams included, and
  is proven by the write cases of the golden master. Handing a task over means flipping its owner
  and its routes together, page included — a form carries the CSRF token of the app that rendered
  it:
  - `economics`: page and four write routes can move together now.
  - `light_settings`: moves with `/lights/:key` and `lights` (Phase 6a, below; the validation
    refuses it alone).
  - `switch_schedule`: moves with `/switches` (Phase 6a, below). The pause and delete buttons sit
    in the page Rails renders and would post Rails' token to Phoenix.
- **Phase 6a** (dry run first): everything that switches plugs and lights — the edge-driven
  scheduler, the plug button, the lamp commands — and the controls of `/switches` and
  `/lights/:key` as LiveView events (see Switching and lights).

## Setup and run

```sh
cd elixir
mix deps.get
mix test          # builds tmp/test.sqlite3 from test/support/rails_*.sql first
mix phx.server    # reads storage/development.sqlite3, or $ZIWOAS_DB
```

Erlang/OTP and Elixir are pinned in `.tool-versions` (read by the cloud SessionStart hook and by
`erlef/setup-beam` in CI).

| Variable | Meaning |
| --- | --- |
| `ZIWOAS_DB` | SQLite file; dev default `storage/development.sqlite3` (relative to this app, the repo root once it moves there; until then set it), required in prod |
| `ZIWOAS_SHADOW_DB` | Shadow database for tasks in `shadow`/`dry_run` mode; created with the Rails schema, required once one is |
| `ZIWOAS_CONFIG` | Device config; dev default `config/ziwoas.yml` (relative to this app, as `ZIWOAS_DB`), tests `test/fixtures/ziwoas.test.yml`, required in prod |

## Tests

- `mix test` mirrors the Ruby tests. `bin/ci` runs it with `mix format --check-formatted` and
  `mix compile --warnings-as-errors` where `mix` exists; GitHub Actions always does.
- **Fixture from Rails.** `test/support/rails_fixture.rb` loads `db/schema.rb`, writes one row
  per table through ActiveRecord and dumps `priv/rails_schema.sql` (also the shadow database's
  schema, so it ships) + `test/support/rails_rows.sql`.
  After a Rails migration: `mix ziwoas.rails_fixture` (needs Ruby), then adjust the schemas.
  `bin/ci` and GitHub Actions fail on a stale fixture. `Ziwoas.RailsFixture.build!/2` deletes
  and rebuilds its file, so it builds only under `elixir/tmp/` (real path): `ZIWOAS_DB=<file>
  mix test` raises instead of wiping that file.
- **Device configs.** `test/fixtures/ziwoas.test.yml` is the default under `MIX_ENV=test`;
  `ziwoas.inverter.yml` adds a Solakon inverter. `Ziwoas.TestConfigs.file/1` names both.
- **Database per module.** `use Ziwoas.DataCase` (or `ZiwoasWeb.ConnCase, db: true`) gives a
  writable database. A disconnected render (`get/2` + `LazyHTML`) sees its rows; so does a
  connected `live/2`, because `ZiwoasWeb.Nav` calls `Ziwoas.Repo.inherit_dynamic_repo/0` in test
  (adopts the test process's dynamic repo from `$callers`; `config :ziwoas,
  inherit_dynamic_repo: true`).
- **Live updates.** Broadcast on the topic, then `render/1` (`SensorsLiveTest`). Watchers are
  tested with `repo:` pointed at the test database (`SensorsWatcherTest`).

## Porting a route

Implement it, flip `ported: true` in `script/golden_routes.yml`, run the golden master. Set
`serve: phoenix` once nothing on the page still needs Rails (forms, PATCHes, Turbo).

- **One LiveView per page** in `lib/ziwoas_web/live/`, inside `live_session :default`
  (`on_mount: ZiwoasWeb.Nav` assigns `@look` and `@current_path`; the session carries the `look`
  cookie). Render `<Layouts.app look={@look} current_path={@current_path}>`, set `:page_title`
  (Rails' `content_for :title`). Template: `ZiwoasWeb.WeatherLive`.
- **ViewComponents → function components** with the same markup and classes
  (`ZiwoasWeb.CoreComponents.card/1` = `CardComponent`). A page's partials and helpers go into one
  `ZiwoasWeb.<Page>Components` module (`ZiwoasWeb.WeatherComponents`).
- **Keep Stimulus `data-*` verbatim** — the golden master compares them. Write a JSON
  `<script>` whole from a function (`ReportsComponents.json_script/2`): the HEEx formatter
  wraps its body otherwise.
- **Stimulus controllers** are Rails' own, unchanged; a page adds its controllers to
  `@stimulus_controllers` in `ZiwoasWeb.Layouts`.
- **Domain code** under `lib/ziwoas/<seam>/`, taking `now`/`today`/`zone` as arguments. Mirror
  the Rails query (same WHERE, no added ORDER BY) where SQLite's row order feeds a float sum or
  a tie.
- **Numbers print as Ruby prints them**: `Ziwoas.RubyNumeric.to_s/1` (`Float#to_s`: `100.0`,
  `1.0e-05`), `format_g/1` (`%g`); SVG geometry through `Ziwoas.Plot` (Rails' `Plot`: one
  decimal, whole values as Integers).
- **Optional attributes as a list**: HEEx renders `class={false}` as `class=""`, so write
  `{if x, do: [class: "zero"], else: []}`.
- **Request parameters** go through Rails' parser: `Ziwoas.RubyDate.iso8601/2` is
  `Date.iso8601` (`20260329`, `2026-W14-2`, `--03-29` …).
- **JSON responses**: `Ziwoas.RubyJSON.encode!/1` with `put_resp_content_type("application/json")`
  and `send_resp/3`, never `json/2`.

## Porting a form

Add the route's write cases to `golden_routes.yml` next to `ported: true`; parity first, so plain
controllers where Rails has plain forms (LiveView `phx-change` validation comes after the
handover).

- **Contracts** are `embedded_schema` changesets built with `Ziwoas.Form` — dry-validation's
  `params` semantics on Ecto: absent required key `"is missing"`, `""` → nil, `Integer(s, 10)`
  per list element, rules only for keys whose schema step passed, messages schema-first then in
  rule order (`Form.messages/1`). `test/vectors/forms.json` pins the four contracts, `Float()`,
  `Date.iso8601`, the clock times and the decimal columns' rounding.
- **Controller semantics**: `permit` keeps only scalars of the listed keys; `head` answers
  `text/html` without a body; `ActiveModel::Type::Boolean` is `Rules.cast_boolean/1`; a blank
  string column stays `""` (`cast(…, empty_values: [])`).
- **Turbo Streams** (`ZiwoasWeb.TurboStream`): Rails' `<turbo-stream>` envelopes, rendered from
  the page's own function components (`TurboStream.component/2`); `requested?/1` is
  `respond_to`'s choice between stream and HTML. The routes sit in the `:turbo` pipeline, which
  does not `accepts`-filter.
- **Rails form markup**: `CoreComponents.rails_form/1` (`form_with`), `button_to/1` (params in
  key order), `submit/1`; `checked="checked"`/`selected="selected"` as attribute lists
  (`attr_if/2`); `field_with_errors` wrappers where ActionView adds them.
- **Writes** only inside `Ziwoas.Repo.write(task, …)` in the domain module; every write route has
  `plug ZiwoasWeb.Owned, task: …` before anything else, as Rails' `owned_by` runs first. Tests:
  `Repo.put_writer(:main, repo)` and `Ownership.override(%{task => :phoenix})`.

## Live updates

Where Rails writes, Phoenix polls: a `Ziwoas.Live.*Watcher` GenServer polls a cheap marker every
`:interval_ms` and broadcasts what Rails' broadcaster would, on a topic named like Rails' Turbo
stream. Where Phoenix owns the writing task, the task broadcasts after its own write and the
watcher stands down (`Ziwoas.Application.watchers/1`, from the boot owners).
`Ziwoas.Application` starts them under their own `Ziwoas.Live.Supervisor` unless
`config :ziwoas, live_watchers: false` (test).

| Watcher | Polls | Broadcasts | Stands down when Phoenix owns |
| --- | --- | --- | --- |
| `SensorsWatcher` | `MAX(id)` of `sensor_readings`, 5 s | `{:sensors_updated}` on `sensors`, `{:weather_updated}` on `weather` | `sensor_poll` (`Sensors.PollJob` broadcasts) |
| `DashboardWatcher` | `MAX(rowid)` of `samples`, 5 s (Rails' `BROADCAST_INTERVAL`); deltas only with a subscriber | `{:dashboard_live, deltas}` (the plugs' `LiveState::Update`s); `{:dashboard_summary}` every minute; on `dashboard` | `plug_ingest` (`live: false`: the summary beat stays; `ShellyStatusHandler` sends the deltas) |
| `SolakonWatcher` | `MAX(id)` of `solakon_readings`, 5 s | `{:solakon_reading, id}` on `solakon` (Rails' monitor beat) | `solakon_monitor` (`Solakon.MonitorJob` sends the beat) |

Owners broadcast through `Ziwoas.Live.broadcast/3`; in shadow mode nothing broadcasts and the
pages follow Rails' rows through the watchers.

`SwitchesLive` rebuilds its plug rows on `{:dashboard_live, _}`, where Rails replaces each
`sw_head_<plug>` from `DashboardBroadcaster.broadcast_switch_heads`.

**Stimulus data carriers** (`energy_flow_state`, `plug_deltas`, the Solakon-Verlauf's
`turbo-frame`): Turbo *replaces* them and the controllers react in `*TargetConnected`/`connect`;
LiveView would only patch attributes. They keep Rails' id on the first render and take
`<id>-<n>` on every update (`DashboardLive.carrier_id/2`), so morphdom swaps the element and
Stimulus reconnects. The `<turbo-frame>` stays in the markup (the normaliser unwraps it); with
Turbo gone, the LiveView reloads the frame's payload every minute, as the frame's `src` did, and
the range tabs swap it in place: they keep Rails' `href` as the fallback, `phx-click` sends
`"history_range"`, and `app.js` stops the browser following a link that has a `phx-click`.

## Ground rules

- **Rails owns the schema.** No Ecto migrations, no `ecto_repos`. Every table has a mirroring
  schema under `lib/ziwoas/<seam>/`.
- **Rails' timestamps.** `Ziwoas.Ecto.RailsDateTime` reads and writes
  `YYYY-MM-DD HH:MM:SS[.ffffff]` (fraction only when non-zero), so SQL string comparisons hold on
  mixed rows. Neither of ecto_sqlite3's `:datetime_type` options matches.
- **Read-only by default.** `Ziwoas.Repo` opens SQLite with `SQLITE_OPEN_READONLY`; writes go
  through `Ziwoas.Repo.write/2` and the task's ownership mode (see Ownership & modes).
- **Rails 8's pragmas**: WAL, `synchronous=NORMAL`, 15 s busy timeout, 64 MiB journal limit,
  128 MiB mmap.
- **One clock.** `Ziwoas.Clock.now/0,1`, `today/1`, `unix_now/0` replace every `Time.now`,
  `Time.current`, `Date.today` and `zone.now`. Frozen by `Clock.freeze/1` in
  tests (seen by processes the test starts; `config :ziwoas, clock_process_override: true`). Only the edge (controller, LiveView, task) reads
  the clock. Rails' `Date.today` is the OS zone (the container runs `TZ=Europe/Berlin`), ported
  as `Clock.today(config zone)`.
- **One config.** `Ziwoas.Config` reads the YAML Rails reads, with ConfigLoader's checks and
  messages, into structs (`Ziwoas.Config`, `Ziwoas.Plugs.Plug`, `Ziwoas.Config.Sensor`, …).
  `Config.app_config/0` caches per path in `:persistent_term`. YAML 1.1 booleans (`yes`/`on`)
  read like Psych via yamerl's `bool_ext`.
- **Ruby's numbers.** `Ziwoas.RubyNumeric`: `Float#round`, compensated `Array#sum`,
  `Array#min`, `%.Nf`, lenient `to_i`/`to_f`, `Float#to_s`, `%g`.
- **Rails' JSON bytes.** `Ziwoas.RubyJSON.encode!/1`: objects as ordered pair lists
  (`[{"a", 1}]`), floats through a port of the json gem's fpconv/Grisu2
  (`Ziwoas.RubyJSON.Float`, proven by `test/vectors/rails_json.json`), `<>&` escaped like
  ActiveSupport. Elsewhere Elixir's built-in `JSON`.
- **No asset pipeline.** No esbuild, no Tailwind; `priv/static` is served as is. Phoenix and
  LiveView ES modules come from the Hex packages through an import map
  (`ZiwoasWeb.Layouts.import_map/0`). Images, stylesheets, the Stimulus controllers, `lib/*.js` and
  `chart.min.js` sit in `priv/static/assets/` (no digest), the icons in `priv/static/`. Stimulus (`priv/static/assets/vendor/stimulus.min.js`, stimulus-rails 1.3.4) runs
  next to LiveView; `app.js` registers every `controllers/*_controller` of the import map.
- **One look.** `ZiwoasWeb.Layouts` ports the application layout (`root.html.heex` +
  `<Layouts.app>`), felt-css from its CDN like Rails; `PATCH /look` sets the `look` cookie.

## Ownership & modes

Every task has one owner, named in `config/ziwoas.yml` (`migration.owners`, documented in
`config/ziwoas.example.yml`; absent = everything `rails`). Rails reads it through
`lib/ownership.rb`, Phoenix through `Ziwoas.Ownership`; `test/vectors/ownership.json` pins both.
Owners are read at boot: after a change restart the side that gives a task up first. Rails reads
them in an initializer (`config/initializers/ownership.rb`, before Puma or Solid Queue fork, and
logs the tasks not Rails' alone); Phoenix keeps the owners it started its writers, collector and
scheduler for (`Ownership.put_boot_owners/1`) — all `rails` when the config did not load, even
if it loads later.

| Class | Modes | Tasks |
| --- | --- | --- |
| ingest | `rails` `shadow` `phoenix` | `aggregator` `weather` `sensor_poll` `solakon_monitor` `plug_ingest` `light_ingest` `fritz_bridge` `govee_bridge` |
| effect | `rails` `dry_run` `phoenix` | `trmnl_push` `switching` `lights` `solakon_control` |
| route | `rails` `phoenix` | `economics` `switch_schedule` `light_settings` |

Tasks that change hands together — both parsers refuse anything else, with the same messages:

- `solakon_control` and `solakon_monitor` are `phoenix` together or neither is (Rails' control
  tick runs inside its monitor job); `solakon_control: dry_run` needs `solakon_monitor: shadow`
  (the dry run ticks on the shadowing monitor's readings).
- `switching`, `lights`, `switch_schedule`, `light_settings` and `light_ingest` are `phoenix`
  together or none is (see Handing over under Switching and lights). Short of that, any mix of
  their other modes is fine: `switching`/`lights` in `dry_run` and `light_ingest` in `shadow`
  next to the route tasks on `rails`.

What each mode means:

| Mode | Rails | Phoenix runs | Phoenix writes the DB | Phoenix acts on devices |
| --- | --- | --- | --- | --- |
| `rails` | runs | no | nowhere | no |
| `shadow`, `dry_run` | runs | yes | shadow DB only | reads only; sends, publishes, pushes, broadcasts nothing |
| `phoenix` | skips (`owned_by`, 421 on routes) | yes | main DB | yes (holding the lease) |

- **Asking.** `Ownership.mode/1`, `runs?/1` (anything but `rails`), `owner?/1`,
  `may_write_devices?/1`, `acting?/1` (owner and holding the lease), `ensure_owner!/1` (raises
  `Ownership.NotOwnerError`, also without the lease).
- **Writing.** Only inside `Ziwoas.Repo.write(task, fn -> … end)`: it points the process at
  `Ziwoas.Repo.MainWriter` (`phoenix`, lease required) or `Ziwoas.Repo.ShadowWriter`
  (`shadow`/`dry_run`), raises for `rails`; reads inside see the same database.
  `Ziwoas.Application` starts a writer only when some task needs it. Writers begin their
  transactions `IMMEDIATE` (`default_transaction_mode`): a deferred transaction that reads and
  then writes gets `SQLITE_BUSY` at once when Rails holds the write lock, the busy timeout never
  applies. The shadow file gets `priv/rails_schema.sql` (`Ziwoas.ShadowDb`), is refused after a
  schema change, and refused at boot when it is the main database (real paths with symlinks
  resolved, or the same inode); Ecto still migrates nothing.
- **Leases.** Runtime protection against both apps acting, should their owners disagree (a side
  not restarted, a typo): table `migration_leases` (task, holder `rails`/`phoenix`,
  `heartbeat_at`; Rails' `MigrationLease`, Phoenix's `Ziwoas.Lease`). Whoever acts for an
  ingest or effect task takes or renews its lease with one conditional UPSERT, which succeeds
  only while the other holder's heartbeat is older than two intervals (60 s). Phoenix heartbeats
  every task it owns every 30 s (`Ziwoas.Lease`, started before the collector and the scheduler,
  heartbeat-checked by `held?/1`); Rails takes the lease each time a job runs or a route
  switches (`owned_by`) and from the collector's 30 s heartbeat. Refused: Rails skips the job,
  answers 503, does not start or stops the collector component; Phoenix skips the run,
  `ensure_owner!`/`Repo.write` raise, `ZiwoasWeb.Owned` answers 503 — each logged as an error.
  `shadow`/`dry_run` never take a lease, route tasks have none. A hand-over therefore pauses a
  task until the old holder's last heartbeat is 60 s old; a clean Phoenix stop hands its leases
  back at once. Tests run without leases (`config :ziwoas, leases: false`) except `LeaseTest`.
- **Devices.** Every device client calls `Ownership.ensure_owner!(task)` at its lowest level,
  right before it switches, publishes to MQTT, writes a register or pushes to TRMNL. Shadow
  connections publish nothing to the shared broker (a shadow Fritz poller only logs, a shadow
  Govee bridge never consumes `govees/+/set`).
- **Jobs.** `Ziwoas.Scheduler` runs `config :ziwoas, Ziwoas.Scheduler, jobs: [name: [task:,
  schedule:, job:]]` (local zone, DST-correct), one `Scheduler.Runner` each,
  `job.perform(%{task:, mode:, at:})` only while the task is not `rails`. A run past the next
  due instant skips it; nothing is made up after downtime, and a failed run is logged, not
  retried (Rails' `retry_on` has no counterpart; the clients retry where Rails' do).
- **Effects.** Page updates go through `Ziwoas.Live.broadcast/3` (owner only), TRMNL through
  `Ziwoas.Trmnl.Push` (`ensure_owner!` before the POST; in `dry_run`/`shadow` the payload is
  built, size-checked and logged), the nightly backup through `Aggregator.backup!/3`
  (`ensure_owner!`: a shadow run would overwrite Rails' file of the day), plug switches and lamp
  commands through `Switching.Commander` and `Lights.Commander` (dry run: logged and recorded,
  never sent; see Switching and lights).
- **One world per run.** Everything a job reads inside `Repo.write/2` comes from the database
  it writes, other tasks' tables included. In shadow mode the aggregator therefore folds the
  shadow's `samples` and `solakon_readings` (meaningful once `plug_ingest`/`solakon_monitor`
  shadow too, Phase 4), and the historic-weather backfill sees the shadow's `daily_totals`.
  The one exception is the schedule tick's input: rules and manual commands are the human's,
  read from the main database in every mode (in the shadow they would not exist); only its own
  watermark and commands live where it writes.
- **Routes.** A Phoenix route that writes or switches has `plug ZiwoasWeb.Owned, task: …`
  (421 unless `owner?/1`, 503 without the lease), the mirror of Rails' `owned_by` (421 for what
  Phoenix owns).
- **Comparing.** `script/shadow_compare --main … --shadow … --since … --until …` per table,
  keys and tolerances in its `SPECS`; rows pair with the nearest one in time. A table whose
  shadow holds no rows at all is SKIP (not shadowed); a dead shadow FAILs: a table named in
  `--tables` without shadow rows in the window, or shadow rows that stop before the window while
  main has some in it. `lights` ignores `name` and `shelly_plug_id` (the human's, never ingested).
- **Shadow phase.** A job's `shadow_offset:` delays its runs in `shadow`/`dry_run` by that many
  seconds: the shadowing Solakon monitor reads 10 s after Rails' (every 30 s), the snapshot 40 s
  after (every 2 min), so the apps never poll the inverter at the same moment;
  `shadow_compare`'s `within` is 20 s and 70 s accordingly.
- **Shadow growth.** The shadow database grows like the main one, but only the shadowed tasks
  fill it, and nothing prunes it: shadow `aggregator` with `plug_ingest` so the shadow's samples
  roll up, and start a fresh shadow file (move the old one away) after each comparison window.
- **Tests.** `Ownership.override/1` (unvalidated, seen by started processes),
  `Repo.put_writer/2`; `config :ziwoas, scheduler: false`. A job's context may carry `:config`
  (`Scheduler.Job.config/1`) and the aggregator's `:backup_dir`.

### Jobs (Phase 3)

| `recurring.yml` | Task | Phoenix job | Rails |
| --- | --- | --- | --- |
| `aggregate_energy_samples` | `aggregator` | `Plugs.AggregatorJob` (+ `Solakon.PvHourAggregator`, `Aggregator.backup!/3`) | `AggregatorJob` |
| `fetch_current_weather`, `fetch_today_weather`, `fetch_weather_forecast`, `fetch_historic_weather` | `weather` | `Weather.CurrentJob`, `TodayJob`, `ForecastJob`, `HistoricJob` over `Weather.Sync` and `Weather.BrightskyClient` | `Weather*Job`, `WeatherSync`, `BrightskyClient` |
| `poll_sensors` | `sensor_poll` | `Sensors.PollJob` over `Sensors.SwitchBotClient`, then the TRMNL sensor push | `SensorPollJob` + `TrmnlSensorPushJob` |
| `push_trmnl_widget` | `trmnl_push` | `Trmnl.EnergyPushJob` | `TrmnlPushJob` |
| `schedule_tick` (Phase 6a) | `switching` | `Switching.ScheduleTickJob` | `ScheduleTickJob` |

- Outbound HTTP is `Req` through `Ziwoas.Http` (raw bodies, Elixir's `JSON`). Tests stub every
  client with `Req.Test` under its module name (`config :ziwoas, http_stubs: true`).
- Bright Sky JSON becomes `weather_records` rows with ActiveModel's casts (`Ziwoas.RailsCast`:
  Float columns take Integers, Integer columns truncate Floats), pinned by
  `test/vectors/weather_sync.json` (recorded bodies in `../test/fixtures/files/brightsky/`);
  PV hours by `test/vectors/pv_hour_aggregator.json`.
- Backups go to `config :ziwoas, :backup_dir`, by default `backup/` next to `ZIWOAS_DB`
  (Rails' `storage/backup`).

## Collector (Phase 4)

`bin/ziwoas_collector` and the Solakon jobs as one supervision tree, `Ziwoas.Collector`
(`one_for_one`), started by `Ziwoas.Application` from the boot owners (`config :ziwoas,
collector: false` in tests). A child exists only while its task runs in Phoenix:

```
Ziwoas.Collector
├── ziwoas-phoenix-ingest   Tortoise311 connection, handler Ziwoas.Collector.MqttRouter
│                           ├── Ziwoas.Plugs.ShellyStatusHandler   plug_ingest
│                           └── Ziwoas.Lights.GoveeSubscriber      light_ingest
├── Ziwoas.Solakon.Monitor  the Modbus TCP connection               solakon_monitor
├── ziwoas-phoenix-fritz    MQTT publisher (owner only)             fritz_bridge
├── Ziwoas.Fritz.Bridge ×n  one per fritz_dect plug                 fritz_bridge
├── Ziwoas.Govee.Bridge     LAN + Platform API                      govee_bridge
├── ziwoas-phoenix-govee    govees/+/set in, state out (owner only) govee_bridge
└── ziwoas-phoenix-command  MQTT publisher (owner only)             switching, lights (Phase 6a)
```

The scheduler's `solakon_monitor` (every 30 s) and `solakon_snapshot` (every 2 min) jobs read
through the monitor. Rails' sources: `ShellyStatusHandler`, `Govees::Subscriber`,
`MqttRouter` → `lib/ziwoas/plugs`, `lights`, `collector/`; `Solakon::Client`, `MonitorJob`,
`SnapshotJob` → `lib/ziwoas/solakon/` (`Modbus` replaces rmodbus: `:gen_tcp`, FC03/06/16);
`FritzDectClient`, `FritzMqttBridge` → `lib/ziwoas/fritz/`; `lib/govees/` → `lib/ziwoas/govee/`.

| Component | `shadow` | `phoenix` |
| --- | --- | --- |
| MQTT ingest | subscribes; rows into the shadow DB; no broadcast | main DB; `{:dashboard_live, deltas}` every ≤ 5 s |
| Solakon monitor | reads, a connection per read (Rails polls the same inverter); shadow DB | keeps its connection; main DB; `{:solakon_reading, id}`; the control tick writes through it |
| Fritz bridge | polls the Fritz!Box, logs the would-be message | publishes `shellies/<plug>/status/switch:0` |
| Govee bridge | Platform API reads only: no UDP port, no datagram, no `set`, logs the would-be message | the full bridge: LAN listener on UDP 4002, `govees/+/set`, retained config/state |

- **MQTT** is `tortoise311` (pure Elixir, MQTT 3.1.1, reconnects with backoff, deps
  `gen_state_machine` + `telemetry`). `emqtt` was the alternative: MQTT 5 we don't use, and its
  `quicer` dependency is a NIF. Client ids are fixed (`ziwoas-phoenix-*`); `Ziwoas.Mqtt.publish/5`
  calls `ensure_owner!/1`. Writes keep Rails' pattern (one INSERT per message), batching comes
  after parity. Tortoise connects with a clean session once and reconnects with
  `clean_session: false` (hard-wired): the broker keeps the session and its subscriptions across
  a drop, and a second process with the same client id takes that session over. QoS 0
  messages missed while away are not replayed unless the broker queues them (Mosquitto's
  `queue_qos0_messages`, off by default).
- **Modbus** (`Ziwoas.Solakon.Modbus`, `Client`): the same registers in Rails' order, rmodbus'
  frames byte for byte (transaction ids from 1 per connection); answers read as rmodbus 2.1.3
  reads them: frame after frame until the request's transaction id (a late answer to an earlier
  request is skipped), protocol and unit id unchecked, the timeout bounding the whole search.
  Writes only as owner of `solakon_control` (see Solakon control). After a failure the monitor backs off 1 s → 60 s
  (a write the inverter refuses does not); as owner a dropped idle connection is replaced
  within the same request.
- **Fritz!Box** via Req, `:xmerl` and `:crypto`: Rails' MD5 challenge; a PBKDF2 challenge
  (`2$…`) is answered too.
- **Replay vectors** (`../test/vectors/`, from `script/test_vectors_collector.rb`):
  `shelly_status` and `govee_subscriber` (recorded MQTT messages through Rails' `MqttRouter` →
  rows and live deltas), `solakon_modbus` (register dumps → requests, decoded values, rows;
  served by `Ziwoas.FakeModbusServer` over TCP), `fritz_dect` (recorded HTTP exchanges →
  requests, readings, errors, payload bytes), `govee_lan`, `govee_messages`, `govee_bridge`
  (packets, coercions, registry from the VCR cassette, store, router). `Ziwoas.FakeMqttBroker`
  runs Tortoise against a socket.
- **On the server**: the inverter may accept few Modbus TCP clients (shadow reads open and
  close like Rails', out of phase with Rails' polls). UDP 4002: Rails' and Phoenix's bridges
  both bind it with `SO_REUSEPORT`, so while both listen the kernel splits the lamps' unicast
  replies between them and each sees only part of them. A shadow bridge binds nothing; on a
  hand-over restart Rails first (its bridge lets go of the port), then Phoenix, and back the
  other way. An owner whose bind fails (the old bridge still there) retries with backoff
  1 s → 60 s; its Platform API polls are re-armed before each poll starts, and a poll whose task
  raises, exits or throws is logged, never silently dropped. The broker sees three extra
  clients. Pages Rails still serves (`/solakon`, `/lights`, `/switches`) lose their Turbo
  updates once Phoenix owns the task feeding them, so `solakon_monitor` and `light_ingest` stay
  in shadow until those pages move (the validation ties both to them). As owner,
  `GoveeSubscriber` sends `{:light_updated, key}` on `light_<key>` (`LightLive` reloads the
  power hero, as Rails replaces `#light_power`) and on `lights` (`SwitchesLive` the tiles).

## Switching and lights (Phase 6a)

| Rails | Phoenix |
| --- | --- |
| `ScheduleTickJob` (`schedule_tick`, every minute), `Switching::EdgeCalculator#latest_edge_per_plug`, `SchedulerState`, `Command.manual_after?` | `Switching.ScheduleTickJob` (`tick/2`), `EdgeCalculator.latest_edge_per_plug/4`, `SchedulerState.advance!/2`, `Command.manual_after?/2` |
| `Switching::Commander` (Shelly over MQTT; other drivers refuse) | `Switching.Commander` |
| `Govees::Commander`, `Lights::Operations::*`, `Params`, `Contracts::Zone*`, `LightState.record_state`/`record_zone_state` | `Lights.Commander`, `Lights.Commands` |
| `PlugSwitchesController#create` | `ZiwoasWeb.PlugSwitchController` |
| `LightsController#command` | `ZiwoasWeb.LightCommandController` |
| Turbo round trips on `/switches` and `/lights/:key` | `SwitchesLive`/`LightLive` events, `ZiwoasWeb.LightEvents` |

Shading only reads (the yield map); nothing in it switches.

- **Modes.** `switching: dry_run` runs the tick in Phoenix: it decides from the main database's
  rules and manual commands, keeps its own watermark in the shadow database, logs
  `switching dry run: would publish …` and records the command there; `script/shadow_compare
  --tables switch_commands,scheduler_states` holds a week of it against Rails (`switch_commands`
  compares the schedule's rows only). Lamp commands come only from requests, so `lights:
  dry_run` has nothing to decide: its routes answer 421 like `rails`, its LiveView events do
  nothing. As owner both publish over one connection, `ziwoas-phoenix-command`; a broker that
  cannot be reached answers within 5 s (Rails: a refused connect), the route 503, the tick
  keeps that plug's watermark.
- **Guard.** `Ziwoas.Mqtt.publish/5` calls `ensure_owner!/1` before the socket; the
  commanders branch to the dry run on the mode first, so `rails` raises before anything is sent
  or written. `Ziwoas.SwitchingGuardTest` runs all three paths against a broker on a socket.
- **Decision vectors.** `../test/vectors/schedule_tick.json` (`script/test_vectors_switching.rb`):
  the real `ScheduleTickJob` tick after tick — watermarks, grace bounds to the microsecond,
  manual commands before/at/after an edge, paused rules, orphaned and non-switchable plugs, a
  plug without a driver, a refusing broker, midnight, both DST nights, another zone, three
  seeded random runs of 220 ticks — and what it published, wrote and left. They stay after the
  cutover as the regression fixture of the switching decisions.
- **Golden writes**: `plug_switch`, `plug_switch_refused`, `light_turn`, `light_zones`,
  `light_values`, `light_refused`, device commands included. `zone_states` keeps Rails' key
  order (`json_set` appends like `Hash#merge`; an Ecto map would sort); the payloads are Ruby's
  `JSON.generate` (`RubyJSON.generate!/1`, no HTML escaping — the Govee bridge and the Fritz
  bridge use it now too).
- **Pages without Turbo.** The forms keep Rails' markup and gain `phx-submit`/`phx-click` with
  `phx-value-*` (the normaliser drops them): the plug knob (`switch_plug`), the lamp forms
  (`light_command`), `+ Zeitfenster`/`+ Einzelschaltung`/edit (`new_entry`, `edit_entry`: the
  editor opens below the list or in place of the row), the editors' save and cancel
  (`save_entry`, `close_editor`), pause and delete (`set_enabled`, `delete_entry`; `app.js` asks
  `data-turbo-confirm` first), the gear (`open_settings`: the sheet in place, `save_settings`; the
  `SettingsSheet` hook tells the LiveView when the dialog closed itself). Brightness, white and
  colour stay the `light-detail` controller's `fetch` to `POST /lights/:key/command` with the
  page's token. What Stimulus changes in the browser — panels, tabs, the brightness slider —
  is `phx-update="ignore"`, the toast hides itself after 5 s on both sides. Known glitch: the
  brightness label falls back to the stored value when the hero redraws.
- **Handing over** (owners are read at boot; restart Rails first). `/switches` carries the plug
  knobs, the schedule editors and the lamp tiles, `/lights/:key` the lamp commands and the
  settings sheet, and both pages post to `POST /lights/:key/command`. So `switching`, `lights`,
  `switch_schedule`, `light_settings` and `light_ingest` flip to `phoenix` together (the
  validation refuses anything else) with these routes:
  `/switches`, `/lights/:key`, `GET /lights/:key/edit`, `PATCH|PUT /lights/:key`,
  `POST /lights/:key/command`, `POST /plugs/:plug_id/switch`, `/plugs/:plug_id/switch_windows…`,
  `/plugs/:plug_id/switch_rules…` (then `serve: phoenix` in `golden_routes.yml`).
  `light_ingest` belongs to the group because no watcher polls `light_states`: a Phoenix lamp
  page hears of the lamps only from Phoenix's own subscriber, a Rails one only from Rails'. A
  route on one side and its page on the other gets 421 (wrong owner) or a CSRF error (the other
  app's token). Way back: the five owners off `phoenix`, the proxy back.

## Solakon control (Phase 6b)

Rails' control loop (ADR-0002) as task `solakon_control`, run by `Solakon.MonitorJob` after each
reading, as Rails' monitor does. Sources: `Solakon::Control::{Policy, LoadReader, Load, Decision,
Stored, State, Tick, Outcome}` → `lib/ziwoas/solakon/control/`; `SolakonControlsController` →
`ZiwoasWeb.SolakonControlsController` + `Ziwoas.Solakon.Control`; `Solakon::Client`'s writes →
`Client.apply_control/4`, `set_eps_output/2`, `release_control/1` over `Monitor`.

- **Write guard.** `Modbus.write_single_register/6` and `write_multiple_registers/6` call
  `Ownership.ensure_owner!(:solakon_control)` right before the frame goes on the socket; the
  monitor turns the raise into `{:error, {:not_owner, mode}}`. `Control.WriteGuardTest` proves
  with a Modbus TCP fake that `rails`, `shadow` and `dry_run` send no FC06/FC16 frame through any
  path (Modbus, monitor, tick, PATCH routes, LiveView events).
- **dry_run** (needs `solakon_monitor: shadow`; the validation refuses it otherwise): every reading
  of the shadowing monitor ticks. Load (the plugs' samples) and the pause switch come from the
  main database — the switch belongs to whoever owns the PATCH route; the decision is stored in
  the shadow database's `solakon_control_states` row as if written (the row mirrors Rails'
  `paused`); nothing reaches the inverter. The decision log is the monitor's log line, Rails'
  wording: `solakon_control (dry_run): state=… target=…W load=… floor=…W soc=…% temp=…C pv=…W
  battery=…W — not sent: 46001=1, 46002=150, 46003=[0, 251]`. Compare with
  `script/shadow_compare --tables solakon_control_states` (decision exact, target ±50 W, time
  ±60 s, failure count ignored: a dry run never fails a write) and against Rails' log lines.
- **phoenix**: writes the registers through the monitor's connection, three failed writes
  release control, as Rails.
- **Vectors** (`script/test_vectors_control.rb`, regression fixtures after the cut-over):
  `solakon_policy` (`Policy.decide`: policy_test.rb's cases, chained ticks, 200 seeded random
  ones; a negative load while trimming raises in both), `solakon_modbus_writes` (rmodbus' frames
  for `apply_control!`, `set_eps_output!`, `release_control!`, refusals included),
  `solakon_control` (MonitorJob ticks end to end: register dump, samples, state row → frames per
  connection, decision, load, outcome, row; full battery, low SoC, overtemperature, stale load,
  stale decision, alarms, EPS off, control disabled, paused, read and write failures). Each runs
  as owner (everything equal) and as dry run (only the read connection, same rows).
- **UI.** `SolakonLive`'s switches are `phx-click` events (`"toggle_eps"`, `"toggle_control"`);
  the inputs keep Rails' `data-action`, and `app.js` stops their `change` before the `solakon`
  Stimulus controller PATCHes too. A `phx-value-attempt` that changes per event re-renders the
  input, so LiveView resets `checked` after a refused switch. First render golden-identical.
- **Golden write cases** `solakon_eps`, `solakon_eps_refused`, `solakon_control_pause_resume`:
  responses, DB diff and the Modbus requests per step, from a stand-in inverter on each side
  (Rails: `GoldenRender::ModbusRecorder` in `script/golden_render.rb` only; Phoenix:
  `FakeModbusServer` behind a real `Monitor`).
- **Hand-over rule:** `/solakon`, `PATCH /solakon/eps`, `PATCH /solakon/control`,
  `solakon_control` and `solakon_monitor` move together: owners to `phoenix` (both tasks; the
  validation refuses one alone), routes to `serve: phoenix`, restart Rails first. Until then
  `solakon_control: dry_run` with `solakon_monitor: shadow`.

## Deps

- `phoenix`, `phoenix_html`, `phoenix_live_view`, `bandit` — web and LiveView.
- `ecto_sql`, `ecto_sqlite3` — the shared SQLite file.
- `tz` — IANA zones for local day windows; Elixir itself only knows UTC.
- `yamerl` — reads `config/ziwoas.yml`; pure Erlang, no transitive deps (`yaml_elixir` would only
  wrap it).
- `tortoise311` — the collector's MQTT client (see Collector).
- `req` — outbound HTTP for Bright Sky, SwitchBot, TRMNL, the Fritz!Box and the Govee Platform
  API through `Ziwoas.Http`, with `Req.Test` stubs (brings `finch`/`mint`, and `jason`, which
  only Req itself uses).
- `lazy_html` (test only) — the HTML parser `Phoenix.LiveViewTest` needs.

No Jason of our own (only Req's), no asset bundler, no telemetry dashboard, no mailer.

## Release and gaps

- VM flags in `rel/vm.args.eex`: `+sbwt none +sbwtdcpu none +sbwtdio none`.
- A release needs `ZIWOAS_DB`, `ZIWOAS_CONFIG`, `SECRET_KEY_BASE`, `PHX_SERVER=true`,
  `PHX_HOST`; optional `PORT` (4000), `POOL_SIZE` (5). It raises at boot without the first
  three.
- TLS ends at the reverse proxy, as Rails' `assume_ssl` + `force_ssl`: `ZiwoasWeb.AssumeSSL`
  (prod) treats every request as HTTPS (no redirect), sends Rails' HSTS header (2 years,
  subdomains) and flags cookies `Secure`.
- The image must carry `ca-certificates` (Req verifies TLS against the system store: Bright Sky,
  SwitchBot, TRMNL, the Govee Platform API).
- Not deployed yet: no container image for Phoenix, no reverse-proxy split. The collector needs
  the broker, the inverter, the Fritz!Box and the Platform API reachable, and as Govee owner
  the LAN's multicast (host networking).
- Every route is ported. Rails keeps what is marked `serve: rails` (the Phase 5 and 6a pages
  until their owners flip, `/solakon` until `solakon_control` flips, the proxy's `/up`;
  Phoenix answers its own `/up` like `rails/health#show`).
- Phoenix's own pages load no Turbo: on `/switches` and `/lights/:key` the controls are
  LiveView events (Switching and lights).
- Known divergence: a schedule form whose time arrives as a list (`switch_window[on_at_time][]=…`)
  crashes Rails' re-render (500); Phoenix answers 422 without echoing it. Not a golden case.
