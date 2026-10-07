# ZiWoAS moves to Elixir/Phoenix route by route, with Rails as the oracle

ZiWoAS is mostly long-lived device connections (MQTT, Modbus, Govee, Fritz!Box) and live
dashboards, run as three Ruby processes side by side: Puma, Solid Queue and the collector. That
is what the BEAM is built for: supervision trees reconnect devices, PubSub and LiveView carry
live pages, binary pattern matching reads Modbus registers, and one VM with busy-waiting off
(`+sbwt none +sbwtdcpu none +sbwtdio none`) replaces three processes on the home server. OTP
already brings `:crypto` (the Fritz login's PBKDF2), `:xmerl`, `:gen_tcp` and `JSON`.

The port is a strangler fig (issue #158): Phoenix takes over one task at a time, at parity and
with the architecture unchanged, while Rails keeps running as the reference.

- **The SQLite file is the contract.** Both apps run on the same database; Rails owns the schema
  until cutover. Ecto gets schemas, never migrations.
- **Every task has exactly one owner** (job, device connection, route), named in configuration.
  Never more than one system switches devices or writes Solakon registers.
- **The Ruby tests are the spec.** They are ported along; while Rails runs, Rails is the oracle.

Four safety nets prove each handover: **test vectors** (`script/test_vectors.rb` writes JSON
cases per calculation core, ExUnit reproduces them exactly), a **golden master**
(`script/golden_master` renders every route in both apps on a synthetic database with a frozen
clock: JSON byte-identical, HTML equal after normalisation), **shadow mode** for the collector
(a shadow database compared on `samples`, `solakon_readings`, `sensor_readings`; recorded device
traffic as replay fixtures) and a **dry run** for everything that switches (a week of logged
decisions compared with `switch_commands` and `solakon_control_states`).

| Phase | What | Way back |
| --- | --- | --- |
| 0 | Synthetic database, test vectors, golden master | – |
| 1 | Read-only Phoenix on the same database; calculation cores against the vectors | – |
| 2 | Read pages and API behind the reverse proxy, route by route | Route back to Rails |
| 3 | Jobs fetching external data (weather, sensor polling): shadow, then owner | Job back on in Rails |
| 4 | Collector ingest (MQTT, Modbus reads, Govee): shadow, then owner | Restart the Rails collector |
| 5 | Forms that write (costs, prices, time windows, rules) | Route back to Rails |
| 6 | Last: everything that switches (switching, lights, Solakon control): dry run, then owner | Owner flag back |
| 7 | Ecto migrations take the schema, Rails is removed | – |

Parity comes first, LiveView and OTP idioms after. The exception is pages with live updates
(dashboard, sensors, Solakon): they become LiveViews with Rails' markup right away, so no Turbo
Stream plumbing is built in Phoenix only to be torn out again.

Go was rejected: its single binary buys nothing for an app that runs in a container anyway, and
the code would be noticeably more verbose.

## Consequences

- Until Phase 7 a schema change is a Rails migration, `mix ziwoas.rails_fixture` and the matching
  Ecto schema; a contract test and `bin/ci` fail on drift.
- ecto_sqlite3 has no setting for Rails' `YYYY-MM-DD HH:MM:SS[.ffffff]` timestamps:
  `Ziwoas.Ecto.RailsDateTime` writes them, so string comparisons in SQL hold on mixed rows.
- Ownership lives in `config/ziwoas.yml` (`migration.owners`): per task `rails`, `shadow`/`dry_run`
  or `phoenix`, read by both apps. Rails jobs, collector components and write routes skip what
  Phoenix owns; Phoenix runs nothing that is `rails` and writes only through `Ziwoas.Repo.write/2`.
  Should the two configs disagree, an owner lease per ingest and effect task (`migration_leases`,
  a heartbeat every 30 s, stale after 60 s) lets only one app act at a time.
- Phoenix reads the database read-only. As owner it writes it through a separate writer; in shadow
  and dry run into a shadow database with Rails' schema (`ZIWOAS_SHADOW_DB`), compared by
  `script/shadow_compare`.
- Parity means Ruby's numbers and bytes: `Ziwoas.RubyNumeric` reproduces `Float#round`,
  compensated `Array#sum`, `%.Nf` and `Float#to_s`; `Ziwoas.RubyJSON` writes ActiveSupport's JSON
  bytes, floats included.
- Live pages run before the collector moves: until Phase 4, `Ziwoas.Live.*Watcher` processes
  poll the database for Rails' writes and broadcast on PubSub.
- Elixir only knows UTC and has no YAML: `tz` and `yamerl` are the two deps beyond Phoenix/Ecto;
  the jobs of Phase 3 add `req` for outbound HTTP.
- Two toolchains in CI and the cloud hook until Rails is gone. Muzak is weaker than mutant, so
  the comparison against Ruby is the stronger net until cutover; afterwards ExUnit stands alone.
