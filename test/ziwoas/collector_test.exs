defmodule Ziwoas.CollectorTest do
  # Collector::Assembly: which connections run for which owners.
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ziwoas.{Collector, Config, Ownership}

  @config Config.from_yaml!("""
          location:
            timezone: Europe/Berlin
          mqtt:
            host: broker
            port: 1883
            topic_prefix: shellies
          fritz_box:
            host: fritz.box
            user: u
            password: p
          fritz_poll:
            active_interval_seconds: 5
            idle_interval_seconds: 60
            idle_threshold_w: 10
            timeout_seconds: 2
          plugs:
            - id: bkw
              name: BKW
              role: producer
            - id: washer
              name: Waschmaschine
              role: consumer
              driver: fritz_dect
              ain: "08761 0500475"
          solakon:
            host: 192.168.8.166
            control_enabled: true
          govee:
            api_key: k
          """)

  defp owners(modes), do: Map.merge(Ownership.all_rails(), modes)

  test "Phoenix runs nothing while Rails owns every task" do
    assert Collector.children(@config, Ownership.all_rails()) == []
  end

  test "one MQTT connection carries both handlers, subscribed to their union" do
    [ingest] =
      Collector.children(@config, owners(%{plug_ingest: :shadow, light_ingest: :phoenix}))

    assert ingest.id == {Ziwoas.Mqtt, "ziwoas-phoenix-ingest"}
    {Tortoise311.Connection, :start_link, [opts]} = ingest.start

    assert opts[:subscriptions] == [
             {"shellies/+/status/switch:0", 0},
             {"govees/+/config", 0},
             {"govees/+/state", 0}
           ]

    assert {Ziwoas.Collector.MqttRouter,
            [{Ziwoas.Plugs.ShellyStatusHandler, _}, {Ziwoas.Lights.GoveeSubscriber, _}]} =
             opts[:handler]
  end

  test "the Solakon monitor keeps its connection open only as owner" do
    [shadow] = Collector.children(@config, owners(%{solakon_monitor: :shadow}))

    assert {Ziwoas.Solakon.Monitor,
            [host: "192.168.8.166", port: 502, unit_id: 1, keep_open: false]} = shadow

    [owner] =
      Collector.children(@config, owners(%{solakon_monitor: :phoenix, solakon_control: :phoenix}))

    assert {Ziwoas.Solakon.Monitor, opts} = owner
    assert opts[:keep_open]
  end

  test "a control dry run with the monitoring switched off says that no tick runs" do
    config = %{
      @config
      | solakon: %{@config.solakon | monitoring_enabled: false, control_enabled: true}
    }

    log =
      capture_log(fn ->
        assert Collector.children(
                 config,
                 owners(%{solakon_control: :dry_run, solakon_monitor: :shadow})
               ) == []
      end)

    assert log =~ "solakon_control: runs in Phoenix, but solakon.monitoring_enabled is off"
  end

  test "a shadow Fritz bridge polls without a publisher connection" do
    assert [{Ziwoas.Fritz.Bridge, opts}] =
             Collector.children(@config, owners(%{fritz_bridge: :shadow}))

    assert opts[:plug].id == "washer"
    refute opts[:owner]

    assert [%{id: {Ziwoas.Mqtt, "ziwoas-phoenix-fritz"}}, {Ziwoas.Fritz.Bridge, owner_opts}] =
             Collector.children(@config, owners(%{fritz_bridge: :phoenix}))

    assert owner_opts[:owner]
  end

  test "a shadow Govee bridge gets no command connection" do
    assert [{Ziwoas.Govee.Bridge, [govee: _, owner: false]}] =
             Collector.children(@config, owners(%{govee_bridge: :shadow}))

    assert [
             {Ziwoas.Govee.Bridge, [govee: _, owner: true]},
             %{id: {Ziwoas.Mqtt, "ziwoas-phoenix-govee"}}
           ] =
             Collector.children(@config, owners(%{govee_bridge: :phoenix}))
  end

  test "the command connection runs only while Phoenix owns switching or lights" do
    assert Collector.children(@config, owners(%{switching: :dry_run, lights: :dry_run})) == []

    for modes <- [
          %{switching: :phoenix},
          %{lights: :phoenix},
          %{switching: :phoenix, lights: :phoenix}
        ] do
      assert [%{id: {Ziwoas.Mqtt, "ziwoas-phoenix-command"}}] =
               Collector.children(@config, owners(modes))
    end
  end

  test "devices that are not configured start nothing" do
    bare = %{
      @config
      | solakon: nil,
        govee: nil,
        plugs: Enum.reject(@config.plugs, &(&1.driver == :fritz_dect))
    }

    modes = %{solakon_monitor: :shadow, fritz_bridge: :shadow, govee_bridge: :shadow}
    assert Collector.children(bare, owners(modes)) == []

    log =
      capture_log(fn ->
        assert Collector.children(
                 %{@config | govee: %{@config.govee | api_key: ""}},
                 owners(%{govee_bridge: :shadow})
               ) == []
      end)

    assert log =~ "missing govee.api_key"
  end
end
