import Config

config :ziwoas, Ziwoas.Repo,
  database: Path.expand("../tmp/test#{System.get_env("MIX_TEST_PARTITION")}.sqlite3", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 4

config :ziwoas, ZiwoasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "X8E/R8Yq9K4LprsBlve67ohdXwRGe52g9xcq6ZGqPGABDn5NWgIevYG7BqeTbgBC",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view, enable_expensive_runtime_checks: true

config :phoenix, sort_verified_routes_query_params: true

config :ziwoas, scheduler: false, collector: false

config :ziwoas, http_stubs: true, brightsky_retry_base_ms: 0

config :ziwoas, clock: Ziwoas.TestClock

config :ziwoas, govee_command_timeout_ms: 200
