defmodule ZiwoasWeb.StaticAssetsTest do
  # Only files in git: the esbuild bundles under /assets are build output, so `mix test`
  # stays green on a fresh checkout. CI builds them (`mix assets.deploy`), which fails on
  # an import that does not resolve; `~p` already verifies at compile time that the
  # layout's /assets paths are static paths.
  use ZiwoasWeb.ConnCase

  for path <-
        ~w[/images/zipfelmaus.webp /images/solakon_battery_normal.webp /favicon.png
           /apple-touch-icon.png /icon.png /icon.svg /robots.txt] do
    test "serves #{path} from priv/static", %{conn: conn} do
      assert get(conn, unquote(path)).status == 200
    end
  end
end
