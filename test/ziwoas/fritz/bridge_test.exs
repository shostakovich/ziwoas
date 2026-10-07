defmodule Ziwoas.Fritz.BridgeTest do
  # The bridge process writes samples before the test could allow it the connection.
  use Ziwoas.DataCase

  import ExUnit.CaptureLog

  alias Ziwoas.Config.FritzPoll
  alias Ziwoas.Fritz.{Bridge, DectClient}
  alias Ziwoas.Plugs.Ingest
  alias Ziwoas.Plugs.Plug, as: PlugCfg
  alias Ziwoas.Plugs.Sample
  alias Ziwoas.Repo

  @moduletag :shared_sandbox

  @plug %PlugCfg{
    id: "robbebike",
    name: "Waschmaschine",
    role: :consumer,
    driver: :fritz_dect,
    ain: "08761 0500475"
  }
  @poll %FritzPoll{
    active_interval_seconds: 5,
    idle_interval_seconds: 60,
    idle_threshold_w: 10.0,
    timeout_seconds: 2
  }
  @now 1_700_000_000.0

  @session ~s(<?xml version="1.0"?><SessionInfo><SID>abc123def456abcd</SID><Challenge>deadbeef</Challenge></SessionInfo>)

  # A Fritz!Box that always answers: login, then `watts` mW and 100 Wh.
  defp client(milliwatts) do
    plug = fn conn ->
      body =
        case conn.query_params do
          %{"switchcmd" => "getswitchpower"} -> "#{milliwatts}\n"
          %{"switchcmd" => "getswitchenergy"} -> "100\n"
          _ -> @session
        end

      Plug.Conn.send_resp(conn, 200, body)
    end

    DectClient.new(host: "fritz.box", user: "u", password: "p", req: [plug: plug])
  end

  defp ingest_opts do
    test = self()
    [clock: fn -> @now end, broadcast: &send(test, {:broadcast, &1})]
  end

  defp state(client),
    do: %{
      plug: @plug,
      client: client,
      poll: @poll,
      ingest: Ingest.new(ingest_opts()),
      last_apower_w: 0.0
    }

  test "a poll records the reading as a sample of this plug and sends its live delta" do
    state = Bridge.poll(state(client(42_500)))

    assert [%Sample{plug_id: "robbebike", ts: 1_700_000_000, apower_w: 42.5, aenergy_wh: 100.0}] =
             Repo.all(Sample)

    assert_received {:broadcast, [%{id: "robbebike", apower_w: 42.5, output: nil}]}
    assert state.client.sid == "abc123def456abcd"
    assert state.last_apower_w == 42.5
  end

  test "the interval is active above the idle threshold, idle at or below it and before the first poll" do
    assert Bridge.interval(%{last_apower_w: 0.0, poll: @poll}) == 60
    assert Bridge.interval(%{last_apower_w: 10.0, poll: @poll}) == 60
    assert Bridge.interval(%{last_apower_w: 10.5, poll: @poll}) == 5
  end

  test "a Fritz error is logged and records nothing" do
    plug = fn conn -> Plug.Conn.send_resp(conn, 500, "") end
    client = DectClient.new(host: "fritz.box", user: "u", password: "p", req: [plug: plug])

    log =
      capture_log(fn ->
        state = Bridge.poll(state(client))
        assert state.last_apower_w == 0.0
      end)

    assert log =~ "FritzBridge robbebike: {:auth_status, 500}"
    assert Repo.all(Sample) == []
    refute_received {:broadcast, _}
  end

  test "the process polls at once and again after the interval" do
    test = self()

    pid =
      start_supervised!(
        {Bridge,
         plug: @plug,
         client: client(1000),
         poll: @poll,
         ingest: ingest_opts(),
         timer: fn pid, message, delay -> send(test, {:armed, pid, message, delay}) end}
      )

    assert_receive {:broadcast, [%{id: "robbebike"}]}, 5_000
    assert_receive {:armed, ^pid, :poll, delay}, 5_000
    assert delay == round(Bridge.interval(:sys.get_state(pid)) * 1000)

    send(pid, :poll)
    assert_receive {:armed, ^pid, :poll, _delay}, 5_000
  end

  test "by default the readings reach Plugs' subscribers" do
    Ziwoas.Plugs.subscribe()

    pid =
      start_supervised!(
        {Bridge, plug: @plug, client: client(1000), poll: %{@poll | idle_interval_seconds: 3600}}
      )

    assert_receive {:live, [%{id: "robbebike", apower_w: 1.0}]}, 5_000

    assert %{last_apower_w: 1.0, client: %DectClient{sid: "abc123def456abcd"}} =
             :sys.get_state(pid)
  end
end
