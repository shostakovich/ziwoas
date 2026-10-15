defmodule ZiwoasWeb.LayoutsTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.TestClock

  setup do
    TestClock.freeze("2026-05-04T12:00:00+02:00")
    :ok
  end

  @dock "nav.dock"

  defp page(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()
  defp attrs(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  describe "navigation" do
    test "brand, top bar and dock navigate inside the live session", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sensors")

      assert has_element?(
               view,
               "header a[aria-label='Zipfelmaus — Startseite'][data-phx-link=redirect][href='/']"
             )

      for path <- ~w[/ /solakon /switches /reports /weather /sensors] do
        assert has_element?(view, "#app-shell-nav a[data-phx-link=redirect][href='#{path}']")
      end

      for path <- ~w[/ /solakon /switches /sensors] do
        assert has_element?(view, "#{@dock} a[data-phx-link=redirect][href='#{path}']")
      end

      refute has_element?(view, "#{@dock} a[href='/reports']")
      refute has_element?(view, "#{@dock} a[href='/weather']")
      assert has_element?(view, "#{@dock} button[aria-haspopup=dialog]", "Mehr")
      assert has_element?(view, "#app-shell-more a[href='/reports']")
      assert has_element?(view, "#app-shell-more a[href='/weather']")
      assert has_element?(view, "#app-shell-nav a[aria-current=page]", "Sensoren")
    end

    test "a navigation link switches the LiveView without a page load", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sensors")

      {:ok, weather, _html} =
        view
        |> element("#app-shell-nav a[href='/weather']")
        |> render_click()
        |> follow_redirect(conn, ~p"/weather")

      assert has_element?(weather, "h1", "Wetter")
      assert has_element?(weather, "#app-shell-nav a[aria-current=page]", "Wetter")
    end
  end

  describe "shell" do
    test "offers the colour scheme, System first, and one confirmation dialog", %{conn: conn} do
      doc = page(conn, ~p"/sensors")

      assert attrs(doc, "#theme-toggle-menu > summary", "title") == ["Farbschema"]
      assert attrs(doc, "#theme-toggle input[type=radio]", "value") == ~w(system light dark)
      assert attrs(doc, "#theme-toggle input[checked]", "value") == ["system"]
      assert count(doc, "dialog#confirm-delete") == 1
      assert count(doc, "#flash-group") == 1
    end

    test "the head sets the theme before paint and preloads the bundled Figtree", %{conn: conn} do
      doc = page(conn, ~p"/sensors")

      assert attrs(doc, "html", "lang") == ["de"]
      assert attrs(doc, "html", "data-look") == []
      assert attrs(doc, "meta[name=theme-color]", "media") |> length() == 2
      assert count(doc, "head script:not([src])") == 1

      assert attrs(doc, "link[rel=preload][as=font]", "href") == [
               "/setzkasten/fonts/Figtree-Variable.woff2"
             ]
    end
  end
end
