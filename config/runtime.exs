import Config

if System.get_env("PHX_SERVER") do
  config :ziwoas, ZiwoasWeb.Endpoint, server: true
end

config :ziwoas, ZiwoasWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# The Shelly plugs' outbound websockets connect here (Ziwoas.Shelly.Listener).
config :ziwoas, shelly_port: String.to_integer(System.get_env("SHELLY_PORT", "4001"))

# A release (prod) names every path; development and tests default to this checkout.
path_env = fn name, example, default ->
  cond do
    path = System.get_env(name) -> path
    config_env() == :prod -> raise "environment variable #{name} is missing, e.g. #{example}"
    true -> default
  end
end

# The device configuration (ADR-0004 keeps prices out of it). ZIWOAS_CONFIG overrides
# the path; tests read test/fixtures/ziwoas.test.yml, development config/ziwoas.yml.
config :ziwoas,
  config_path:
    path_env.(
      "ZIWOAS_CONFIG",
      "/app/config/ziwoas.yml",
      Path.expand(
        if(config_env() == :test,
          do: "../test/fixtures/ziwoas.test.yml",
          else: "ziwoas.yml"
        ),
        __DIR__
      )
    )

# The database. ZIWOAS_DB overrides the path; dev defaults to storage/development.sqlite3.
# Tests always use tmp/test.sqlite3 (config/test.exs): the sandbox wraps every test in a
# transaction, but `mix test` migrates the file first.
if config_env() != :test do
  database =
    path_env.(
      "ZIWOAS_DB",
      "/app/storage/production.sqlite3",
      Path.expand("../storage/development.sqlite3", __DIR__)
    )

  config :ziwoas, Ziwoas.Repo, database: database

  # The aggregator's nightly backups (Ziwoas.Plugs.AggregatorJob), next to the database.
  config :ziwoas, backup_dir: Path.join(Path.dirname(database), "backup")
end

if config_env() == :prod do
  config :ziwoas, Ziwoas.Repo, pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  phx_host = System.get_env("PHX_HOST", "localhost")

  # LiveView's websocket accepts PHX_HOST and the hosts in ZIWOAS_ALLOWED_HOSTS
  # ("ziwoas.example.org,192.168.1.50") as Origin, any scheme and port.
  # The origin check runs before ForwardedSSL, so it cannot compare schemes behind the proxy.
  check_origin =
    System.get_env("ZIWOAS_ALLOWED_HOSTS", "")
    |> String.split(",", trim: true)
    |> Enum.concat([phx_host])
    |> Enum.map(fn host ->
      host = host |> String.trim() |> String.replace(~r{^\w+://}, "") |> String.trim_trailing("/")
      host = String.replace(host, ~r/^\./, "*.")
      "//" <> host
    end)
    |> Enum.uniq()

  config :ziwoas, ZiwoasWeb.Endpoint,
    url: [host: phx_host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}],
    check_origin: check_origin,
    secret_key_base: secret_key_base
end
