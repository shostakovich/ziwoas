import Config

# Rails' assume_ssl + force_ssl (config/environments/production.rb): TLS ends at the
# reverse proxy; every request counts as HTTPS, HSTS and Secure cookies (ZiwoasWeb.AssumeSSL).
config :ziwoas, assume_ssl: true

config :logger, level: :info
