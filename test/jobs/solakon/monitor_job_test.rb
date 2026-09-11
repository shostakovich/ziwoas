require "test_helper"

class SolakonMonitorJobTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls

    def initialize(state: nil, fail: false)
      @state = state
      @fail = fail
      @calls = []
    end

    def read_state
      @calls << :read_state
      raise Solakon::Client::Error, "down" if @fail

      @state
    end
  end

  class RecordingLogger
    attr_reader :infos, :warnings

    def initialize
      @infos = []
      @warnings = []
    end

    def info(message = nil) = (@infos << message)
    def warn(message = nil) = (@warnings << message)
  end

  class FakeBroadcaster
    attr_reader :calls

    def initialize(fail: false)
      @fail = fail
      @calls = []
    end

    def broadcast_live(**)
      @calls << :live
      raise "broadcast down" if @fail
    end
  end

  Sol = Struct.new(:host, :port, :unit_id, :monitoring_enabled, :control_enabled, keyword_init: true)
  Cfg = Struct.new(:solakon, :plug_roster, keyword_init: true)

  setup do
    Solakon::Reading.delete_all
  end

  def config(monitoring_enabled: true, control_enabled: false, solakon: true)
    Cfg.new(
      plug_roster: Plugs::Roster.new([]),
      solakon: (
        Sol.new(
          host: "h",
          port: 502,
          unit_id: 1,
          monitoring_enabled: monitoring_enabled,
          control_enabled: control_enabled
        ) if solakon
      )
    )
  end

  def state
    Solakon::Client::State.new(
      battery_soc: 55,
      active_power_w: 123,
      pv_power_w: 456,
      battery_power_w: -78,
      battery_temperature_c: 42.3,
      battery_voltage_v: 51.2,
      battery_current_a: -1.5,
      inverter_temperature_c: 34.1,
      status1: 4,
      status3: 0,
      alarm1: 0,
      alarm2: 8,
      alarm3: 0,
      eps_enabled: true,
      eps_voltage_v: 230.1,
      eps_power_w: 125
    )
  end

  # A tick stub has to answer like the real one: with an outcome the monitor can log.
  def recording(calls)
    lambda do |reading:, roster:, client:, control:, now:|
      calls << reading
      Solakon::Control::Outcome.paused
    end
  end

  def answering(outcome) = ->(reading:, roster:, client:, control:, now:) { outcome }

  def run_job(client:, cfg: config, now: Time.zone.local(2026, 6, 18, 12, 0, 0),
              broadcaster: FakeBroadcaster.new, &block)
    ConfigLoader.stub(:app_config, cfg) do
      DashboardBroadcaster.stub(:broadcast_live, broadcaster.method(:broadcast_live)) do
        if block
          Solakon::Control::Tick.stub(:call, block) do
            Solakon::MonitorJob.new.perform(client: client, now: now)
          end
        else
          Solakon::MonitorJob.new.perform(client: client, now: now)
        end
      end
    end
  end

  test "persists reading when monitoring_enabled true" do
    now = Time.zone.local(2026, 6, 18, 12, 0, 0)
    client = FakeClient.new(state: state)
    broadcaster = FakeBroadcaster.new

    assert_difference -> { Solakon::Reading.count }, 1 do
      run_job(client: client, now: now, broadcaster: broadcaster)
    end

    reading = Solakon::Reading.last
    assert_equal [ :read_state ], client.calls
    assert_equal [ :live ], broadcaster.calls
    assert_equal now, reading.taken_at
    assert_equal 123, reading.active_power_w
    assert_equal 456, reading.pv_power_w
    assert_equal(-78, reading.battery_power_w)
    assert_equal 55, reading.battery_soc_pct
    assert_in_delta 42.3, reading.battery_temperature_c, 0.001
    assert_in_delta 51.2, reading.battery_voltage_v, 0.001
    assert_in_delta(-1.5, reading.battery_current_a, 0.001)
    assert_in_delta 34.1, reading.inverter_temperature_c, 0.001
    assert_equal 4, reading.status1
    assert_equal 0, reading.status3
    assert_equal 0, reading.alarm1
    assert_equal 8, reading.alarm2
    assert_equal 0, reading.alarm3
    assert_equal true, reading.eps_enabled
    assert_in_delta 230.1, reading.eps_voltage_v, 0.001
    assert_equal 125, reading.eps_power_w
  end

  test "does not read or persist when monitoring_enabled false" do
    client = FakeClient.new(state: state)

    assert_no_difference -> { Solakon::Reading.count } do
      run_job(client: client, cfg: config(monitoring_enabled: false))
    end

    assert_empty client.calls
  end

  test "read failure does not persist and does not control" do
    client = FakeClient.new(fail: true)
    control_calls = []

    assert_no_difference -> { Solakon::Reading.count } do
      assert_nothing_raised do
        run_job(client: client, cfg: config(control_enabled: true), &recording(control_calls))
      end
    end

    assert_equal [ :read_state ], client.calls
    assert_empty control_calls
  end

  test "successful read with control_enabled true hands the control tick the reading it just took" do
    now = Time.zone.local(2026, 6, 18, 12, 0, 0)
    client = FakeClient.new(state: state)
    broadcaster = FakeBroadcaster.new
    control_calls = []

    run_job(
      client: client,
      now: now,
      cfg: config(control_enabled: true),
      broadcaster: broadcaster,
      &recording(control_calls)
    )

    handed = control_calls.sole
    assert_equal now, handed.taken_at
    assert_equal 456, handed.pv_power_w
    assert_equal handed, Solakon::Reading.last # the reading was taken once, not twice
    assert_equal [ :live ], broadcaster.calls
  end

  # The configuration gates sit here, before anything is read or decided.
  test "control_enabled false leaves the control tick alone" do
    control_calls = []

    run_job(
      client: FakeClient.new(state: state),
      cfg: config(control_enabled: false),
      &recording(control_calls)
    )

    assert_empty control_calls
  end

  test "an unconfigured inverter is neither read nor controlled" do
    client = FakeClient.new(state: state)
    control_calls = []

    run_job(
      client: client,
      cfg: config(solakon: false),
      &recording(control_calls)
    )

    assert_empty client.calls
    assert_empty control_calls
  end

  test "the tick outcome is logged under the control prefix" do
    logger = RecordingLogger.new
    outcome = Solakon::Control::Outcome.paused

    Rails.stub(:logger, logger) do
      run_job(
        client: FakeClient.new(state: state),
        cfg: config(control_enabled: true),
        &answering(outcome)
      )
    end

    assert_equal [ "solakon_control: runtime paused" ], logger.infos
  end

  test "invalid reading does not persist or trigger control" do
    invalid_state = Solakon::Client::State.new(
      battery_soc: 150,
      active_power_w: 123,
      pv_power_w: 456,
      battery_power_w: -78,
      battery_temperature_c: 42.3
    )
    client = FakeClient.new(state: invalid_state)
    control_calls = []

    assert_no_difference -> { Solakon::Reading.count } do
      assert_nothing_raised do
        run_job(client: client, cfg: config(control_enabled: true), &recording(control_calls))
      end
    end

    assert_equal [ :read_state ], client.calls
    assert_empty control_calls
  end

  test "broadcast failure does not block the control tick" do
    client = FakeClient.new(state: state)
    broadcaster = FakeBroadcaster.new(fail: true)
    control_calls = []

    assert_nothing_raised do
      run_job(
        client: client,
        cfg: config(control_enabled: true),
        broadcaster: broadcaster,
        &recording(control_calls)
      )
    end

    assert_equal 1, control_calls.length
    assert_equal [ :live ], broadcaster.calls
  end
end
