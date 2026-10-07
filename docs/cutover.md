# Cutover Rails → Phoenix: rehearsal and runbook

> Historical record. After the cutover the adoption (`adopt_rails_database!`, `mix ziwoas.adopt`,
> the Rails schema fixture and its tests) and `docs/port-plan.md` were removed; `bin/migrate` now
> only migrates. Part A can no longer be replayed against a Rails dump with the current code.

Belongs to [ADR-0007](adr/0007-idiomatic-phoenix-big-bang-cutover.md) and issue #158. Part A
runs locally on a copy, part B on the home server. Part A comes before part B, without
exception.

On start, the container (see `Dockerfile`, `docker-compose.yml`) runs `bin/migrate`: it adopts
the Rails database once (`Ziwoas.Release.adopt_rails_database!/0`, drops `schema_migrations` and
`ar_internal_metadata`) and then migrates. Then `bin/server` starts on port 3000. After the
adoption Rails can no longer read the file (columns renamed, time format rewritten); the only
way back is the backup.

## A. Rehearsal (local, production dump, no devices)

1. **Take a dump**, read-only on the home server:
   `sqlite3 'file:storage/production.sqlite3?mode=ro' ".backup /tmp/ziwoas-dump.sqlite3"`,
   then copy it to the local machine. Always work on a **copy** of the dump.
2. **Build the image**: `docker build -t ziwoas:probe .`. The published image is amd64 only
   (the home server); on the Mac, `docker build --platform linux/amd64 .` builds the same.
3. **Config without devices**: only `location:`, `mqtt:` pointing at a host without a broker
   (e.g. `127.0.0.1`, port 1) and `plugs:` from the real config. No `solakon:`, `govee:`,
   `switchbot:`, `trmnl:`. Plugs with `driver: fritz_dect` need `fritz_box:` and
   `fritz_poll:`: set `fritz_box.host` to an unreachable address there (e.g. `127.0.0.1`).
   Only parse the real `ziwoas.yml`, don't start it (this contacts no device):
   `docker run --rm -e SECRET_KEY_BASE=x -v $PWD/config/ziwoas.yml:/app/config/ziwoas.yml:ro ziwoas:probe
   bin/ziwoas eval 'Ziwoas.Config.from_yaml!(File.read!("/app/config/ziwoas.yml")); IO.puts(:ok)'`.
   If a config fails to load in operation, `/up` answers 503 and the log names the key.
4. **Start** and time it:
   ```
   docker run --rm --name ziwoas-probe --network host -e PORT=3000 \
     -e SECRET_KEY_BASE=$(openssl rand -hex 64) -e PHX_HOST=<real hostname> \
     -e ZIWOAS_ALLOWED_HOSTS=localhost,<LAN IP> \
     -v $PWD/tmp/probe/storage:/app/storage -v $PWD/tmp/probe/ziwoas.yml:/app/config/ziwoas.yml:ro \
     ziwoas:probe
   ```
   `tmp/probe/` is ignored by git and Docker, so the dump never ends up in the image. **Don't
   open the file from the host** while the container runs: SQLite locks don't work across the
   bind mount of Docker Desktop/OrbStack, a host `sqlite3` checkpoints and truncates the WAL,
   and the container then reports `disk I/O error`. Check the data after `docker stop`, or with
   `docker exec … sqlite3` inside the container. A second container on the host network needs
   `-e RELEASE_NODE=<other name>`.
   In the log: "Adopted the Rails database", four `Migrated`, then `Running ZiwoasWeb.Endpoint`.
   A second start migrates nothing.
5. **Check**:
   - `PRAGMA integrity_check` = `ok`; row counts of all tables equal to the dump.
   - No time column left in Rails format (`… WHERE inserted_at GLOB '* *'` empty).
   - `cost_items.spent_on` is `YYYY-MM-DD` everywhere (now a `:date` field).
   - Every page in the browser: Dashboard, Berichte (also a range over months), PV with
     Verlauf (tabs 24 h/7 Tage/30 Tage, a reload keeps the tab), Wirtschaftlichkeit (create and
     delete an item, confirmation on delete, create a price), Wetter, Sensoren, Schalten (open
     the editor, save, delete – only in the copy!), one lamp. Console without errors, LiveView
     connected (no "Keine Verbindung").
   - `/api/today`, `/api/history`, `/up`, `/up.json`.
   - Through the real hostname (reverse proxy) without origin errors in the log, and directly at
     `http://<LAN IP>:3000`. The proxy must set `X-Forwarded-Proto: https`; only then are there
     HSTS and secure cookies (`ZiwoasWeb.ForwardedSSL`).
   - LiveView accepts `PHX_HOST` and the hosts from `ZIWOAS_ALLOWED_HOSTS` (without scheme, any
     port; `.example.org` means `*.example.org`).
6. **MQTT probe (read-only, optional)**: config with only `mqtt:` (the real broker) and
   `plugs:`, `DELETE FROM switch_rules` in the copy, no clicks on switches or lamps. Phoenix
   ingests Shelly statuses (`samples` grows); compare with a second dump what Rails wrote in the
   same time. Check on the broker that `ziwoas-phoenix-*` publishes nothing. Watch for dropped
   statuses (log: Shelly status without `aenergy.total`).

## B. Cutover on the home server

Done on 2026-10-07 (Rails stopped 16:30:54 UTC, Phoenix endpoint 16:31:12, adoption and
migrations 4.6 s). Govee and the battery were checked live together. This is how it went, with
the specifics of the home server:

1. **Prepare** (Rails still running), in `/web/config/ziwoas`:
   - Online backup `sqlite3 'file:…/production.sqlite3?mode=ro' ".backup …/backup/pre-phoenix-<ts>.sqlite3"`
     with `integrity_check`.
   - `docker image tag ghcr.io/shostakovich/ziwoas:latest ziwoas:rails-final`, pull the Phoenix
     image by tag (`phoenix-2026-10-07`).
   - Copy `compose.yml` → `compose.rails.yml` and `ziwoas.yml` → `ziwoas.yml.rails-final`.
   - `compose.phoenix.yml`: one service `ziwoas` on the host network (data
     `/web/data/ziwoas/data:/app/storage`, `ziwoas.yml` read-only, `PHX_HOST`,
     `ZIWOAS_ALLOWED_HOSTS`), **Mosquitto carried over unchanged** – the broker lives in the
     same compose project. `.env` with `SECRET_KEY_BASE`.
2. **Stop Rails**, only the three Rails services:
   `docker compose -f compose.rails.yml stop ziwoas ziwoas_collector ziwoas_jobs` and `rm -f`
   – **no `down`**, that would take Mosquitto with it. `fuser` on the database empty, UDP 4002
   free.
3. **Backup** without writers: `.backup …/backup/pre-phoenix-final-<ts>.sqlite3`,
   `integrity_check` = `ok`.
4. **Start Phoenix**: remove `electricity_price_eur_per_kwh` and `trmnl_webhook_url` from
   `ziwoas.yml`; `compose.phoenix.yml` → `compose.yml`; `docker compose up -d --no-deps ziwoas`;
   log: adoption, four `Migrated`, endpoint.
5. **Caddy**: Phoenix runs on the host network, so the service name `ziwoas` no longer resolves
   in the `frontend` network. In the Caddyfile, `reverse_proxy ziwoas:3000` →
   `reverse_proxy 192.168.8.100:3000` (write the file in place, it is a single-file bind mount),
   `caddy validate`, `caddy reload`. Caddy sets `X-Forwarded-Proto` itself.
6. **Smoke**: `/up` and every page through the hostname 200, HSTS and secure cookie, container
   `healthy`, no origin errors; every Shelly in `samples`, `solakon_readings` every 30 s, the
   battery control ticks; one lamp and one plug switched; the schedule tick every minute.
   Fritz!DECT only delivers while the plug is plugged in ("inval" otherwise).
7. **Way back**, if needed: `docker compose stop ziwoas && docker compose rm -f ziwoas`;
   `pre-phoenix-final-*.sqlite3` back to `production.sqlite3`, delete `-wal`/`-shm`;
   `ziwoas.yml.rails-final` back; `compose.rails.yml` → `compose.yml`, `docker compose up -d`
   (tag `ziwoas:rails-final` as `ghcr.io/shostakovich/ziwoas:latest`); `Caddyfile.before-phoenix`
   back and `caddy reload`. Data written since the cutover is lost.
8. **After stable days**: in `/web/data/ziwoas/data` delete the `production_cable/_cache/_queue`
   files and the old `ziwoas.db`; delete `ziwoas:rails-final`, `compose.rails.yml`,
   `compose.yml.was-rails`, `ziwoas.yml.rails-final` and `Caddyfile.before-phoenix`; then, in a
   follow-up PR, remove the adoption (`adopt_rails_database!`, `ziwoas.adopt`, parity test,
   `test/fixtures/rails_schema.sql`) and `docs/port-plan.md`.
