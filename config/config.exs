import Config

config :ziwoas, ecto_repos: [Ziwoas.Repo]

config :ziwoas, Ziwoas.Repo,
  journal_mode: :wal,
  synchronous: :normal,
  foreign_keys: :on,
  busy_timeout: 15_000,
  journal_size_limit: 64 * 1024 * 1024,
  custom_pragmas: [mmap_size: 128 * 1024 * 1024],
  # A deferred read-then-write fails with SQLITE_BUSY at once; immediate ones wait at BEGIN.
  default_transaction_mode: :immediate,
  pool_size: 5,
  # :serial is AUTOINCREMENT in SQLite, so ids are never reused.
  migration_primary_key: [type: :serial, null: false]

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

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

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

config :phoenix, :json_library, JSON
config :ecto_sqlite3, json_library: JSON

import_config "#{config_env()}.exs"
