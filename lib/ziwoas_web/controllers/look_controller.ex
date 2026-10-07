defmodule ZiwoasWeb.LookController do
  @moduledoc "Switches the look (Rails' `LooksController#update`): a permanent cookie, then back."
  use ZiwoasWeb, :controller

  alias Ziwoas.Look

  # Rails' `cookies.permanent`: 20 years.
  @max_age 20 * 365 * 24 * 60 * 60

  def update(conn, params) do
    look = params["look"]

    if Look.valid?(look) do
      conn
      |> put_resp_cookie(Look.cookie(), look,
        max_age: @max_age,
        sign: false,
        http_only: false,
        same_site: "Lax"
      )
      |> put_status(:see_other)
      |> redirect(external: back_url(conn))
    else
      send_resp(conn, :bad_request, "")
    end
  end

  # redirect_back_or_to: the Referer when it points here, else the root.
  defp back_url(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host} = uri when host in [nil, conn.host] <- URI.parse(referer) do
      URI.to_string(%URI{uri | scheme: nil, host: nil, port: nil, userinfo: nil, authority: nil})
    else
      _ -> "/"
    end
  end
end
