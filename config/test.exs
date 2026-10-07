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

# No dashboard beat, no scheduler and no device connections in tests: they run on
# their own schedule.
config :ziwoas, live_watchers: false, scheduler: false, collector: false

# Outbound HTTP goes to Req.Test stubs named after the client (Ziwoas.Http), and
# Bright Sky's retries do not wait.
config :ziwoas, http_stubs: true, brightsky_retry_base_ms: 0

# A frozen clock (Ziwoas.TestClock.freeze/1) and an MQTT recorder
# (Ziwoas.TestMqtt.record/1), both in test/support, seen by the processes a test
# starts as well.
config :ziwoas,
  frozen_clock: {Ziwoas.TestClock, :frozen},
  mqtt_recorder: {Ziwoas.TestMqtt, :recorder}
