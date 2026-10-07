<img src="priv/static/icon.png" alt="Zipfelmaus – Wohnungsautomatisierung" width="120">

# ZiWoAS – Zipfelmaus Wohnungs Automatisierungs System

Ein Projekt von [zipfelmaus.com](https://zipfelmaus.com).

ZiWoAS ist eine selbst gehostete Energie- und Wohnungsautomatisierung: Es misst Verbrauch und
Erzeugung über Shelly-Steckdosen (MQTT) und Fritz!DECT-Steckdosen, liest und regelt den
Solakon-ONE-Wechselrichter per Modbus TCP, schaltet Steckdosen nach Zeitplan, steuert
Govee-Lampen, sammelt SwitchBot-Sensoren und Wetter (Bright Sky) und schickt Widgets an TRMNL.
Alles in einer Phoenix-1.8-App mit LiveView und SQLite.

## Voraussetzungen

- Erlang/OTP und Elixir in den Versionen aus [`.tool-versions`](.tool-versions)
  (z. B. mit `asdf` oder `mise`). Node ist nicht nötig.
- Für echte Geräte: ein MQTT-Broker (z. B. Mosquitto), optional Fritz!Box, Solakon ONE,
  Govee-API-Key, SwitchBot-Token, TRMNL-Webhooks.

## Einrichten und starten

```bash
cp config/ziwoas.example.yml config/ziwoas.yml   # anpassen: Standort, MQTT, Steckdosen, …
mix setup                                        # Deps, Datenbank, esbuild, Assets
mix phx.server                                   # http://localhost:4000
```

`config/ziwoas.yml` beschreibt die Geräte und ist nicht im Repo. Kostenposten und Strompreise
stehen in der Datenbank und werden unter PV › Wirtschaftlichkeit gepflegt
([ADR-0004](docs/adr/0004-economics-data-lives-in-the-database.md)).

| Variable | Bedeutung |
| --- | --- |
| `ZIWOAS_CONFIG` | Gerätekonfiguration; Standard `config/ziwoas.yml` |
| `ZIWOAS_DB` | SQLite-Datei; Standard `storage/development.sqlite3` |

Lokal am besten eine Konfiguration ohne echte Geräte verwenden: mit echter Konfiguration
schaltet die App Steckdosen, Lampen und den Wechselrichter wirklich.

## Tests und Prüfungen

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
```

`mix test` legt `tmp/test.sqlite3` an und migriert sie; jeder Test läuft in einer Transaktion der
Ecto-SQL-Sandbox. CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) führt dieselben
Schritte aus und baut zusätzlich die Assets.

## Assets

esbuild läuft als eigenständiges Binary (kein Node) und bündelt `assets/js/app.js` mit den
LiveView-Hooks aus `assets/js/hooks/` sowie `assets/css/app.css` nach `priv/static/assets/`.
Chart.js liegt unter `assets/vendor/`, felt-css kommt vom CDN
([ADR-0005](docs/adr/0005-felt-css-as-the-ui-foundation.md)).

```bash
mix assets.setup    # esbuild-Binary laden
mix assets.build    # Entwicklung (mix phx.server baut bei Änderungen selbst neu)
mix assets.deploy   # minifiziert und mit Digest, für ein Release
```

## Release und Datenbank

Ecto-Migrationen in `priv/repo/migrations/` besitzen das Schema. Ein Release (`mix release`)
bringt zwei Skripte mit:

- `bin/migrate` – übernimmt bei Bedarf eine alte Datenbank und führt alle offenen Migrationen
  aus.
- `bin/server` – startet die App mit `PHX_SERVER=true`.

Im Release sind `ZIWOAS_DB`, `ZIWOAS_CONFIG` und `SECRET_KEY_BASE` Pflicht, dazu `PHX_HOST`;
optional `PORT` (Standard 4000) und `POOL_SIZE` (5).

**Übernahme einer alten Datenbank.** Eine SQLite-Datei aus der früheren Rails-App wird beim
ersten `bin/migrate` (bzw. `mix ecto.migrate` in der Entwicklung) einmalig übernommen:
`Ziwoas.Release.adopt_rails_database!/0` prüft die Tabellen und entfernt Rails' Migrationsbuchhaltung,
danach übernehmen die Ecto-Migrationen. Ein zweiter Lauf ändert nichts. Von Hand:

```bash
ZIWOAS_DB=storage/production.sqlite3 mix ziwoas.adopt
```

Vorher immer eine Sicherung anlegen (`sqlite3 … ".backup …"`). Die App selbst sichert die
Datenbank jede Nacht nach `backup/` neben der Datenbankdatei.

## Weiterlesen

- [`CONTEXT.md`](CONTEXT.md) – Fachbegriffe (Schaltzeit, Flanke, Regelung, Eigenverbrauch, …)
- [`docs/architecture.md`](docs/architecture.md) – Aufbau der App
- [`docs/adr/`](docs/adr/) – Architekturentscheidungen
- [`docs/solakon-modbus-protokoll.md`](docs/solakon-modbus-protokoll.md) – Modbus-Register des
  Solakon ONE
- [`docs/trmnl/`](docs/trmnl/) – Liquid-Vorlagen der TRMNL-Widgets
