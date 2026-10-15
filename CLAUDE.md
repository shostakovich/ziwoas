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
| `assets/` | `css/app.css` (Tailwind entry: daisyUI, Setzkasten, `palette.css`, area files), JS (LiveView hooks in `js/hooks/`), vendored Chart.js and Lucide icons; the standalone Tailwind and esbuild build into `priv/static/assets/` |
| `priv/repo/migrations/` | Ecto migrations, recorded in production: add new ones, never edit old ones; a release runs them via `Ziwoas.Release.migrate/0` |
| `priv/static/` | Images and icons, served as they are |
| `test/` | ExUnit mirroring `lib/`; `test/support/` holds the cases and the fakes (Modbus, MQTT, clock) |

`mix setup` (deps, database, Tailwind and esbuild, assets), then `mix phx.server`. Paths default
to `config/ziwoas.yml` and `storage/development.sqlite3`; `ZIWOAS_CONFIG` and `ZIWOAS_DB` override
them (see [`config/runtime.exs`](config/runtime.exs)).

Cloud sessions (Claude Code on the web) are set up by the SessionStart hook
[`.claude/hooks/session-start.sh`](.claude/hooks/session-start.sh): Erlang/OTP and Elixir
from `.tool-versions`, Hex and git deps, the Tailwind and esbuild binaries, `config/ziwoas.yml`
seeded from the test fixture. It is a no-op outside a remote container.

Real data only exists on the home server (Docker). Local SQLite is not a copy of production:
"empty locally" doesn't mean empty.

## Conventions

- **Idiomatic Phoenix**, no compatibility with the former Rails app
  ([ADR-0007](docs/adr/0007-idiomatic-phoenix-big-bang-cutover.md)); how the app is built and
  its code conventions live in Outline ("ZiWoAS-Architektur", https://outline.rocu.de/doc/mS5HPHX1WJ),
  not in the repo.
- **Ecto migrations own the schema**; timestamps are `:utc_datetime_usec` with `inserted_at`.
  Forms are changesets with German messages and Setzkasten's `<.input>`; a refused save shows
  `ZiwoasWeb.ErrorSummary`, and Setzkasten's `FocusInvalid` hook on the `<.form>` focuses the first
  invalid field. Interaction is LiveView events, client code LiveView hooks in `assets/js/hooks/`.
- **Setzkasten** (Tailwind 4, daisyUI 5) for the UI: its components and its design system
  (`guides/design-system.md` in Setzkasten) first; its conventions win.
  See [ADR-0011](docs/adr/0011-setzkasten-as-the-ui-foundation.md).
- Pages pass `width` to `Layouts.app`: `:default`, forms `:narrow`; the top bar stays
  `:default`. Live pages mark stale data on the server with `ZiwoasWeb.LiveFreshness` (badge and
  time in the header, `stale` stats), never by fading.
- ZiWoAS's palette in `assets/css/palette.css`; own CSS in `assets/css/` only for ZiWoAS
  widgets, on Tailwind/daisyUI tokens, never hex. Data colours: the tokens in
  `application.css` (`--color-solar`, `--color-grid`, `--color-battery`, `--color-chart-N`, …),
  painted on charts by `assets/js/lib/chart_theme.js`. Categories take the series their chart
  leaves free: consumer plugs by their 30-day energy (`Ziwoas.Plugs.consumer_rank/2`, passed to
  `Charts.Categories` and to the hooks as `consumer_order`), sensors in config order;
  `tonesByOrder(ids, semantic)` and `consumer_series.js` in JS, `ZiwoasWeb.Charts.Series` in
  Elixir. The rest is one "Weitere" in Setzkasten's `chart-other` (`OTHER_TONE`, `color: :other`
  in a legend) whose tooltip names its plugs; Home's share bar names each of them in
  `chart-other` instead. The total line takes `--color-chart-total`, which matches the legend's
  `:neutral`.
- Plush images by name via `ZiwoasWeb.Plush`, Lucide icons via `ZiwoasWeb.Icons`
  (`assets/vendor/lucide`).
- Comments in English and sparse — speaking names over commentary. UI text is German.

## Validation

```
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix assets.build
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs the same with `MIX_ENV=test`,
except that it builds the assets with `mix assets.setup && mix assets.deploy`.
Single file: `mix test test/ziwoas/power_series_test.exs`.

## Agent skills

- **Issue tracker** — GitHub Issues on `shostakovich/ziwoas` via the `gh` CLI. No infrastructure
  details (IPs, SSH, Tailscale) in issues, only the functional outcome.
  See [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).
- **Triage labels** — the five canonical roles (`needs-triage`, `needs-info`, `ready-for-agent`,
  `ready-for-human`, `wontfix`). See [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md).
- **Domain docs** — single context: one `CONTEXT.md`, one `docs/adr/` at the root.
  See [`docs/agents/domain.md`](docs/agents/domain.md).
- **Solakon ONE Modbus** — registers, factors, alarms, grid codes, remote control:
  skill `solakon-modbus`, loaded on demand instead of every run.
