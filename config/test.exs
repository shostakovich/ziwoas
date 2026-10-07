import Config

# The `test` alias in mix.exs builds this file from the Rails fixtures before the app starts.
config :ziwoas, Ziwoas.Repo,
  database: Path.expand("../tmp/test#{System.get_env("MIX_TEST_PARTITION")}.sqlite3", __DIR__),
  pool_size: 2

config :ziwoas, ZiwoasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "X8E/R8Yq9K4LprsBlve67ohdXwRGe52g9xcq6ZGqPGABDn5NWgIevYG7BqeTbgBC",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view, enable_expensive_runtime_checks: true

config :phoenix, sort_verified_routes_query_params: true

# No polling bridges, no scheduler and no device connections in tests: they run on
# their own schedule.
config :ziwoas, live_watchers: false, scheduler: false, collector: false

# No owner leases (Ziwoas.Lease): tests own tasks through Ownership.override/1;
# test/ziwoas/lease_test.exs turns them on.
config :ziwoas, leases: false

# Outbound HTTP goes to Req.Test stubs named after the client (Ziwoas.Http), and
# Bright Sky's retries do not wait.
config :ziwoas, http_stubs: true, brightsky_retry_base_ms: 0

# A process a test starts (a LiveView, a scheduler runner) reads the test's writable
# database and writers (Ziwoas.Repo.put_writer/2), the clock it froze
# (Ziwoas.Clock.freeze/1), the owners it set (Ziwoas.Ownership.override/1) and its
# MQTT recorder (Ziwoas.Mqtt.record/1).
config :ziwoas,
  inherit_dynamic_repo: true,
  clock_process_override: true,
  ownership_process_override: true,
  mqtt_recorder: true
