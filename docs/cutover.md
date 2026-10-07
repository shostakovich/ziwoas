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
2. **Image bauen**: `docker build -t ziwoas:probe .` (bzw. `docker buildx build --platform
   linux/amd64,linux/arm64 .` für beide Architekturen).
3. **Gerätelose Config**: nur `location:`, `mqtt:` auf einen Host ohne Broker (z. B.
   `127.0.0.1`, Port 1) und `plugs:` aus der echten Config. Kein `solakon:`, `fritz:`,
   `govee:`, `switchbot:`, `trmnl:`.
4. **Starten** mit Zeitmessung:
   ```
   docker run --rm --name ziwoas-probe --network host -e PORT=3000 \
     -e SECRET_KEY_BASE=$(openssl rand -hex 64) -e ZIWOAS_ALLOWED_HOSTS=localhost \
     -v $PWD/probe/storage:/app/storage -v $PWD/probe/ziwoas.yml:/app/config/ziwoas.yml:ro \
     ziwoas:probe
   ```
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
   - Über den echten Hostnamen (Reverse Proxy) ohne Origin-Fehler im Log.
6. **MQTT-Probe (nur lesend, optional)**: Config nur mit `mqtt:` (echter Broker) und
   `plugs:`, in der Kopie `DELETE FROM switch_rules`, keine Klicks auf Schalter oder Lampen.
   Phoenix nimmt Shelly-Status auf (`samples` wächst); mit einem zweiten Dump vergleichen,
   was Rails in derselben Zeit geschrieben hat. Im Broker prüfen, dass `ziwoas-phoenix-*`
   nichts publiziert. Auf verworfene Status achten (Log: Shelly-Status ohne `aenergy.total`).

## B. Umstieg auf dem Heimserver

Govee und Batterie werden gemeinsam live abgenommen. Zeitbedarf: rund 15 Minuten.

1. **Vorbereiten** (Rails läuft noch):
   - Rails-Image sichern: `docker image tag ziwoas:latest ziwoas:rails-final`.
   - Phoenix-Image per Tag ziehen (`docker.yml`, Tag z. B. `phoenix-2026-10-07`).
   - Alte Compose-Datei als `docker-compose.rails.yml` aufheben, die neue
     `docker-compose.yml` daneben legen; `.env` mit `ZIWOAS_TAG`, `SECRET_KEY_BASE`
     (`openssl rand -hex 64`), `PHX_HOST`, `ZIWOAS_ALLOWED_HOSTS` (wie bisher).
   - `migration:`-Block aus `config/ziwoas.yml` entfernen (sonst nur eine Warnung).
2. **Rails stoppen**: `docker compose -f docker-compose.rails.yml down` – alle drei
   Container (`ziwoas`, `ziwoas_collector`, `ziwoas_jobs`), damit Modbus und UDP 4002 frei
   sind. Prüfen, dass niemand `storage/production.sqlite3` offen hat (`fuser`).
3. **Backup**:
   `sqlite3 storage/production.sqlite3 ".backup storage/backup/pre-phoenix-$(date +%F).sqlite3"`,
   dann `sqlite3 storage/backup/pre-phoenix-*.sqlite3 'PRAGMA integrity_check'` = `ok`.
4. **Phoenix starten**: `docker compose up -d`, `docker compose logs -f` – Übernahme und vier
   Migrationen, dann der Endpoint.
5. **Smoke** (binnen 15 Minuten):
   - `/up` = 200, Container `healthy`.
   - Alle Seiten, keine Origin-Fehler, LiveView verbunden.
   - `samples` wächst (Shelly über MQTT), `solakon_readings` alle 30 s.
   - Govee-Zustand kommt an, eine Lampe schalten (gemeinsam).
   - Batterie-Regelung: Sollwert und Modus auf der PV-Seite plausibel (gemeinsam).
   - Wetter und TRMNL binnen 15 Minuten aktualisiert, Schalttakt binnen 1 Minute,
     Fritz!DECT-Werte.
6. **Rückweg**, falls nötig: `docker compose down`; Backup zurück nach
   `storage/production.sqlite3`, `production.sqlite3-wal` und `-shm` löschen;
   `docker compose -f docker-compose.rails.yml up -d` mit `ziwoas:rails-final`.
   Daten seit dem Umstieg gehen dabei verloren.
7. **Nach stabilen Tagen**: Solid-Queue-, Cache- und Cable-Dateien in `storage/`, das
   Rails-Image und `docker-compose.rails.yml` löschen; danach in einem Folge-PR die
   Übernahme (`adopt_rails_database!`, `ziwoas.adopt`, Paritätstest,
   `test/fixtures/rails_schema.sql`) und `docs/port-plan.md` entfernen.
