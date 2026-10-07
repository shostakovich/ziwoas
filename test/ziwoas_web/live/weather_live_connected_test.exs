defmodule ZiwoasWeb.WeatherLiveConnectedTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Repo, TestClock}
  alias Ziwoas.Weather.Record

  test "mounts, and reloads on a weather update", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/weather")
    assert html =~ ~r/<h1[^>]*>Wetter<\/h1>/

    send(view.pid, {:weather_updated})
    assert render(view) =~ "Wetter"
  end

  test "a segment tile opens its hours and closes the day's other one; again, it closes", %{
    conn: conn
  } do
    TestClock.freeze("2026-05-04T12:00:00+02:00")

    Repo.insert!(%Record{
      kind: "forecast",
      lat: 52.52,
      lon: 13.405,
      daytime: "day",
      icon: "clear-day",
      timestamp: ~U[2026-05-05 10:00:00.000000Z],
      temperature: 20.0
    })

    {:ok, view, _html} = live(conn, ~p"/weather")
    tile = &element(view, ".weather-segment[phx-value-day='2026-05-05'][phx-value-index='#{&1}']")
    selected = ".weather-segment.active.border-primary.bg-primary-subtle[aria-expanded=true]"

    render_click(tile.(1))
    assert has_element?(view, "#{selected}[phx-value-index='1']")
    assert has_element?(view, "#seg-2026-05-05-1:not([hidden])")

    render_click(tile.(2))
    refute has_element?(view, "#{selected}[phx-value-index='1']")
    assert has_element?(view, "#seg-2026-05-05-1[hidden]")
    assert has_element?(view, "#seg-2026-05-05-2:not([hidden])")

    send(view.pid, {:weather_updated})
    assert has_element?(view, "#{selected}[phx-value-index='2']")

    render_click(tile.(2))
    refute has_element?(view, selected)
    assert has_element?(view, "#seg-2026-05-05-2[hidden]")
  end
end
