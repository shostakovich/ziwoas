# CLAUDE.md – ZiWoAS

Self-hosted energy and home automation: Solakon inverter, Shelly plugs, Fritz!Box DECT,
Govee lights, sensors, weather. Domain vocabulary lives in [`CONTEXT.md`](CONTEXT.md),
decisions in [`docs/adr/`](docs/adr/).

## Setup

Phoenix 1.8 · LiveView · Ecto + SQLite · Bandit. Erlang/OTP and Elixir are pinned in
[`.tool-versions`](.tool-versions).

| Path | What |
| --- | --- |
| `lib/ziwoas/` | Domain, device clients, collector and scheduler; `lights/`, `plugs/`, `switching/`, `sensors/`, `energy_report/`, `economics/`, `solakon/` are the functional seams |
| `lib/ziwoas_web/` | Router, controllers, LiveViews, components |
| `config/ziwoas.yml` | **Not in the repo** — device config incl. the plug list. Template: `config/ziwoas.example.yml`, tests use `test/fixtures/ziwoas.test.yml`. Cost items and the electricity price live in the database instead (ADR-0004) |
| `priv/static/` | Hand-maintained CSS, JS and images, served as they are (no asset bundler yet) |
| `test/` | ExUnit mirroring `lib/`; `test/support/` holds the cases and the test database fixture |

`mix deps.get`, then `mix phx.server`. Paths default to `config/ziwoas.yml` and
`storage/development.sqlite3`; `ZIWOAS_CONFIG` and `ZIWOAS_DB` override them
(see [`config/runtime.exs`](config/runtime.exs)).

Cloud sessions (Claude Code on the web) are set up by the SessionStart hook
[`.claude/hooks/session-start.sh`](.claude/hooks/session-start.sh). It still prepares the
removed Rails app and is being switched over. It is a no-op outside a remote container.

Real data only exists on the home server (Docker). Local SQLite is not a copy of production:
"empty locally" doesn't mean empty.

## Conventions

- **The port is being reshaped into idiomatic Phoenix** (plan in issue #158). Parity with the
  former Rails app is no longer a goal; [`docs/elixir-port.md`](docs/elixir-port.md) describes
  the port as it was built and is rewritten along the way.
- **felt-css** (Bootstrap class names) for styling: its components and utilities first; own CSS
  in `priv/static/assets/` only for ZiWoAS widgets, with tokens, never hex. Chart colours via
  `--viz-*` and `priv/static/assets/lib/chart_theme.js`.
  See [ADR-0005](docs/adr/0005-felt-css-as-the-ui-foundation.md).
- Comments in English and sparse — speaking names over commentary. UI text is German.

## Validation

```
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs the same with `MIX_ENV=test`.
Single file: `mix test test/ziwoas/power_series_test.exs`.

## Agent skills

- **Issue tracker** — GitHub Issues on `shostakovich/zihas` via the `gh` CLI. No infrastructure
  details (IPs, SSH, Tailscale) in issues, only the functional outcome.
  See [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).
- **Triage labels** — the five canonical roles (`needs-triage`, `needs-info`, `ready-for-agent`,
  `ready-for-human`, `wontfix`). See [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md).
- **Domain docs** — single context: one `CONTEXT.md`, one `docs/adr/` at the root.
  See [`docs/agents/domain.md`](docs/agents/domain.md).
- **Solakon ONE Modbus** — registers, factors, alarms, grid codes, remote control:
  skill `solakon-modbus`, loaded on demand instead of every run.
