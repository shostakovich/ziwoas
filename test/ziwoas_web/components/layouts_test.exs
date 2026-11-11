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

      for path <- ~w[/ /solakon /switches /reports /weather /sensors] do
        assert has_element?(view, "#{@dock} a[data-phx-link=redirect][href='#{path}']")
      end

      refute has_element?(view, "#{@dock} button[aria-haspopup=dialog]")
      refute has_element?(view, "#app-shell-more")
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

  describe "the resident" do
    setup do
      previous = Application.get_env(:ziwoas, :sign_out_url)
      on_exit(fn -> Application.put_env(:ziwoas, :sign_out_url, previous) end)
    end

    test "the top bar names the signed-in resident and offers „Abmelden“", %{conn: conn} do
      Application.put_env(:ziwoas, :sign_out_url, "https://gate.example.test/")
      {:ok, view, _html} = conn |> sign_in("anna") |> live(~p"/sensors")

      assert has_element?(view, "#account summary [data-resident]", "anna")

      assert has_element?(
               view,
               "#account a[href='https://gate.example.test/']",
               "Abmelden"
             )
    end

    test "without a sign-out address the top bar shows only the name", %{conn: conn} do
      Application.delete_env(:ziwoas, :sign_out_url)
      {:ok, view, _html} = conn |> sign_in("anna") |> live(~p"/sensors")

      assert has_element?(view, "span#account[data-resident]", "anna")
      refute has_element?(view, "a", "Abmelden")
    end

    test "an anonymous request shows no name", %{conn: conn} do
      Application.put_env(:ziwoas, :sign_out_url, "https://gate.example.test/")
      {:ok, view, _html} = live(conn, ~p"/sensors")

      refute has_element?(view, "[data-resident]")
      refute has_element?(view, "a", "Abmelden")
    end
  end
end
