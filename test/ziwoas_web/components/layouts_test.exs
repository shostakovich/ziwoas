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

  describe "look toggle" do
    @toggle "button.app-look-toggle"

    test "switches the look in the browser and keeps the LiveView in step", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sensors")

      assert has_element?(view, "#{@toggle}[aria-pressed=false]:not(.active)")
      [click] = view |> element(@toggle) |> render() |> attribute("phx-click")

      assert [["dispatch", %{"event" => "ziwoas:set-look", "detail" => %{"look" => "felt"}}] | _] =
               JSON.decode!(click)

      view |> element(@toggle) |> render_click()

      assert has_element?(view, "#{@toggle}.active[aria-pressed=true]")
      [click] = view |> element(@toggle) |> render() |> attribute("phx-click")
      assert click =~ ~s("look":"clean")
    end

    test "a look switched in the browser reaches the next LiveView via connect params",
         %{conn: conn} do
      {:ok, view, _html} =
        conn |> put_connect_params(%{"look" => "felt"}) |> live(~p"/sensors")

      assert has_element?(view, "#{@toggle}.active[aria-pressed=true]")
    end

    test "the look cookie renders the felt look server-side", %{conn: conn} do
      doc =
        conn
        |> put_req_cookie("look", "felt")
        |> get(~p"/sensors")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert doc |> LazyHTML.query("html") |> LazyHTML.attribute("data-look") == ["felt"]

      assert doc |> LazyHTML.query("#{@toggle}.active") |> LazyHTML.attribute("aria-pressed") == [
               "true"
             ]
    end

    test "an unknown look falls back to clean", %{conn: conn} do
      doc =
        conn
        |> put_req_cookie("look", "neon")
        |> get(~p"/sensors")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert doc |> LazyHTML.query("html") |> LazyHTML.attribute("data-look") == []
      assert doc |> LazyHTML.query(@toggle) |> LazyHTML.attribute("aria-pressed") == ["false"]
    end

    test "PATCH /look is gone", %{conn: conn} do
      assert patch(conn, "/look", %{"look" => "felt"}).status == 404
    end
  end

  defp attribute(html, name),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.attribute(name)
end
