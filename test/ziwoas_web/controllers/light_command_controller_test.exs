defmodule ZiwoasWeb.LightCommandControllerTest do
  # Mirrors test/controllers/lights_command_test.rb.
  use ZiwoasWeb.ConnCase, async: true, db: true

  import ZiwoasWeb.TurboCase

  alias Ziwoas.{Clock, Mqtt, Ownership, Repo}
  alias Ziwoas.Lights.{Commands, Light, State}

  setup %{repo: repo} do
    Clock.freeze("2026-06-15T17:00:00+02:00")
    Repo.put_writer(:main, repo)
    Ownership.override(%{lights: :phoenix})
    on_exit(&Ownership.clear_override/0)
    record(:ok)
    :ok
  end

  defp record(answer) do
    test = self()

    Mqtt.record(fn _client, topic, payload ->
      send(test, {:published, topic, payload})
      answer
    end)
  end

  defp light!(attrs), do: Repo.insert!(struct!(%Light{name: "Lampe"}, attrs))
  defp command(conn, key, params), do: post(conn, "/lights/#{key}/command", params)

  test "an unknown light is 404", %{conn: conn} do
    assert conn |> command("nope", %{"command" => "turn", "on" => "true"}) |> response(404)
  end

  test "an unknown command is 422", %{conn: conn} do
    light!(%{key: "A1"})
    assert conn |> command("A1", %{"command" => "explode"}) |> response(422)
    assert conn |> command("A1", %{}) |> response(422)
  end

  test "brightness answers 204 without a content type", %{conn: conn} do
    light!(%{key: "S3", zones: []})
    conn = command(conn, "S3", %{"command" => "brightness", "value" => "42"})
    assert response(conn, 204) == ""
    assert get_resp_header(conn, "content-type") == []
    assert_received {:published, "govees/S3/set", ~s({"brightness":42})}
  end

  test "effect forwards the scene name", %{conn: conn} do
    light!(%{key: "A1"})
    assert conn |> command("A1", %{"command" => "effect", "effect" => "Forest"}) |> response(204)
    assert_received {:published, "govees/A1/set", ~s({"scene":"Forest"})}
  end

  test "a broker failure is 503", %{conn: conn} do
    record({:error, :timeout})
    light!(%{key: "A1"})
    assert conn |> command("A1", %{"command" => "turn", "on" => "true"}) |> response(503)
  end

  test "turn records the state and streams the hero and the Schalten tile", %{conn: conn} do
    light!(%{key: "S9", zones: []})

    body =
      conn
      |> turbo()
      |> command("S9", %{"command" => "turn", "on" => "true"})
      |> stream_response(200)

    assert streams(body) == [{"replace", "light_power"}, {"replace", "light_card_S9"}]
    assert Repo.get_by(State, light_key: "S9").on == true
  end

  test "a zone streams its button; an eviction streams the evicted one and the toast", %{
    conn: conn
  } do
    light!(%{
      key: "UP3",
      sku: "H60B0",
      zones: ~w[bottomLightToggle rippleLightToggle sideLightToggle]
    })

    Commands.record_zone_state("UP3", "bottomLightToggle", true)
    Commands.record_zone_state("UP3", "rippleLightToggle", true)

    body =
      conn
      |> turbo()
      |> command("UP3", %{"command" => "zone", "zone" => "sideLightToggle", "on" => "true"})
      |> stream_response(200)

    assert streams(body) == [
             {"replace", "zone_sideLightToggle"},
             {"replace", "zone_rippleLightToggle"},
             {"replace", "light_toast"}
           ]

    doc = stream_doc(body)

    assert LazyHTML.text(LazyHTML.query(doc, "#light_toast span")) ==
             "Welle ausgeschaltet · max. 2 Zonen"

    assert count(doc, "#light_toast input[name=command][value=zone_undo]") == 1
    assert count(doc, "#light_toast:not([hidden])") == 1

    assert Repo.get_by(State, light_key: "UP3").zone_states ==
             %{
               "bottomLightToggle" => true,
               "rippleLightToggle" => false,
               "sideLightToggle" => true
             }
  end

  test "undo clears the toast", %{conn: conn} do
    light!(%{key: "UP4", zones: ~w[rippleLightToggle sideLightToggle]})

    body =
      conn
      |> turbo()
      |> command("UP4", %{
        "command" => "zone_undo",
        "victim" => "rippleLightToggle",
        "added" => "sideLightToggle"
      })
      |> stream_response(200)

    assert {"replace", "light_toast"} in streams(body)
    assert count(stream_doc(body), "#light_toast[hidden]") == 1
  end

  test "421 while Phoenix does not own lights, before anything is sent", %{conn: conn} do
    light!(%{key: "A1"})

    for mode <- [:rails, :dry_run] do
      Ownership.override(%{lights: mode})
      assert conn |> command("A1", %{"command" => "turn", "on" => "true"}) |> response(421)
    end

    refute_received {:published, _, _}
    assert Repo.all(State) == []
  end
end
