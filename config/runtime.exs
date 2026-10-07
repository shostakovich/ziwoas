import Config

if System.get_env("PHX_SERVER") do
  config :ziwoas, ZiwoasWeb.Endpoint, server: true
end

config :ziwoas, ZiwoasWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :ziwoas, shelly_port: String.to_integer(System.get_env("SHELLY_PORT", "4001"))

path_env = fn name, example, default ->
  cond do
    path = System.get_env(name) -> path
    config_env() == :prod -> raise "environment variable #{name} is missing, e.g. #{example}"
    true -> default
  end
end

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

# Tests set their database in config/test.exs.
if config_env() != :test do
  database =
    path_env.(
      "ZIWOAS_DB",
      "/app/storage/production.sqlite3",
      Path.expand("../storage/development.sqlite3", __DIR__)
    )

  config :ziwoas, Ziwoas.Repo, database: database

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

  # Scheme-less: the origin check runs before ForwardedSSL, so it cannot compare schemes.
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
