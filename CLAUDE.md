# CLAUDE.md – ZiWoAS

Self-hosted energy and home automation: Solakon inverter, Shelly plugs, Fritz!Box DECT,
Govee lights, sensors, weather. Domain vocabulary lives in [`CONTEXT.md`](CONTEXT.md),
decisions in [`docs/adr/`](docs/adr/).

## Setup

Rails 8.1 · Ruby 4.0.5 · SQLite · Solid Queue/Cache/Cable · Propshaft + Importmap + Turbo ·
ViewComponent · dry-rb.

| Path | What |
| --- | --- |
| `app/models/` | Domain models; `lights/`, `plugs/`, `switching/`, `sensors/`, `energy_report/` are the functional seams |
| `app/jobs/` | Solid Queue jobs; schedule in `config/recurring.yml` |
| `lib/` | Device clients and calculation cores without Rails ties: `solakon_client.rb`, `govees/`, `power_series.rb`, `aggregator.rb` |
| `bin/ziwoas_collector` | Long-running collector (MQTT, Modbus, Govee bridge) |
| `config/ziwoas.yml` | **Not in the repo** — device config incl. the plug list. Template: `config/ziwoas.example.yml`, tests use `config/ziwoas.test.yml` |
| `test/` | Minitest mirroring `app/` and `lib/`; VCR cassettes in `test/vcr_cassettes/` |

`bundle install && bin/rails db:prepare && bin/dev` starts web, collector and worker together.

Non-interactive shells don't load rbenv and fall back to Ruby 2.6 — prefix Ruby commands with
`PATH="$HOME/.rbenv/shims:$PATH"`.

Real data only exists on the home server (Docker). Local SQLite is not a copy of production:
"empty locally" doesn't mean empty.

## Conventions

- **dry-rb at the data boundaries**: type domain data at the edge (dry-types/-struct,
  dry-validation) instead of passing raw hashes and strings around. `dry-operation` only for
  complex flows (multi-step, side effects, error paths) — **not** for plain CRUD. See
  `app/models/lights/` and `lib/govees/`.
- **ViewComponent** for logic-heavy UI. Trivial markup and simple views (`_form`, `index`)
  stay ERB.
- Comments in English and sparse — speaking names over commentary. UI text is German.

## Validation

`bin/ci` runs the full chain: RuboCop, bundler-audit, importmap audit, Brakeman,
`bin/rails test`, seeds (see [`config/ci.rb`](config/ci.rb)). A Stop hook triggers it on Ruby,
ERB, Gemfile, `db/` and `config/` changes. Single file: `bin/rails test test/lib/foo_test.rb`.

SimpleCov enforces a coverage floor. That floor is the lower bound across run orders, not a
target.

**At the end of a session, run mutation testing on the subjects touched in that session** —
not the whole codebase. Coverage measures execution, not verification: `lib/power_series.rb`
had 100 % line and branch coverage and still let four mutations survive. Commands, the `cover`
declaration, handling survivors, delegating to a subagent: skill
[`mutation-testing`](.claude/skills/mutation-testing/SKILL.md).

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
