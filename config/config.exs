import Config

# Ecto's migrations own the schema; `mix ecto.migrate` and Ziwoas.Release.migrate/0
# first adopt a database from the former Rails app (Ziwoas.Release).
config :ziwoas, ecto_repos: [Ziwoas.Repo]

# Read at runtime, where Mix.env/0 is gone (a release).
config :ziwoas, env: config_env()

# SQLite for one writer app: WAL, synchronous NORMAL, foreign keys, 64 MiB journal
# limit, 128 MiB mmap, 15 s busy timeout. The path is set in config/runtime.exs.
# Tables get `id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT`: ids are never reused.
config :ziwoas, Ziwoas.Repo,
  journal_mode: :wal,
  synchronous: :normal,
  foreign_keys: :on,
  busy_timeout: 15_000,
  journal_size_limit: 64 * 1024 * 1024,
  custom_pragmas: [mmap_size: 128 * 1024 * 1024],
  # A transaction that reads and then writes waits at BEGIN for the write lock instead of
  # failing with SQLITE_BUSY at its first write (Ziwoas.Repo).
  default_transaction_mode: :immediate,
  pool_size: 5,
  migration_primary_key: [type: :serial, null: false]

# The recurring jobs (Ziwoas.Scheduler): name => [schedule:, job:], schedules in the
# syntax of Ziwoas.Scheduler.Schedule.
config :ziwoas, Ziwoas.Scheduler,
  jobs: [
    aggregate_energy_samples: [
      schedule: "at 3:15am every day",
      job: Ziwoas.Plugs.AggregatorJob
    ],
    fetch_current_weather: [
      schedule: "every 15 minutes",
      job: Ziwoas.Weather.CurrentJob
    ],
    push_trmnl_widget: [
      schedule: "every 15 minutes",
      job: Ziwoas.Trmnl.EnergyPushJob
    ],
    fetch_today_weather: [schedule: "every hour", job: Ziwoas.Weather.TodayJob],
    fetch_weather_forecast: [
      schedule: "every 3 hours",
      job: Ziwoas.Weather.ForecastJob
    ],
    fetch_historic_weather: [
      schedule: "at 3:45am every day",
      job: Ziwoas.Weather.HistoricJob
    ],
    poll_sensors: [schedule: "every 15 minutes", job: Ziwoas.Sensors.PollJob],
    schedule_tick: [
      schedule: "every minute",
      job: Ziwoas.Switching.ScheduleTickJob
    ],
    solakon_monitor: [
      schedule: "every 30 seconds",
      job: Ziwoas.Solakon.MonitorJob
    ],
    solakon_snapshot: [
      schedule: "every 2 minutes",
      job: Ziwoas.Solakon.SnapshotJob
    ]
  ]

config :ziwoas, ZiwoasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ZiwoasWeb.ErrorHTML, json: ZiwoasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ziwoas.PubSub,
  live_view: [signing_salt: "WOLRJ7dh"]

config :phoenix_live_view, root_tag_attribute: "phx-r"

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Local day windows (Europe/Berlin and friends) need the IANA database.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# The standalone esbuild binary bundles assets/ into priv/static/assets (no Node).
config :esbuild,
  version: "0.28.2",
  ziwoas: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  ziwoas_css: [
    args: ~w(css/app.css --bundle --outdir=../priv/static/assets/css),
    cd: Path.expand("../assets", __DIR__)
  ]

# Elixir's built-in JSON instead of Jason.
config :phoenix, :json_library, JSON
config :ecto_sqlite3, json_library: JSON

import_config "#{config_env()}.exs"
