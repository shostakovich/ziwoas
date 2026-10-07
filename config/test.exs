import Config

# Every test runs in a transaction of the SQL sandbox (Ziwoas.DataCase), rolled back at
# its end. SQLite allows one writer at a time, so tests that touch the database run
# synchronously and need few connections. The `test` alias in mix.exs migrates the
# file first.
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

# No scheduler and no device connections in tests (read at compile time by
# Ziwoas.Application): they run on their own schedule.
config :ziwoas, scheduler: false, collector: false

# Read at compile time. Outbound HTTP goes to Req.Test stubs named after the client
# (Ziwoas.Http), and Bright Sky's retries do not wait.
config :ziwoas, http_stubs: true, brightsky_retry_base_ms: 0

# Read at compile time: a clock tests can freeze (Ziwoas.TestClock.freeze/1), in
# test/support, seen by the processes a test starts as well.
config :ziwoas, clock: Ziwoas.TestClock

# Read at compile time: a busy Govee bridge answers a command with an error this soon.
config :ziwoas, govee_command_timeout_ms: 200
