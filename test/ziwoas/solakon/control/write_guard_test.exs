defmodule Ziwoas.Solakon.Control.WriteGuardTest do
  # The proof behind dry_run: in every mode but phoenix no FC06/FC16 frame reaches the
  # inverter, whichever way a write is attempted — the Modbus functions themselves,
  # the monitor, the control tick, the PATCH routes and the PV page's events.
  use Ziwoas.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Config, FakeModbusServer, Ownership, Repo}
  alias Ziwoas.Plugs.Roster
  alias Ziwoas.Solakon.{Modbus, Monitor, Reading}
  alias Ziwoas.Solakon.Control.{State, Tick}

  @moduletag :capture_log
  @endpoint ZiwoasWeb.Endpoint

  @not_owner [
    %{solakon_control: :rails, solakon_monitor: :rails},
    %{solakon_control: :rails, solakon_monitor: :shadow},
    %{solakon_control: :dry_run, solakon_monitor: :shadow},
    %{solakon_control: :dry_run, solakon_monitor: :rails}
  ]

  setup %{repo: repo} do
    Repo.put_writer(:main, repo)
    Repo.put_writer(:shadow, repo)
    Clock.freeze("2026-10-05T10:00:00Z")
    server = start_supervised!({FakeModbusServer, %{"46609:1" => [10]}})

    monitor =
      start_supervised!(
        {Monitor, name: nil, host: "127.0.0.1", port: FakeModbusServer.port(server)}
      )

    Application.put_env(:ziwoas, :solakon_monitor, monitor)
    # The test config plus an inverter with control enabled.
    previous = Application.fetch_env!(:ziwoas, :config_path)

    Application.put_env(:ziwoas, :config_path, Ziwoas.TestConfigs.file(:inverter))

    on_exit(fn ->
      Application.delete_env(:ziwoas, :solakon_monitor)
      Application.put_env(:ziwoas, :config_path, previous)
      Config.reset()
      Ownership.clear_override()
    end)

    %{server: server, monitor: monitor}
  end

  defp writes(server) do
    for connection <- FakeModbusServer.frames(server),
        frame <- connection,
        binary_part(frame, 14, 2) in ["06", "10"],
        do: frame
  end

  for owners <- @not_owner do
    @owners owners
    describe "control #{owners.solakon_control}, monitor #{owners.solakon_monitor}" do
      setup do
        Ownership.override(@owners)
        :ok
      end

      test "the Modbus write functions raise before sending", %{server: server} do
        {:ok, socket} = Modbus.connect("127.0.0.1", FakeModbusServer.port(server), 1_000)

        assert_raise Ownership.NotOwnerError, fn ->
          Modbus.write_single_register(socket, 1, 1, 46001, 1, 1_000)
        end

        assert_raise Ownership.NotOwnerError, fn ->
          Modbus.write_multiple_registers(socket, 2, 1, 46003, [0, 300], 1_000)
        end

        Modbus.close(socket)
        assert writes(server) == []
      end

      test "the monitor refuses every write and stays up", %{server: server, monitor: monitor} do
        assert {:error, {:not_owner, _}} = Monitor.apply_control(monitor, 300, 10)
        assert {:error, {:not_owner, _}} = Monitor.set_eps_output(monitor, true)
        assert {:error, {:not_owner, _}} = Monitor.release_control(monitor)
        assert writes(server) == []
        assert Process.alive?(monitor)
      end

      test "the tick sends nothing", %{server: server, monitor: monitor} do
        reading = %Reading{battery_soc_pct: 55, pv_power_w: 300.0, battery_power_w: 0.0}
        roster = Roster.new([])

        if Ownership.runs?(:solakon_control) do
          outcome = Tick.run(reading, roster, Clock.now(), monitor: monitor)
          assert outcome.dry_run
          assert outcome.writes != []
        end

        assert writes(server) == []
      end

      test "the PATCH routes answer 421 and send nothing", %{server: server} do
        for {path, body} <- [
              {"/solakon/eps", %{enabled: true}},
              {"/solakon/control", %{active: false}}
            ] do
          conn =
            build_conn()
            |> Plug.Conn.put_req_header("accept", "application/json")
            |> patch(path, body)

          assert conn.status == 421
        end

        assert writes(server) == []
        assert Repo.aggregate(State, :count) == 0
      end

      test "the PV page's switches send nothing", %{server: server} do
        {:ok, view, _html} = live(build_conn(), "/solakon")

        html = view |> element("#solakon-eps-toggle") |> render_click()
        assert html =~ "Schalten fehlgeschlagen"
        html = view |> element("#solakon-control-toggle") |> render_click()
        assert html =~ "Umschalten fehlgeschlagen"

        assert writes(server) == []
        assert Repo.aggregate(State, :count) == 0
      end
    end
  end

  test "as owner the same paths do write", %{server: server, monitor: monitor} do
    Ownership.override(%{solakon_control: :phoenix, solakon_monitor: :phoenix})

    assert Monitor.set_eps_output(monitor, true) == :ok
    assert writes(server) == ["0001000000060106b6150002"]
    assert Config.app_config().solakon
  end
end
