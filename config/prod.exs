import Config

config :ziwoas, ZiwoasWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

config :ziwoas, forwarded_ssl: true

config :logger, level: :info
