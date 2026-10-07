defmodule ZiwoasWeb.PlugSwitchControllerTest do
  # Mirrors test/controllers/plug_switches_controller_test.rb.
  use ZiwoasWeb.ConnCase, async: true, db: true

  import ZiwoasWeb.TurboCase

  alias Ziwoas.{Clock, Mqtt, Ownership, Repo}
  alias Ziwoas.Switching.Command

  setup %{repo: repo, conn: conn} do
    Clock.freeze("2026-06-15T17:00:00+02:00")
    Repo.put_writer(:main, repo)
    Ownership.override(%{switching: :phoenix})
    on_exit(&Ownership.clear_override/0)
    record(:ok)
    {:ok, conn: turbo(conn)}
  end

  defp record(answer) do
    test = self()

    Mqtt.record(fn _client, topic, payload ->
      send(test, {:published, topic, payload})
      answer
    end)
  end

  test "an unknown plug is 404", %{conn: conn} do
    assert conn |> post("/plugs/nope/switch", %{"state" => "on"}) |> response(404) == ""
  end

  test "a plug that does not switch is 422", %{conn: conn} do
    conn = post(conn, "/plugs/bkw/switch", %{"state" => "on"})
    assert response(conn, 422) == ""
    # Rails' head in an action answers the negotiated format.
    assert [<<"text/vnd.turbo-stream.html", _::binary>>] = get_resp_header(conn, "content-type")
  end

  test "an invalid state is 422", %{conn: conn} do
    for state <- ["toggle", "ON", nil] do
      assert conn |> post("/plugs/fridge/switch", %{"state" => state}) |> response(422)
    end

    refute_received {:published, _, _}
  end

  test "a valid switch publishes, logs a manual command and streams the head", %{conn: conn} do
    Repo.insert!(%Ziwoas.Plugs.Sample{
      plug_id: "fridge",
      ts: Clock.unix_now() - 5,
      apower_w: 1.0,
      aenergy_wh: 1.0
    })

    body = conn |> post("/plugs/fridge/switch?state=on") |> stream_response(200)

    assert_received {:published, "shellies/fridge/command/switch:0", "on"}
    assert streams(body) == [{"replace", "sw_head_fridge"}]
    assert [%Command{plug_id: "fridge", action: "on", source: "manual"}] = Repo.all(Command)
    assert stream_doc(body) |> LazyHTML.text() =~ "An seit 17:00 (manuell)"
  end

  test "a broker failure is 503 with the error streamed in and no command", %{conn: conn} do
    record({:error, :timeout})
    body = conn |> post("/plugs/fridge/switch", %{"state" => "on"}) |> stream_response(503)

    assert streams(body) == [{"update", "sw_error_fridge"}]
    assert body =~ "nicht erreichbar"
    assert Repo.all(Command) == []
  end

  test "421 while Phoenix does not own switching, before anything is sent", %{conn: conn} do
    for mode <- [:rails, :dry_run] do
      Ownership.override(%{switching: mode})
      assert conn |> post("/plugs/fridge/switch", %{"state" => "on"}) |> response(421)
    end

    refute_received {:published, _, _}
    assert Repo.all(Command) == []
  end
end
