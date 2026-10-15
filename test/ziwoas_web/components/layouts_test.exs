defmodule ZiwoasWeb.LayoutsTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.TestClock

  setup do
    TestClock.freeze("2026-05-04T12:00:00+02:00")
    :ok
  end

  describe "navigation" do
    test "brand, top navigation and tab bar navigate inside the live session", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sensors")

      assert has_element?(view, "header a.app-brand[data-phx-link=redirect][href='/']")

      for path <- ~w[/ /solakon /switches /reports /weather /sensors] do
        assert has_element?(
                 view,
                 "nav[aria-label=Hauptnavigation] a.nav-link[data-phx-link=redirect][href='#{path}']"
               )

        assert has_element?(
                 view,
                 "nav[aria-label=Tab-Leiste] a.nav-link[data-phx-link=redirect][href='#{path}']"
               )
      end

      assert has_element?(
               view,
               "nav[aria-label=Hauptnavigation] a.active[aria-current=page]",
               "Sensoren"
             )
    end

    test "a navigation link switches the LiveView without a page load", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sensors")

      {:ok, weather, _html} =
        view
        |> element("nav[aria-label=Hauptnavigation] a[href='/weather']")
        |> render_click()
        |> follow_redirect(conn, ~p"/weather")

      assert has_element?(weather, "h1", "Wetter")
      assert has_element?(weather, "nav[aria-label=Hauptnavigation] a.active", "Wetter")
    end
  end
end
