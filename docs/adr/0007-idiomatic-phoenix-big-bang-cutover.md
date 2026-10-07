# ZiWoAS becomes idiomatic Phoenix and replaces Rails in one cutover

**Status:** Accepted. Supersedes [ADR-0006](0006-migrate-to-elixir-phoenix.md).

ADR-0006 moved ZiWoAS to Elixir/Phoenix as a strangler fig: both apps on one SQLite file, Rails
owning the schema and acting as the oracle, every task handed over through an ownership switch,
proven by test vectors, a golden master, shadow databases and dry runs. That bridge did its job.
On a copy of the production database the port rendered every route like Rails (golden master
153/153), reproduced all 2688 vector cases, and showed no difference in content while running
live. Parity is proven.

The bridge itself had grown to some 49,000 lines: owner leases, shadow writers, database
watchers, Rails' timestamp format, Ruby's float printing and JSON bytes, Turbo Streams, Rails'
form markup. All of it exists only so that two apps can run side by side, and it would have to be
operated, step by step, by one person on one home server.

ZiWoAS therefore drops the parallel run. Rails keeps running unchanged until the cutover; the
port is reshaped into an ordinary Phoenix 1.8 application — "the Phoenix way" — and replaces
Rails in a single step at the end.

- **No bridge.** Ownership, leases, shadow database, watchers, golden master and test vectors
  are removed without replacement. ExUnit tests on the Elixir code are the safety net.
- **Idiomatic Phoenix.** Ecto migrations, `:utc_datetime_usec` timestamps with `inserted_at`,
  changesets with German messages, `core_components` in the 1.8 style on felt-css classes,
  LiveView events instead of Turbo, LiveView hooks instead of Stimulus, esbuild for assets, the
  Ecto SQL sandbox for tests.
- **Big bang.** One release, one container, one switch-over, rehearsed beforehand.

The alternative, finishing the strangler fig phase by phase, was rejected: every remaining phase
(collector, switching, Solakon control) would have needed its own hand-over with leases and dry
runs, and the bridge code would only have been torn out afterwards. With parity already proven,
the remaining risk is the switch-over itself, which a rehearsal covers better than a bridge.

## Consequences

- **Ecto owns the schema.** The migrations in `priv/repo/migrations/` start from a baseline that
  reproduces Rails' last schema (`create_if_not_exists`), then normalise its drift and rewrite
  the timestamps. A schema change is an Ecto migration, nothing else.
- **Adoption, not import.** The production file stays where it is. On first start
  `Ziwoas.Release.adopt_rails_database!/0` (run by `bin/migrate` and, in development, by
  `mix ecto.migrate` through `mix ziwoas.adopt`) checks Rails' tables and drops Rails' migration
  bookkeeping; the migrator then takes over. A second run is a no-op.
- **No Ruby compatibility.** Numbers, JSON and dates follow Elixir's standard library, not Ruby's.
  The `/api/*` responses have only internal consumers and may change format; the TRMNL payloads
  stay within TRMNL's 2 kB limit, which their tests check.
- **A leftover `migration:` block** in `config/ziwoas.yml` is ignored with a warning.
- **Dress rehearsal before the cutover**: adoption and migration on a fresh production dump, with
  timing, every page, LiveView through the real host name, the container for both architectures,
  and a read-only MQTT probe.
- **Way back**: the cutover starts from a `.backup` of the database and keeps the last Rails image.
  Going back means stopping Phoenix, restoring the backup and starting that image; data written
  since the cutover is lost.
- `main` is frozen for the duration of the reshaping; hotfixes are ported by hand.
