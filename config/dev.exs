import Config

config :ziwoas, Ziwoas.Repo,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :ziwoas, ZiwoasWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "naHt66UR00Dd+tvCuNlqtIyHzTNmFKhqkXV0fR6zZRTzis+kt85G/eqhQoMWxVCA",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:ziwoas, ~w(--sourcemap=inline --watch)]},
    esbuild_css: {Esbuild, :install_and_run, [:ziwoas_css, ~w(--sourcemap=inline --watch)]}
  ]

config :ziwoas, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
