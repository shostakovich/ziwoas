defmodule ZiwoasWeb.LightControllerTest do
  # Mirrors the settings half of test/controllers/lights_controller_test.rb.
  use ZiwoasWeb.ConnCase, async: true, db: true

  import ZiwoasWeb.TurboCase

  alias Ziwoas.{Ownership, Repo}
  alias Ziwoas.Lights.Light

  setup %{repo: repo} do
    Repo.put_writer(:main, repo)
    Ownership.override(%{light_settings: :phoenix})
    on_exit(&Ownership.clear_override/0)
    :ok
  end

  defp light!(attrs \\ %{}),
    do: Repo.insert!(struct!(%Light{name: "Lampe", key: "A1B2C3D4E5F60002"}, attrs))

  defp reload(light), do: Repo.get(Light, light.id)
  defp doc(conn, status), do: conn |> html_response(status) |> LazyHTML.from_document()

  test "update edits a light's name by key and returns to the detail page", %{conn: conn} do
    light = light!()
    conn = patch(conn, ~p"/lights/#{light.key}", %{"light" => %{"name" => "Stehlampe"}})

    assert redirected_to(conn) == "/lights/A1B2C3D4E5F60002"
    assert Phoenix.Flash.get(conn.assigns.flash, :notice) == "Lampe aktualisiert."
    assert reload(light).name == "Stehlampe"
  end

  test "update ignores capability params (bridge-managed) and keeps a blank plug choice", %{
    conn: conn
  } do
    light = light!(%{supports_color: false, shelly_plug_id: "fridge"})

    patch(conn, ~p"/lights/#{light.key}", %{
      "light" => %{
        "name" => "Neu",
        "supports_color" => "1",
        "key" => "HACK",
        "shelly_plug_id" => ""
      }
    })

    assert %{name: "Neu", supports_color: false, key: "A1B2C3D4E5F60002", shelly_plug_id: ""} =
             reload(light)
  end

  test "there is no index, create or destroy route", %{conn: conn} do
    light = light!()
    assert conn |> delete(~p"/lights/#{light.key}") |> response(404)
    assert conn |> get("/lights") |> response(404)
  end

  test "edit page renders the slim form with a plug dropdown", %{conn: conn} do
    light = light!(%{key: "A1B2C3D4E5F60010"})
    doc = conn |> get(~p"/lights/#{light.key}/edit") |> doc(200)

    assert count(doc, "input[name='light[name]']") == 1

    assert doc
           |> LazyHTML.query("select[name='light[shelly_plug_id]'] option")
           |> Enum.map(&String.trim(LazyHTML.text(&1))) ==
             ["— keine —", "Balkonkraftwerk", "Kühlschrank"]

    assert count(doc, "input[name='light[supports_color]']") == 0
    assert count(doc, "input[type=submit][value='Speichern']") == 1
    assert LazyHTML.text(LazyHTML.query(doc, "a.btn-outline-secondary")) =~ "Abbrechen"
  end

  test "update failure re-renders the form with errors and the dropdown", %{conn: conn} do
    light = light!(%{key: "A1B2C3D4E5F60011"})
    doc = conn |> patch(~p"/lights/#{light.key}", %{"light" => %{"name" => ""}}) |> doc(422)

    assert LazyHTML.text(LazyHTML.query(doc, ".alert-danger li")) == "Name can't be blank"
    assert count(doc, ".field_with_errors #light_name") == 1
    assert count(doc, "select.form-select[name='light[shelly_plug_id]']") == 1
    assert reload(light).name == "Lampe"
  end

  test "edit as turbo stream injects the settings sheet", %{conn: conn} do
    light = light!(%{key: "A1B2C3D4E5F60021"})

    body =
      conn
      |> Plug.Conn.put_req_header("accept", "text/vnd.turbo-stream.html")
      |> get(~p"/lights/#{light.key}/edit")
      |> stream_response(200)

    assert streams(body) == [{"update", "light_settings"}]
    doc = stream_doc(body)
    assert count(doc, "dialog.modal[closedby=any][data-controller=settings-dialog]") == 1
    assert count(doc, "button.btn-close") == 1
    assert body =~ "Abbrechen"
    assert body =~ "light[shelly_plug_id]"
  end

  test "update failure as turbo stream re-injects the sheet with errors", %{conn: conn} do
    light = light!(%{key: "A1B2C3D4E5F60022"})

    body =
      conn
      |> turbo()
      |> patch(~p"/lights/#{light.key}", %{"light" => %{"name" => "   "}})
      |> stream_response(422)

    assert streams(body) == [{"update", "light_settings"}]
    assert body =~ "<dialog"
    assert body =~ "alert-danger"
  end

  test "an update without light parameters is a bad request, an unknown lamp not found", %{
    conn: conn
  } do
    light = light!()
    assert conn |> patch(~p"/lights/#{light.key}", %{}) |> response(400)
    assert conn |> patch(~p"/lights/#{light.key}", %{"light" => %{}}) |> response(400)
    assert_error_sent 404, fn -> patch(conn, ~p"/lights/NOPE", %{"light" => %{"name" => "X"}}) end
    assert_error_sent 404, fn -> get(conn, ~p"/lights/NOPE/edit") end
  end

  test "the update answers 421 and writes nothing while Rails owns the settings", %{conn: conn} do
    light = light!()
    Ownership.override(%{light_settings: :rails})

    assert conn
           |> patch(~p"/lights/#{light.key}", %{"light" => %{"name" => "Neu"}})
           |> response(421)

    assert reload(light).name == "Lampe"
    assert conn |> get(~p"/lights/#{light.key}/edit") |> html_response(200)
  end

  describe "TurboStream.requested?/1 (Rails' respond_to)" do
    defp requested?(accept),
      do:
        ZiwoasWeb.TurboStream.requested?(Plug.Conn.put_req_header(build_conn(), "accept", accept))

    test "follows the Accept header" do
      assert requested?("text/vnd.turbo-stream.html, text/html, application/xhtml+xml")
      assert requested?("text/vnd.turbo-stream.html")
      assert requested?("*/*")
      refute requested?("text/html")
      refute requested?("text/html, text/vnd.turbo-stream.html")
      refute requested?("text/vnd.turbo-stream.html, */*")
      refute requested?("text/vnd.turbo-stream.html;q=0.5, text/html")
      refute ZiwoasWeb.TurboStream.requested?(build_conn())
    end
  end
end
