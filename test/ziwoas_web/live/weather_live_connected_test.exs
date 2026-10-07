defmodule ZiwoasWeb.WeatherLiveConnectedTest do
  # The connected LiveView reads the default (read-only fixture) repo: a LiveView
  # process does not inherit the test's dynamic repo.
  use ZiwoasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "mounts, and reloads on a weather update", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/weather")
    assert html =~ ~r/<h1[^>]*>Wetter<\/h1>/

    send(view.pid, {:weather_updated})
    assert render(view) =~ "Wetter"
  end
end
