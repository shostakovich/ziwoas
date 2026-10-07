defmodule ZiwoasWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ziwoas

  @session_options [
    store: :cookie,
    key: "_ziwoas_key",
    signing_salt: "upAgpXSP",
    same_site: "Lax"
  ]

  if Application.compile_env(:ziwoas, :assume_ssl, false) do
    plug ZiwoasWeb.AssumeSSL
  end

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # No JS bundler: the browser loads the Phoenix and LiveView ES modules straight from
  # the Hex packages via the import map in the root layout, versions pinned by mix.lock.
  plug Plug.Static,
    at: "/assets/vendor",
    from: {:phoenix, "priv/static"},
    only: ~w(phoenix.mjs)

  plug Plug.Static,
    at: "/assets/vendor",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.esm.js)

  plug Plug.Static,
    at: "/",
    from: :ziwoas,
    gzip: not code_reloading?,
    only: ZiwoasWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ZiwoasWeb.Router
end
