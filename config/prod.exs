import Config

# `mix assets.deploy` digests priv/static (phx.digest); ~p paths then name the digested files.
config :ziwoas, ZiwoasWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

# Rails' assume_ssl + force_ssl (config/environments/production.rb): TLS ends at the
# reverse proxy; every request counts as HTTPS, HSTS and Secure cookies (ZiwoasWeb.AssumeSSL).
config :ziwoas, assume_ssl: true

config :logger, level: :info
