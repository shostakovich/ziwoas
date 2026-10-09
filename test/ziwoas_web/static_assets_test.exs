defmodule ZiwoasWeb.StaticAssetsTest do
  use ZiwoasWeb.ConnCase

  for path <-
        ~w[/images/zipfelmaus.webp /images/solakon_battery_normal.webp /images/favicon.svg
           /images/favicon.png /images/apple-touch-icon.png /robots.txt] do
    test "serves #{path} from priv/static", %{conn: conn} do
      assert get(conn, unquote(path)).status == 200
    end
  end

  # In production `~p` points at digested names such as `/images/favicon-1a2b.png`.
  # Plug.Static only serves those when their first segment is a static path, so a
  # root-level `/favicon.png` would turn into an unserved `/favicon-1a2b.png`.
  test "links icons from a static path, so their digested names are served too", %{conn: conn} do
    hrefs =
      conn
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query(~s(link[rel~="icon"], link[rel="apple-touch-icon"]))
      |> LazyHTML.attribute("href")

    assert hrefs != []

    for href <- hrefs do
      digested = Path.rootname(href) <> "-0123456789abcdef" <> Path.extname(href)
      [segment | _] = String.split(digested, "/", trim: true)
      assert segment in ZiwoasWeb.static_paths(), "#{digested} would not be served"
    end
  end
end
