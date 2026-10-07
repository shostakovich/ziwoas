defmodule ZiwoasWeb.SolakonControlsControllerTest do
  # test/controllers/solakon_controls_controller_test.rb, with the inverter a Modbus
  # TCP fake behind Phoenix's monitor, plus the PV page's switches as LiveView events.
  # Not async: it swaps the config path, which every process reads.
  use ZiwoasWeb.ConnCase, async: false, db: true

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Config, FakeModbusServer, Ownership, Repo}
  alias Ziwoas.Solakon.Monitor
  alias Ziwoas.Solakon.Control.State

  @moduletag :capture_log
  @inverter Ziwoas.TestConfigs.file(:inverter)

  setup %{repo: repo} do
    Repo.put_writer(:main, repo)
    Clock.freeze("2026-10-05T12:00:00+02:00")
    Ownership.override(%{solakon_control: :phoenix, solakon_monitor: :phoenix})
    previous = Application.fetch_env!(:ziwoas, :config_path)
    use_config(@inverter)

    on_exit(fn ->
      Application.delete_env(:ziwoas, :solakon_monitor)
      Application.put_env(:ziwoas, :config_path, previous)
      Config.reset()
      Ownership.clear_override()
    end)

    :ok
  end

  defp use_config(path) do
    Application.put_env(:ziwoas, :config_path, path)
    Config.reset()
  end

  defp inverter!(opts \\ []) do
    server = start_supervised!({FakeModbusServer, {%{"46609:1" => [10]}, opts}})

    monitor =
      start_supervised!(
        {Monitor, name: nil, host: "127.0.0.1", port: FakeModbusServer.port(server)}
      )

    Application.put_env(:ziwoas, :solakon_monitor, monitor)
    server
  end

  defp patch_json(conn, path, body),
    do:
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> patch(path, JSON.encode!(body))

  # The inverter config with the inverter's control switched off.
  defp control_disabled_config! do
    path =
      Path.join(
        System.tmp_dir!(),
        "ziwoas_control_disabled_#{System.unique_integer([:positive])}.yml"
      )

    File.write!(
      path,
      String.replace(File.read!(@inverter), "control_enabled: true", "control_enabled: false")
    )

    on_exit(fn -> File.rm(path) end)
    path
  end

  test "eps writes the outdoor socket's register through the monitor", %{conn: conn} do
    server = inverter!()

    conn = patch_json(conn, "/solakon/eps", %{enabled: "true"})

    assert conn.status == 200
    assert conn.resp_body == ~s({"enabled":true})
    assert conn |> get_resp_header("content-type") |> hd() =~ "application/json"
    assert FakeModbusServer.frames(server) == [["0001000000060106b6150002"]]
  end

  test "eps casts like ActiveModel: JSON false, \"0\" and a missing value switch off", %{
    conn: conn
  } do
    server = inverter!()

    assert patch_json(conn, "/solakon/eps", %{enabled: false}).resp_body == ~s({"enabled":false})

    assert patch_json(build_conn(), "/solakon/eps", %{enabled: "0"}).resp_body ==
             ~s({"enabled":false})

    assert patch_json(build_conn(), "/solakon/eps", %{}).resp_body == ~s({"enabled":null})

    assert patch_json(build_conn(), "/solakon/eps", %{enabled: "yes"}).resp_body ==
             ~s({"enabled":true})

    assert List.flatten(FakeModbusServer.frames(server)) == [
             "0001000000060106b6150000",
             "0001000000060106b6150000",
             "0001000000060106b6150000",
             "0001000000060106b6150002"
           ]
  end

  test "eps answers service unavailable on a Modbus failure", %{conn: conn} do
    inverter!(fail: ["6:46613"])

    conn = patch_json(conn, "/solakon/eps", %{enabled: "true"})

    assert conn.status == 503
    assert conn.resp_body == ~s({"error":"Schalten fehlgeschlagen"})
  end

  test "eps answers service unavailable without a monitor", %{conn: conn} do
    Application.put_env(:ziwoas, :solakon_monitor, :no_such_monitor)

    assert patch_json(conn, "/solakon/eps", %{enabled: true}).status == 503
  end

  test "the auto regulation pauses and resumes", %{conn: conn} do
    conn = patch_json(conn, "/solakon/control", %{active: "false"})

    assert conn.status == 200
    assert conn.resp_body == ~s({"active":false})
    refute State.active?(State.current())

    Repo.update!(
      Ecto.Changeset.change(State.current(),
        decision_state: "surplus",
        last_target_w: 400,
        last_decision_at: Clock.now()
      )
    )

    conn = patch_json(build_conn(), "/solakon/control", %{active: true})

    assert conn.resp_body == ~s({"active":true})
    state = State.current()
    assert State.active?(state)
    assert State.stored(state) == nil
  end

  test "a missing value pauses, as Rails' cast leaves nil", %{conn: conn} do
    assert patch_json(conn, "/solakon/control", %{}).resp_body == ~s({"active":false})
  end

  test "the auto regulation cannot be enabled when the config disables control", %{conn: conn} do
    Repo.insert!(%State{paused: true})
    use_config(control_disabled_config!())

    conn = patch_json(conn, "/solakon/control", %{active: "true"})

    assert conn.status == 403
    assert conn.resp_body == ~s({"error":"in Konfiguration deaktiviert"})
    refute State.active?(State.current())
  end

  test "without an inverter both routes answer service unavailable", %{conn: conn} do
    use_config(Ziwoas.TestConfigs.file(:test))

    assert patch_json(conn, "/solakon/eps", %{enabled: true}).resp_body ==
             ~s({"error":"Solakon nicht konfiguriert"})

    assert patch_json(build_conn(), "/solakon/control", %{active: true}).status == 503
  end

  test "a form-encoded body works too", %{conn: conn} do
    server = inverter!()

    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> patch("/solakon/eps", "enabled=true")

    assert conn.resp_body == ~s({"enabled":true})
    assert FakeModbusServer.frames(server) == [["0001000000060106b6150002"]]
  end

  describe "the PV page's switches" do
    test "the EPS switch writes and shows the new state", %{conn: conn} do
      server = inverter!()
      {:ok, view, _html} = live(conn, "/solakon")

      html = view |> element("#solakon-eps-toggle") |> render_click()

      assert FakeModbusServer.frames(server) == [["0001000000060106b6150002"]]
      assert html =~ ~r/data-solakon-target="epsState"[^>]*>\s*An\s*</

      view |> element("#solakon-eps-toggle") |> render_click()

      assert List.last(List.flatten(FakeModbusServer.frames(server))) ==
               "0001000000060106b6150000"
    end

    test "a failed EPS switch says so and keeps the state", %{conn: conn} do
      inverter!(fail: ["6:46613"])
      {:ok, view, _html} = live(conn, "/solakon")

      html = view |> element("#solakon-eps-toggle") |> render_click()

      doc = LazyHTML.from_fragment(html)
      [error] = doc |> LazyHTML.query("[data-solakon-target='epsError']") |> Enum.to_list()
      assert String.trim(LazyHTML.text(error)) == "Schalten fehlgeschlagen"
      assert LazyHTML.attribute(error, "hidden") == []
      assert html =~ ~r/data-solakon-target="epsState"[^>]*>\s*Aus\s*</
    end

    test "the Auto-Regelung switch pauses and resumes the loop", %{conn: conn} do
      {:ok, view, html} = live(conn, "/solakon")
      assert html =~ "folgt dem gemessenen Verbrauch"

      html = view |> element("#solakon-control-toggle") |> render_click()

      refute State.active?(State.current())
      assert html =~ ~r/data-solakon-target="controlState"[^>]*>\s*Pausiert\s*</
      assert html =~ ~r/data-solakon-target="controlHelp"[^>]*>\s*pausiert\s*</

      html = view |> element("#solakon-control-toggle") |> render_click()

      assert State.active?(State.current())
      assert html =~ ~r/data-solakon-target="controlState"[^>]*>\s*Aktiv\s*</
    end
  end
end
