defmodule ZiwoasWeb.StaticAssetsTest do
  use ZiwoasWeb.ConnCase

  for path <-
        ~w[/images/zipfelmaus.webp /images/solakon_battery_normal.webp /favicon.png
           /apple-touch-icon.png /icon.png /icon.svg /robots.txt] do
    test "serves #{path} from priv/static", %{conn: conn} do
      assert get(conn, unquote(path)).status == 200
    end
  end
end
