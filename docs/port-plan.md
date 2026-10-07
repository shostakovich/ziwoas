# Port-Plan: Phoenix wird idiomatisch, dann Big-Bang-Umstieg (#158)

> Arbeitsplan der Migration, nicht dauerhafte Doku: entfällt in Phase 3 bzw. geht in ADR-0007 auf.

## Stand (2026-10-06)

| Phase | Stand |
|---|---|
| 0 Ruby raus, Phoenix nach oben | fertig (`cb73179`, `fcf5d1a`) |
| 1 Datenschicht | P1a Migrations/Übernahme `f0d7162`, A1 esbuild `af0d0e9`, P1b Sandbox/Rückbau `714aa93`, P1c Zeitstempel `5ab6ba1`, A2 Stimulus → Hooks `88f2aea` – fertig |
| 2 Scheiben S1–S4 | offen – nächster Schritt |
| 3 Aufräumen, Credo, Doku | offen |
| 4 Deployment, Generalprobe | offen – lokal mit Robert (Prod-Dump, MQTT nur lesend) |
| 5 Umstieg | Robert |

Arbeitsweise: Claude koordiniert, Opus-Subagenten in großen, disjunkten Paketen (parallele Pakete in eigenen Worktrees, weil `_build` und die Test-DB geteilt sind), Claude committet je Paket nach eigener Gate-Prüfung (Exit-Codes, nicht `| tail`). Push auf `claude/awesome-heisenberg-61irby` ist freigegeben. Validierung im Browser macht Robert am Ende gemeinsam mit Claude.

Erkenntnisse aus Phase 0/1, die Phase 2 betreffen:

- Ownership-Reste (`Ownership.*`, `Repo.write/2` = `fun.()`, Dry-Run-Zweige, `Owned`, `shadow_offset`) listet der P1b-Commit; jede Scheibe löst sie in ihren Pfaden auf.
- `:utc_datetime_usec` verlangt beim Dump Mikrosekunden: `Repo.insert!(%Struct{})`, `insert_all`, `change/2` casten nicht – `~U[…]` ohne µs wirft. Zeitvergleiche immer über getypte Felder; Roh-SQL über `Repo.dump_time/1`.
- DB-Tests sind synchron (`DataCase`/`ConnCase` verweigern `async: true`); Repos auf eigenen Dateien brauchen `pool: DBConnection.ConnectionPool`.
- `assert_receive` hat global 1000 ms Timeout (Flakes unter Last).
- Nach A2 hängt in `assets/js/app.js` noch: der Capture-Listener `a[href][phx-click]` (Range-Tabs im Solakon-Verlauf, Zahnrad der Lampe) und der Submit-Listener für `data-turbo-confirm` (Löschknöpfe des Zeitplans). Die Löschformulare der Wirtschaftlichkeit (`economics_html.ex`, keine LiveView) fragen ohne Turbo gar nicht nach – S2 behebt das mit der LiveView. Die PATCH-Routen `/solakon/eps|control` (`SolakonControlsController`, Pipeline `:json_writes`) ruft niemand mehr auf – S2 löscht sie. Der Turbo-Stream-Pfad von `LightController` – S3.
- Hooks liegen in `assets/js/hooks/`, Charts aktualisieren in place über `renderChart` in `assets/js/lib/chart_theme.js`; Canvas-Container tragen `phx-update="ignore"`.
- Lokal (nicht in der Cloud) gibt es eine Prod-Kopie für Laufproben; in der Cloud nur Tests. Laufprobe und Browser-Abnahme macht Robert mit Claude in Phase 4.

## Context

Der lokale Lauf auf der Prod-Kopie (2026-10-06) hat den Port bestätigt: Golden Master 153/153, 2688 Vektorfälle grün, live keine inhaltliche Abweichung. Robert hält das Brücken-Gerüst für Overkill und will den Featherpage-Kurs (Outline „meerkat-cms › Phoenix-Port: Plan und Entscheidungen“): kein Parallelbetrieb, keine Rails-Kompatibilität, idiomatisches Phoenix („the Phoenix way“), Umstieg als letzter Schritt. Rails läuft bis dahin unverändert von `main`; der Port-Branch (PR #159) wird umgebaut.

**Ergebnis:** ein reines Phoenix-1.8-Repo im Wurzelverzeichnis, Ecto besitzt das Schema, keine Ruby-Kompatibilität, Assets per esbuild, LiveView-Hooks statt Stimulus, Deployment als ein Container. Danach nimmt Robert den Umstieg auf dem Heimserver per Runbook vor; Govee und Batterie werden gemeinsam live abgenommen.

## Entschieden

- Rückbau in einem Zug: Eigentümer-Weiche, Leases, Shadow-DB, Watcher, Turbo-Controller, Golden Master, Vektoren (ersatzlos), Rails-Fixture, `shadow_compare`, synthetische DB, alles Ruby.
- Phoenix ins Wurzelverzeichnis; `main` ab Phase 0 eingefroren (nur Hotfixes, von Hand portiert).
- Ecto-Migrations besitzen das Schema; Rails-Übernahme läuft vor dem Migrator (Kollision mit Rails' `schema_migrations`).
- Zeitstempel: `:utc_datetime_usec`, Spalten `created_at` → `inserted_at` (Phoenix-Standard), einmalige Umschreibung in der DB.
- Keine Ruby-Kompatibilität: `RubyNumeric`, `RubyJSON`, `RubyDate`, `RailsCast`, `Ziwoas.Form`, Rails-Formular-Markup weg. `/api/*` hat nur interne Nutzer (Robert, 2026-10-06), Format darf sich ändern; TRMNL-Payload gegen das 2-kB-Limit testen.
- Formulare: Changesets mit deutschen Meldungen, ohne Gettext; `core_components` im Stil von 1.8 auf felt-css-Klassen.
- Tests: Ecto-SQL-Sandbox wie der Generator; DB-Tests synchron (SQLite kann kein async mit Sandbox), reine Tests bleiben async.
- Assets: esbuild als Standalone-Binary (kein Node), `phx.digest`, Chart.js vendored; Stimulus → LiveView-Hooks; felt-css weiter vom CDN.
- Lint: `mix format`, Credo, `compile --warnings-as-errors` in CI. Skill `mutation-testing` und Mutant-Regel in CLAUDE.md entfallen; Muzak als eigenes Issue.
- Doku: ADR-0007 löst ADR-0006 ab; CLAUDE.md, README, CONTEXT.md (Abschnitt Migration fällt weg), elixir/README in die neue README.
- Deployment: ein Container, `network_mode: host`, Port 3000 bleibt, `check_origin` aus einer Env-Liste (ersetzt `ZIWOAS_ALLOWED_HOSTS`).
- Lokale Läufe nur mit geräteloser Config (wie die heutige lokale `config/ziwoas.yml`), kein Schalter im Code.
- Arbeitsteilung: Claude koordiniert, Opus-Subagenten in großen, disjunkten Paketen, sie committen nicht; Claude committet je Paket. Push nur mit Roberts OK.

## Phasen

Jedes Paket endet mit: `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test` (ab Phase 3 Credo). Laufprobe auf einer **Kopie** der Prod-Kopie (`sqlite3 'file:…?mode=ro' ".backup …"`), nie am Original.

### Phase 0: Ruby raus, Phoenix nach oben (sequenziell)

- **P0.1 – `elixir/` eigenständig machen:** Bilder, Stylesheets, Stimulus-Controller, `chart.min.js`, Icons nach `priv/static` unter denselben URLs; `ZiwoasWeb.RailsAssets` → `Plug.Static`, `:rails_root` weg. `config/ziwoas.test.yml` und `ziwoas.golden.yml` (als Wechselrichter-Fixture) nach `test/fixtures/`; `recurring.yml`-Abgleich in `scheduler/jobs_test.exs`/`schedule_test.exs` streichen. Löschen: `mix ziwoas.golden_render`, `ZIWOAS_NOW` (`check_frozen_clock!`, `Clock`-Schritt 2), `rails_contract_test.exs`, `vector_case.ex` + `test/vectors/`, `rails_assets_test.exs`.
- **P0.2 – Umzug:** `git rm` aller Ruby-/Rails-Dateien (app, bin, db, lib, test, script, config/*.rb, Gemfile*, Rakefile, Procfile.dev, .rubocop/.reek/.mutant); alter Dockerfile/Compose bleiben als Referenz bis Phase 4. `git mv elixir/* .`, Pfade `../../` korrigieren, `.tool-versions`, `.formatter.exs`, `.gitignore`, `.dockerignore`. `ci.yml` nur noch Elixir; `docker.yml` Publish auf `workflow_dispatch` bis Phase 4.
- **Fertig:** keine `*.rb`/`*.erb`/`Gemfile*` mehr; Gates grün; `mix phx.server` auf der Prod-Kopie rendert alle Seiten mit Bildern, CSS, Charts.

### Phase 1: Datenschicht – `[P1a ∥ A1] → P1b → [P1c ∥ A2]`

Vorab (Claude): Deps `esbuild`, `credo`; `ecto_repos`, `migration_primary_key: [type: :serial]`, Alias-Gerüst, esbuild-Config – damit `mix.exs`/`config/*` nicht umkämpft sind.

- **P1a – Migrations und Übernahme:** `priv/repo/migrations/` Baseline (alle 19 Tabellen mit `create_if_not_exists`, Float-Spalten als `:real`, zusammengesetzte PKs, partieller Unique-Index), `normalize_rails_drift` (`idx_samples_ts` → `index_samples_on_ts`). `Ziwoas.Release.adopt_rails_database!/0` (nur wenn `schema_migrations` ohne `inserted_at`: 19 Tabellen prüfen, dann `schema_migrations`/`ar_internal_metadata` droppen; idempotent), `Release.migrate/0`, `rel/overlays/bin/{migrate,server}`, Mix-Task `ziwoas.adopt` + Alias `"ecto.migrate": ["ziwoas.adopt", "ecto.migrate"]`. Repo schreibbar. Temporärer Paritätstest frisch-migriert vs. `priv/rails_schema.sql` (`PRAGMA table_info`/`index_list`).
  **Fertig:** Parität grün; auf der Prod-Kopie Migrate ok, zweiter Lauf No-op, Zeilenzahlen gleich, `integrity_check` ok.
- **A1 – Asset-Toolchain:** `assets/`, esbuild-Profile JS + CSS, Chart.js als `assets/vendor/chart.umd.js` mit explizitem Import, Bilder unter `~p"/images/…"`, die ~10 `"/assets/…"`-Literale → `~p`; Vendor-`Plug.Static` aus `endpoint.ex` weg. Stimulus läuft vorerst gebündelt weiter. **Fertig:** `mix assets.deploy` ok, alle Chart-Seiten rendern.
- **P1b – Sandbox und Umlegen** (allein, fegt die Tests): Generator-Testconfig, `DataCase`/`ConnCase` (raise bei async), Sweep `async: true`/`db: true` aus DB-Tests; `RailsFixture` + `.sql`-Dateien weg. `Ownership.owners/0` = alles `:phoenix`, `Repo.write(task, fun)` = `fun.()`. Löschen: `writer_children`, `put_writer`, `test_lineage`, `inherit_dynamic_repo` (auch `nav.ex`), `ShadowDb`, `Lease`, `Lease.Row`, `SensorsWatcher`, `SolakonWatcher`; Migration `drop_migration_leases`. `Solakon.Monitor` `keep_open` default true. Backup (`VACUUM INTO`) als injizierbare Funktion, echter Test via `Sandbox.unboxed_run`. Lineage-Helfer von `Clock.freeze`/`Mqtt.record` in Test-Support verlegen. Suite-Laufzeit vorher/nachher messen.
  **Fertig:** `git grep -E 'put_writer|test_lineage|ShadowDb|Lease|MainWriter'` leer.
- **P1c – Zeitstempel:** `Ziwoas.Schema` → `@timestamps_opts [type: :utc_datetime_usec]`, Migration benennt `created_at` → `inserted_at` um und schreibt alle Zeitspalten um (`created_at`/`updated_at` der 14 Tabellen plus `last_seen_at`, `last_tick_at`, `taken_at` ×3, `last_decision_at`, `started_at`, `weather_records.timestamp`): Vorbedingung Länge 19/26, dann `replace(c,' ','T') || … || 'Z'`, eine Transaktion. `type(^x, RailsDateTime)` → `type(^x, :utc_datetime_usec)` (weather, weather/sync, sun_calendar, shading, solakon reading/snapshot/history); Roh-SQL (`pv_hour_aggregator.utc_text/1`, `lights/commands.record_zone_state`) über einen Helfer `Repo.dump_time/1`; `Clock.now` mit µs. `rails_date_time.ex` löschen. Grenztests je Fensterabfrage (Zeile genau auf `from` drin, auf `to` draußen).
  **Fertig:** auf migrierter Prod-Kopie 0 Zeilen außerhalb des Formats; `/api/today`, `/api/history`, ein vergangener Solakon-Tag, ein Berichtszeitraum, Sonnenkalender zeigen vorher/nachher dieselben Werte.
- **A2 – Stimulus → Hooks:** 12 Controller → `assets/js/hooks/*.js` (`mounted`/`updated`/`destroyed` mit `chart.destroy()`), `data-controller` → `phx-hook` + stabile `id`, `lib/*.js` relativ importiert, `stimulus.min.js` weg. LiveViewTests für jedes Hook-Element.

### Phase 2: Vertikale Scheiben S1–S4 parallel

Vorab (Claude): `core_components` (1.8-Stil, felt-css, deutsche Fehlertexte), neues `Ziwoas.GermanNumber` auf Elixir-Standard. Bis Phase 3 eingefroren: `ownership.ex`, `mqtt.ex`, `repo.ex`, `ruby_*`, `rails_cast.ex`, `form.ex`, `application.ex`, `owned.ex`, `layouts.ex`, `endpoint.ex`, `app.js`.

Jede Scheibe in ihren Pfaden: `Repo.write` auflösen, Ownership/Owned-Zweige streichen, Ruby-Kompat → Elixir-Standard, Changesets statt `Ziwoas.Form`, Turbo-Markup (`data-turbo-*`, `<turbo-frame>`, no-JS-Fallbacks) weg, Formulare als `<.form>`/`<.input>`, Bestätigungen per `data-confirm`.

| Scheibe | Bereich | Besonderes |
|---|---|---|
| S1 Energie | `energy*`, `energy_report/`, `plugs/`, `power_series`, `plot`, `trmnl/`, `live*`; Dashboard, Berichte, API, Health | Minutentakt als Timer in `DashboardLive`, `DashboardWatcher` weg; TRMNL-Payload ≤ 2 kB getestet |
| S2 PV/Wirtschaftlichkeit | `solakon*`, `economics*`, `shading/`, `sun*`; Solakon-, Verlauf-, Wirtschaftlichkeitsseiten | `EconomicsController` → `EconomicsLive`; `SolakonControlsController` weg; Dry-Run-Zweige in `Control.Tick`, `State.mirror_paused!`, `Outcome` weg |
| S3 Schalten/Lampen | `switching/`, `lights*`, `govee/`; Schalter- und Lampenseiten | erst `ScheduleEditing`-Helfer und `failed_message` in Context/LiveView, dann PlugSwitch-/SwitchWindow-/SwitchRule-/Light-Controller, `light_html`, `turbo_stream.ex` löschen; Helligkeit/Farbe als LiveView-Event statt `fetch` |
| S4 Sensoren/Wetter/Collector | `sensors*`, `weather*`, `collector*`, `fritz/`, `scheduler/`, `config.ex`, `http.ex`; Sensoren-, Wetterseite, Look | Collector ohne `owners`, Govee-Befehlsverbindung bleibt; Scheduler ohne `task`/`mode`/`shadow_offset`; `Config` warnt bei altem `migration:`-Block |

**Testlücken aus P0.1 (Vektoren weg):** Jede Scheibe schreibt idiomatische ExUnit-Tests für ihre Module, die bisher nur über Vektoren geprüft wurden:
- **S1:** `DailyEnergySummaryBuilder`, `ChartBuilder` (Labels über mehrere Tage), `Plugs.EnergyDeltas`, `ShellyStatusHandler` (Fehlerpfade)
- **S2:** `Solakon.Control.Policy` (surplus, probe, probe_blocked, Trimmung, Hitze-Drosselung; Vorrang), Ablauf nach Schreibfehlern in `Tick`/`MonitorJob`/`State`, `Monitor` `write_multiple_registers`, `PvHourAggregator`, `Payback`, `SavingsCalculator`, `PriceBook`, `Economics.Overview`, `SunCalc` (Polartag und Polarnacht)
- **S3:** Govee `CommandRouter`, `Messages`, `Types`, `DeviceRegistry`, `Lan`, `StateStore`
- **S4:** `Fritz.DectClient` (Fehlerpfade, 403 mit Neuanmeldung), `Weather.Sync` (Update eines bestehenden Datensatzes), `GermanNumber`

`router.ex`: S2 und S3 ändern getrennte Blöcke. **Fertig je Scheibe:** `git grep -E 'Repo\.write|Ownership|Owned|Ruby(Numeric|JSON|Date)|RailsCast|Ziwoas\.Form|turbo'` in ihren Pfaden leer, Gates grün.

### Phase 3: Aufräumen und Lint (sequenziell, Doku D parallel)

- Löschen: `Ownership`, `Repo.write`, `Owned`, `ruby_*.ex`, `rails_cast.ex`, `form.ex`, Paritätstest + `priv/rails_schema.sql`. `Mqtt.publish/5` → `/4`, `Trmnl.Push.run/4` → `/3` mit Aufrufern; `Mqtt.record` durch `FakeMqttBroker` ersetzen, wo möglich; Pipelines `:turbo`/`:json_writes` weg. `.credo.exs` + CI-Gate, `mix xref graph --format cycles`, `mix deps.unlock --check-unused`.
- **D – Doku:** CLAUDE.md, README, CONTEXT.md, ADR-0007. `.claude/skills/**` und `.claude/hooks/**` sind in der Sandbox schreibgeschützt: Löschen von `mutation-testing`, Pfade in `solakon-modbus`, Hook auf reines Elixir – mit Roberts Freigabe außerhalb der Sandbox.
- **Fertig:** `git grep -i -E 'rails|ruby|turbo|stimulus|shadow|lease'` trifft nur ADRs, Übernahme-Code und historische Notizen.

### Phase 4: Deployment und Generalprobe

- Dockerfile nach `phx.gen.release`, mehrstufig, Asset-Stufe auf `$BUILDPLATFORM`, Debian-Runtime mit `ca-certificates`, tzdata, `LANG=C.UTF-8`; amd64 + arm64. Compose: ein Dienst, `network_mode: host`, `PORT=3000`, Storage-Volume, `ziwoas.yml` read-only, `SECRET_KEY_BASE`, `PHX_HOST`, `check_origin`-Liste; Kommando `bin/migrate && exec bin/server`; Healthcheck `/up`. `docker.yml` publiziert mit explizitem Tag, nicht `latest` beim Merge.
- **Generalprobe** auf frischem Prod-Dump (Robert erlaubt Spiegeln): Übernahme + Migration mit Zeitmessung, Boot, alle Seiten, LiveView über den echten Hostnamen ohne Origin-Fehler; `docker buildx` für beide Architekturen.
- **MQTT-Probe (nur lesend, von Robert erlaubt):** lokale Config nur mit `mqtt` (echter Broker) und `plugs`, ohne Fritz/Govee/Solakon/SwitchBot/TRMNL; in der DB-Kopie `switch_rules` geleert, keine Klicks auf Schalter/Lampen. Phoenix nimmt Shelly-Status auf; Vergleich der neuen `samples` mit dem, was Rails gleichzeitig in Prod schreibt (über einen weiteren Dump). Kontrolle, dass Phoenix' Client-IDs nichts publizieren. Broker-Host/Zugang liefert Robert.
- Runbook als Markdown im Repo (`docs/cutover.md`) und Checkliste im Issue #158.

### Phase 5: Umstieg (Robert, per Runbook; Govee und Batterie gemeinsam live)

1. Rails-Image sichern (`docker image tag ziwoas:latest ziwoas:rails-final`), Phoenix-Image per Tag ziehen, neue Compose/Env bereitlegen, `migration:`-Block aus `ziwoas.yml`.
2. Alle drei Rails-Container stoppen (Modbus-Verbindung und UDP 4002 frei); prüfen, dass niemand `production.sqlite3` hält.
3. `.backup` nach `storage/backup/pre-phoenix-<datum>.sqlite3`, `integrity_check`.
4. Phoenix starten, Migrationslog lesen.
5. Smoke: `/up`, alle Seiten, `samples` wachsen, `solakon_readings` alle 30 s, Govee-State, Wetter und TRMNL binnen 15 min, Schalttakt binnen 1 min, Fritz, keine Origin-Fehler. Govee und Batterie gemeinsam.
6. Rückweg: Phoenix stoppen, Backup zurückkopieren, `-wal`/`-shm` löschen, `ziwoas:rails-final` starten (Daten seit dem Umstieg gehen verloren).
7. Nach stabilen Tagen: Solid-Queue/Cache/Cable-Dateien und alte Images löschen.

## Kritische Dateien

`elixir/lib/ziwoas/repo.ex`, `ownership.ex`, `application.ex`, `collector.ex`, `ecto/rails_date_time.ex`, `schema.ex`, `scheduler/runner.ex`, `solakon/monitor.ex`, `solakon/control/tick.ex`, `lib/ziwoas_web/router.ex`, `rails_assets.ex`, `components/layouts.ex`, `test/support/{data_case,conn_case,rails_fixture}.ex`, `priv/rails_schema.sql`, `mix.exs`, `config/{config,runtime,test}.exs`.

## Verifikation

- Je Paket die Gates; Laufprobe auf einer Prod-Kopie mit geräteloser Config; Klickrunde im Browser-Pane (Augenschein, Konsole, LiveView verbunden).
- Datenschicht: Migrate zweimal auf frischer Prod-Kopie, Zeilenzahlen, `integrity_check`, Formatprüfung der Zeitspalten, Vorher/Nachher-Zahlen von `/api/today`, `/api/history`, Berichten, Solakon-Verlauf.
- Ende: Docker-Build beider Architekturen, Generalprobe, MQTT-Probe; danach Umstieg nach Runbook.

## Größte Risiken

1. Langsamere Suite ohne async-DB-Tests; Prozesse, die ihren Test überleben.
2. Drift frisch vs. Prod (Affinität, AUTOINCREMENT) – Paritätstest und Prod-Kopie sind Pflicht.
3. Zeitgrenzen: ungetypte Parameter ohne `Z`; Umschreibung nur in einer Transaktion.
4. Hook-Lebenszyklus ohne Browser-Tests (Chart-Lecks, veraltete Daten) – LiveViewTest je Event plus Klickrunde.
5. Gerätezugriffe: echte Config lokal nach dem Umlegen würde schalten – deshalb nur gerätelose Configs und die eingeschränkte MQTT-Probe.
6. Branch-Drift zu `main` – Freeze ab Phase 0.
