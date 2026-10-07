defmodule Ziwoas.Fritz.BridgeTest do
  # The broker connection and its backoff are Tortoise's (MqttIntegrationTest).
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ziwoas.Config.FritzPoll
  alias Ziwoas.Fritz.{Bridge, DectClient}
  alias Ziwoas.Plugs.Plug, as: PlugCfg

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

  defp state(client, publish),
    do: %{
      plug: @plug,
      client: client,
      poll: @poll,
      topic_prefix: "shellies",
      publish: publish,
      last_apower_w: 0.0
    }

  test "a poll publishes the reading as a Shelly status of this plug" do
    test = self()
    state = Bridge.poll_and_publish(state(client(42_500), &send(test, {:published, &1, &2})))

    assert_received {:published, "shellies/robbebike/status/switch:0", payload}
    assert Jason.decode!(payload) == %{"apower" => 42.5, "aenergy" => %{"total" => 100.0}}

    assert state.client.sid == "abc123def456abcd"
    assert state.last_apower_w == 42.5
  end

  test "the interval is active above the idle threshold, idle at or below it and before the first poll" do
    assert Bridge.interval(%{last_apower_w: 0.0, poll: @poll}) == 60
    assert Bridge.interval(%{last_apower_w: 10.0, poll: @poll}) == 60
    assert Bridge.interval(%{last_apower_w: 10.5, poll: @poll}) == 5
  end

  test "a Fritz error is logged and publishes nothing" do
    plug = fn conn -> Plug.Conn.send_resp(conn, 500, "") end
    client = DectClient.new(host: "fritz.box", user: "u", password: "p", req: [plug: plug])
    test = self()

    log =
      capture_log(fn ->
        state = Bridge.poll_and_publish(state(client, &send(test, {:published, &1, &2})))
        assert state.last_apower_w == 0.0
      end)

    assert log =~ "FritzBridge robbebike: HTTP 500 during auth"
    refute_received {:published, _, _}
  end

  test "the process polls at once and again after the interval" do
    test = self()

    pid =
      start_supervised!(
        {Bridge,
         plug: @plug,
         client: client(1000),
         poll: @poll,
         topic_prefix: "shellies",
         publish: &send(test, {:published, &1, &2}),
         timer: fn pid, message, delay -> send(test, {:armed, pid, message, delay}) end}
      )

    assert_receive {:published, "shellies/robbebike/status/switch:0", _}, 5_000
    assert_receive {:armed, ^pid, :poll, delay}, 5_000
    assert delay == round(Bridge.interval(:sys.get_state(pid)) * 1000)

    send(pid, :poll)

    assert_receive {:published, "shellies/robbebike/status/switch:0", _}, 5_000
    assert_receive {:armed, ^pid, :poll, _delay}, 5_000
  end

  test "the default publisher sends on the bridge's own connection" do
    test = self()

    Ziwoas.TestMqtt.record(fn client_id, topic, payload ->
      send(test, {:mqtt, client_id, topic, payload})
      :ok
    end)

    pid =
      start_supervised!(
        {Bridge,
         plug: @plug,
         client: client(1000),
         poll: %{@poll | idle_interval_seconds: 3600},
         topic_prefix: "shellies"}
      )

    assert_receive {:mqtt, "ziwoas-phoenix-fritz", "shellies/robbebike/status/switch:0", _}

    assert %{last_apower_w: 1.0, client: %DectClient{sid: "abc123def456abcd"}} =
             :sys.get_state(pid)
  end

  test "a failed publish is logged and the bridge keeps polling" do
    Ziwoas.TestMqtt.record(fn _client_id, _topic, _payload -> {:error, :timeout} end)

    log =
      capture_log(fn ->
        pid =
          start_supervised!(
            {Bridge,
             plug: @plug,
             client: client(1000),
             poll: %{@poll | idle_interval_seconds: 3600},
             topic_prefix: "shellies"}
          )

        assert %{last_apower_w: 1.0} = :sys.get_state(pid)
      end)

    assert log =~ "FritzBridge: publish on shellies/robbebike/status/switch:0 failed: :timeout"
  end
end
