defmodule ZiwoasWeb.StaticAssetsTest do
  use ZiwoasWeb.ConnCase, async: true

  for path <-
        ~w[/assets/zipfelmaus.webp /assets/application.css /assets/chart.min.js
           /assets/controllers/solakon_controller.js /assets/lib/chart_theme.js /favicon.png
           /apple-touch-icon.png /icon.png /icon.svg] do
    test "serves #{path} from priv/static", %{conn: conn} do
      assert get(conn, unquote(path)).status == 200
    end
  end

  test "the layout links every stylesheet in priv/static/assets, sorted" do
    on_disk =
      Application.app_dir(:ziwoas, "priv/static/assets/*.css")
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()

    assert "application.css" in on_disk
    assert ZiwoasWeb.Layouts.stylesheets() == on_disk
  end
end
