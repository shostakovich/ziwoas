# Umstieg Rails → Phoenix: Generalprobe und Runbook

Gehört zu [ADR-0007](adr/0007-idiomatic-phoenix-big-bang-cutover.md) und Issue #158. Teil A
läuft lokal auf einer Kopie, Teil B auf dem Heimserver. Teil A kommt vor Teil B, ohne
Ausnahme.

Der Container (siehe `Dockerfile`, `docker-compose.yml`) führt beim Start `bin/migrate` aus:
Er übernimmt die Rails-Datenbank einmalig (`Ziwoas.Release.adopt_rails_database!/0`, wirft
`schema_migrations` und `ar_internal_metadata` weg) und migriert dann. Danach startet
`bin/server` auf Port 3000. Ab der Übernahme kann Rails die Datei nicht mehr lesen
(Spalten umbenannt, Zeitformat umgeschrieben); zurück geht es nur über das Backup.

## A. Generalprobe (lokal, Prod-Dump, ohne Geräte)

1. **Dump ziehen**, auf dem Heimserver lesend:
   `sqlite3 'file:storage/production.sqlite3?mode=ro' ".backup /tmp/ziwoas-dump.sqlite3"`,
   dann nach lokal kopieren. Immer mit einer **Kopie** des Dumps arbeiten.
2. **Image bauen**: `docker build -t ziwoas:probe .`. Das veröffentlichte Image ist nur
   amd64 (Heimserver); vom Mac aus baut `docker build --platform linux/amd64 .` dasselbe.
3. **Gerätelose Config**: nur `location:`, `mqtt:` auf einen Host ohne Broker (z. B.
   `127.0.0.1`, Port 1) und `plugs:` aus der echten Config. Kein `solakon:`, `govee:`,
   `switchbot:`, `trmnl:`. Plugs mit `driver: fritz_dect` brauchen `fritz_box:` und
   `fritz_poll:`: dort `fritz_box.host` auf eine unerreichbare Adresse setzen
   (z. B. `127.0.0.1`). Die echte `ziwoas.yml` nur parsen, nicht starten (spricht kein
   Gerät an):
   `docker run --rm -e SECRET_KEY_BASE=x -v $PWD/config/ziwoas.yml:/app/config/ziwoas.yml:ro ziwoas:probe
   bin/ziwoas eval 'Ziwoas.Config.from_yaml!(File.read!("/app/config/ziwoas.yml")); IO.puts(:ok)'`.
   Lädt eine Config im Betrieb nicht, antwortet `/up` mit 503 und das Log nennt den Schlüssel.
4. **Starten** mit Zeitmessung:
   ```
   docker run --rm --name ziwoas-probe --network host -e PORT=3000 \
     -e SECRET_KEY_BASE=$(openssl rand -hex 64) -e PHX_HOST=<echter Hostname> \
     -e ZIWOAS_ALLOWED_HOSTS=localhost,<LAN-IP> \
     -v $PWD/tmp/probe/storage:/app/storage -v $PWD/tmp/probe/ziwoas.yml:/app/config/ziwoas.yml:ro \
     ziwoas:probe
   ```
   `tmp/probe/` ist git- und docker-ignoriert, der Dump landet also nicht im Image. Die
   Datei **nicht vom Host aus öffnen**, solange der Container läuft: Über den Bind-Mount von
   Docker Desktop/OrbStack wirken SQLite-Sperren nicht, ein Host-`sqlite3` checkpointet und
   kürzt das WAL, der Container meldet danach `disk I/O error`. Daten nach `docker stop`
   prüfen (das Image hat kein `sqlite3`). Ein zweiter Container im Host-Netz braucht
   `-e RELEASE_NODE=<anderer Name>`.
   Im Log: „Adopted the Rails database“, vier `Migrated`, dann `Running ZiwoasWeb.Endpoint`.
   Ein zweiter Start migriert nichts.
5. **Prüfen**:
   - `PRAGMA integrity_check` = `ok`; Zeilenzahlen aller Tabellen gleich wie im Dump.
   - Keine Zeitspalte mehr im Rails-Format (`… WHERE inserted_at GLOB '* *'` leer).
   - `cost_items.spent_on` überall `YYYY-MM-DD` (jetzt ein `:date`-Feld).
   - Alle Seiten im Browser: Dashboard, Berichte (auch ein Zeitraum über Monate), PV mit
     Verlauf (Reiter 24 h/7 Tage/30 Tage, Neuladen behält den Reiter), Wirtschaftlichkeit
     (Posten anlegen und löschen, Nachfrage beim Löschen, Preis anlegen), Wetter, Sensoren,
     Schalten (Editor öffnen, speichern, löschen – nur in der Kopie!), eine Lampe.
     Konsole ohne Fehler, LiveView verbunden (kein „Keine Verbindung“).
   - `/api/today`, `/api/history`, `/up`, `/up.json`.
   - Über den echten Hostnamen (Reverse Proxy) ohne Origin-Fehler im Log, und direkt per
     `http://<LAN-IP>:3000`. Der Proxy muss `X-Forwarded-Proto: https` setzen; nur dann
     gibt es HSTS und Secure-Cookies (`ZiwoasWeb.ForwardedSSL`).
   - LiveView akzeptiert `PHX_HOST` und die Hosts aus `ZIWOAS_ALLOWED_HOSTS` (ohne Schema,
     Port egal; `.example.org` gilt als `*.example.org`).
6. **MQTT-Probe (nur lesend, optional)**: Config nur mit `mqtt:` (echter Broker) und
   `plugs:`, in der Kopie `DELETE FROM switch_rules`, keine Klicks auf Schalter oder Lampen.
   Phoenix nimmt Shelly-Status auf (`samples` wächst); mit einem zweiten Dump vergleichen,
   was Rails in derselben Zeit geschrieben hat. Im Broker prüfen, dass `ziwoas-phoenix-*`
   nichts publiziert. Auf verworfene Status achten (Log: Shelly-Status ohne `aenergy.total`).

## B. Umstieg auf dem Heimserver

Durchgeführt am 2026-10-07 (Rails gestoppt 16:30:54 UTC, Phoenix-Endpoint 16:31:12, Übernahme
und Migrationen 4,6 s). Govee und Batterie wurden gemeinsam live abgenommen. So lief es, mit
den Besonderheiten des Heimservers:

1. **Vorbereiten** (Rails läuft noch), in `/web/config/ziwoas`:
   - Online-Backup `sqlite3 'file:…/production.sqlite3?mode=ro' ".backup …/backup/pre-phoenix-<ts>.sqlite3"`
     mit `integrity_check`.
   - `docker image tag ghcr.io/shostakovich/ziwoas:latest ziwoas:rails-final`, Phoenix-Image
     per Tag ziehen (`phoenix-2026-10-07`).
   - `compose.yml` → `compose.rails.yml` und `ziwoas.yml` → `ziwoas.yml.rails-final` kopieren.
   - `compose.phoenix.yml`: ein Dienst `ziwoas` im Host-Netz (Daten
     `/web/data/ziwoas/data:/app/storage`, `ziwoas.yml` read-only, `PHX_HOST`,
     `ZIWOAS_ALLOWED_HOSTS`), **Mosquitto unverändert übernommen** – der Broker steckt im
     selben Compose-Projekt. `.env` mit `SECRET_KEY_BASE`.
2. **Rails stoppen**, nur die drei Rails-Dienste:
   `docker compose -f compose.rails.yml stop ziwoas ziwoas_collector ziwoas_jobs` und `rm -f`
   – **kein `down`**, das nähme Mosquitto mit. `fuser` auf der DB leer, UDP 4002 frei.
3. **Backup** ohne Schreiber: `.backup …/backup/pre-phoenix-final-<ts>.sqlite3`,
   `integrity_check` = `ok`.
4. **Phoenix starten**: in `ziwoas.yml` `electricity_price_eur_per_kwh` und
   `trmnl_webhook_url` entfernen; `compose.phoenix.yml` → `compose.yml`;
   `docker compose up -d --no-deps ziwoas`; Log: Übernahme, vier `Migrated`, Endpoint.
5. **Caddy**: Phoenix läuft im Host-Netz, der Dienstname `ziwoas` ist im Netz `frontend`
   nicht mehr auflösbar. Im Caddyfile `reverse_proxy ziwoas:3000` →
   `reverse_proxy 192.168.8.100:3000` (Datei in place schreiben, Single-File-Bind-Mount),
   `caddy validate`, `caddy reload`. Caddy setzt `X-Forwarded-Proto` selbst.
6. **Smoke**: `/up` und alle Seiten über den Hostnamen 200, HSTS und Secure-Cookie, Container
   `healthy`, keine Origin-Fehler; alle Shellys in `samples`, `solakon_readings` alle 30 s,
   Batterie-Regelung tickt; eine Lampe und eine Steckdose geschaltet; Schalttakt jede Minute.
   Fritz!DECT liefert nur, wenn die Dose eingesteckt ist („inval“ sonst).
7. **Rückweg**, falls nötig: `docker compose stop ziwoas && docker compose rm -f ziwoas`;
   `pre-phoenix-final-*.sqlite3` zurück nach `production.sqlite3`, `-wal`/`-shm` löschen;
   `ziwoas.yml.rails-final` zurück; `compose.rails.yml` → `compose.yml`, `docker compose up -d`
   (Image `ziwoas:rails-final` als `ghcr.io/shostakovich/ziwoas:latest` taggen);
   `Caddyfile.before-phoenix` zurück und `caddy reload`. Daten seit dem Umstieg gehen verloren.
8. **Nach stabilen Tagen**: in `/web/data/ziwoas/data` die `production_cable/_cache/_queue`-
   Dateien und die alte `ziwoas.db`, `ziwoas:rails-final`, `compose.rails.yml`,
   `compose.yml.was-rails`, `ziwoas.yml.rails-final` und `Caddyfile.before-phoenix` löschen; danach in einem Folge-PR die
   Übernahme (`adopt_rails_database!`, `ziwoas.adopt`, Paritätstest,
   `test/fixtures/rails_schema.sql`) und `docs/port-plan.md` entfernen.
