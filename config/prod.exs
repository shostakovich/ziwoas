import Config

# `mix assets.deploy` digests priv/static (phx.digest); ~p paths then name the digested files.
config :ziwoas, ZiwoasWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

# TLS ends at the reverse proxy: what it forwards as HTTPS gets HSTS and Secure cookies,
# plain HTTP from the LAN stays usable (ZiwoasWeb.ForwardedSSL).
config :ziwoas, forwarded_ssl: true

config :logger, level: :info
