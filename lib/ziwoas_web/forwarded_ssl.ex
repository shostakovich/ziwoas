defmodule ZiwoasWeb.ForwardedSSL do
  @moduledoc """
  TLS ends at the reverse proxy. A request it forwarded as HTTPS
  (`X-Forwarded-Proto: https`) counts as HTTPS: its response carries an HSTS header
  (2 years, subdomains) and flags its cookies `Secure`. A plain request straight to
  the port, say from the LAN, stays HTTP, so the browser keeps its session cookie.
  The endpoint plugs it first when `config :ziwoas, forwarded_ssl: true` (prod).
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(_opts), do: Plug.SSL.init(expires: 63_072_000, subdomains: true, exclude: [])

  @impl true
  def call(conn, ssl) do
    if forwarded_https?(conn) do
      %{conn | scheme: :https, port: 443}
      |> Plug.SSL.call(ssl)
      |> register_before_send(&secure_cookies/1)
    else
      conn
    end
  end

  defp forwarded_https?(conn) do
    case get_req_header(conn, "x-forwarded-proto") do
      [proto | _] ->
        proto |> String.split(",") |> hd() |> String.trim() |> String.downcase() == "https"

      [] ->
        false
    end
  end

  defp secure_cookies(conn) do
    cookies =
      Map.new(conn.resp_cookies, fn {key, opts} -> {key, Map.put(opts, :secure, true)} end)

    %{conn | resp_cookies: cookies}
  end
end
