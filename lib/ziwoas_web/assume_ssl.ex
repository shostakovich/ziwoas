defmodule ZiwoasWeb.AssumeSSL do
  @moduledoc """
  TLS ends at the reverse proxy, so every request counts as HTTPS (no redirect,
  whatever the proxy forwards), and every response carries an HSTS header (2 years,
  subdomains) and flags its
  cookies `Secure`. The endpoint plugs it first when `config :ziwoas,
  assume_ssl: true` (prod).
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(_opts), do: Plug.SSL.init(expires: 63_072_000, subdomains: true, exclude: [])

  @impl true
  def call(conn, ssl) do
    %{conn | scheme: :https, port: 443}
    |> Plug.SSL.call(ssl)
    |> register_before_send(&secure_cookies/1)
  end

  defp secure_cookies(conn) do
    cookies =
      Map.new(conn.resp_cookies, fn {key, opts} -> {key, Map.put(opts, :secure, true)} end)

    %{conn | resp_cookies: cookies}
  end
end
