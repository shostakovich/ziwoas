<img src="priv/static/icon.png" alt="Zipfelmaus – home automation" width="120">

# ZiWoAS – Zipfelmaus Wohnungs Automatisierungs System

A project by [zipfelmaus.com](https://zipfelmaus.com).

ZiWoAS is self-hosted energy and home automation: it measures consumption and generation
through Shelly plugs (MQTT) and Fritz!DECT plugs, reads and controls the Solakon ONE inverter over
Modbus TCP, switches plugs on a schedule, controls Govee lamps, collects SwitchBot sensors and the
weather (Bright Sky) and sends widgets to TRMNL. All in one Phoenix 1.8 app with LiveView and
SQLite. The UI is in German.

## Requirements

- Erlang/OTP and Elixir in the versions from [`.tool-versions`](.tool-versions)
  (e.g. with `asdf` or `mise`). No Node needed.
- For real devices: an MQTT broker (e.g. Mosquitto), optionally a Fritz!Box, a Solakon ONE,
  a Govee API key, a SwitchBot token, TRMNL webhooks.

## Setup and start

```bash
cp config/ziwoas.example.yml config/ziwoas.yml   # adjust: location, MQTT, plugs, …
mix setup                                        # deps, database, esbuild, assets
mix phx.server                                   # http://localhost:4000
```

`config/ziwoas.yml` describes the devices and is not in the repo. Cost items and electricity
prices live in the database and are maintained under PV › Wirtschaftlichkeit
([ADR-0004](docs/adr/0004-economics-data-lives-in-the-database.md)).

| Variable | Meaning |
| --- | --- |
| `ZIWOAS_CONFIG` | Device configuration; default `config/ziwoas.yml` |
| `ZIWOAS_DB` | SQLite file; default `storage/development.sqlite3` |

Locally, prefer a configuration without real devices: with the real one, the app really switches
plugs, lamps and the inverter.

## Tests and checks

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
```

`mix test` creates and migrates `tmp/test.sqlite3`; every test runs in a transaction of the Ecto
SQL sandbox. CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs the same steps and
also builds the assets.

## Assets

esbuild runs as a standalone binary (no Node) and bundles `assets/js/app.js` with the LiveView
hooks from `assets/js/hooks/`, and `assets/css/app.css`, into `priv/static/assets/`. Chart.js lives
in `assets/vendor/`, felt-css comes from the CDN
([ADR-0005](docs/adr/0005-felt-css-as-the-ui-foundation.md)).

```bash
mix assets.setup    # fetch the esbuild binary
mix assets.build    # development (mix phx.server rebuilds on changes itself)
mix assets.deploy   # minified and digested, for a release
```

## Release and database

Ecto migrations in `priv/repo/migrations/` own the schema. A release (`mix release`) ships two
scripts:

- `bin/migrate` – adopts an old database if needed and runs all pending migrations.
- `bin/server` – starts the app with `PHX_SERVER=true`.

In a release, `ZIWOAS_DB`, `ZIWOAS_CONFIG`, `SECRET_KEY_BASE` and `PHX_HOST` are required;
optional are `PORT` (default 4000), `POOL_SIZE` (5) and `ZIWOAS_ALLOWED_HOSTS` (hosts the browser
reaches ZiWoAS under, comma-separated; without it: the host that served the page).

**Container.** The `Dockerfile` builds the release (Debian, uid 1000, port 3000, healthcheck on
`/up`, `sqlite3` for backups) and runs `bin/migrate`, then `bin/server`; `ZIWOAS_DB` and
`ZIWOAS_CONFIG` point to `/app/storage` and `/app/config`. `docker-compose.yml` is one service on
the host network (Govee answers by multicast on UDP 4002) and expects `ZIWOAS_TAG` and
`SECRET_KEY_BASE`. `.github/workflows/docker.yml` publishes images for `linux/amd64` only under an
explicit tag, never `latest`. Rehearsal and cutover: [`docs/cutover.md`](docs/cutover.md).

**Adopting an old database.** A SQLite file from the former Rails app is adopted once, on the
first `bin/migrate` (or `mix ecto.migrate` in development): `Ziwoas.Release.adopt_rails_database!/0`
checks the tables and removes Rails' migration bookkeeping, then the Ecto migrations take over. A
second run changes nothing. By hand:

```bash
ZIWOAS_DB=storage/production.sqlite3 mix ziwoas.adopt
```

Always take a backup first (`sqlite3 … ".backup …"`). The app itself backs up the database every
night into `backup/` next to the database file.

## Further reading

- [`CONTEXT.md`](CONTEXT.md) – domain vocabulary (Schaltzeit, Flanke, Regelung, Eigenverbrauch, …)
- [`docs/architecture.md`](docs/architecture.md) – how the app is built
- [`docs/adr/`](docs/adr/) – architecture decisions
- [`docs/solakon-modbus-protocol.md`](docs/solakon-modbus-protocol.md) – Modbus registers of the
  Solakon ONE
- [`docs/trmnl/`](docs/trmnl/) – Liquid templates of the TRMNL widgets
