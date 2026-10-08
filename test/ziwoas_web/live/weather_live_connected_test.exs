defmodule ZiwoasWeb.WeatherLiveConnectedTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Repo, Sensors, TestClock, Weather}
  alias Ziwoas.Weather.Record

  defp current!(temperature) do
    Repo.insert!(%Record{
      kind: :current,
      lat: 52.52,
      lon: 13.405,
      daytime: "day",
      icon: "cloudy",
      timestamp: Clock.now(),
      temperature: temperature
    })
  end

  test "reloads after a weather sync", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/weather")
    refute has_element?(view, ".weather-current")

    current!(17.5)
    Weather.notify_synced(Clock.today("Europe/Berlin"))

    assert has_element?(view, ".weather-current .stat-value", "17,5")
  end

  test "reloads after a sensor poll: the outdoor sensor's temperature", %{conn: conn} do
    current!(17.5)
    {:ok, view, _html} = live(conn, ~p"/weather")
    assert has_element?(view, ".weather-current .stat-value", "17,5")

    outdoor = Enum.find(Ziwoas.Config.get().sensors, &(&1.type == :outdoor_meter))
    {:ok, _} = Sensors.create_reading(outdoor.id, Clock.now(), %{temperature: 9.3})
    Sensors.notify_polled(Clock.now())

    assert has_element?(view, ".weather-current .stat-value", "9,3")
  end

  test "a toggle with a day or segment the page does not have changes nothing", %{conn: conn} do
    TestClock.freeze("2026-05-04T12:00:00+02:00")
    forecast!()
    {:ok, view, _html} = live(conn, ~p"/weather")

    for params <- [
          %{"day" => "2026-05-05", "index" => "x"},
          %{"day" => "2026-05-05", "index" => "7"},
          %{"day" => "2026-05-05", "index" => 1},
          %{"index" => "1"},
          %{}
        ] do
      render_hook(view, "toggle_segment", params)
    end

    assert has_element?(view, ".weather-segment[phx-value-day='2026-05-05']")
    refute has_element?(view, ".weather-segment.active")
  end

  defp forecast! do
    Repo.insert!(%Record{
      kind: :forecast,
      lat: 52.52,
      lon: 13.405,
      daytime: "day",
      icon: "clear-day",
      timestamp: ~U[2026-05-05 10:00:00.000000Z],
      temperature: 20.0
    })
  end

  test "a segment tile opens its hours and closes the day's other one; again, it closes", %{
    conn: conn
  } do
    TestClock.freeze("2026-05-04T12:00:00+02:00")
    forecast!()

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

    Weather.notify_synced(~D[2026-05-04])
    assert has_element?(view, "#{selected}[phx-value-index='2']")

    render_click(tile.(2))
    refute has_element?(view, selected)
    assert has_element?(view, "#seg-2026-05-05-2[hidden]")
  end
end
