require "test_helper"

class ControlTickTest < ActiveSupport::TestCase
  cover "Solakon::Control::Tick*"

  class FakeClient
    attr_reader :calls

    def initialize(fail: false, release_fail: false)
      @fail = fail
      @release_fail = release_fail
      @calls = []
    end

    def apply_control!(power_w:, min_soc:)
      raise Solakon::Client::Error, "down" if @fail

      @calls << [ :apply_power, power_w, min_soc ]
    end

    def release_control!
      raise Solakon::Client::Error, "release down" if @release_fail

      @calls << :release
    end
  end

  Plug = Struct.new(:id, :role, :name, keyword_init: true)

  NOW = Time.at(1_000_000).freeze

  setup do
    Plugs::Sample.delete_all
    Solakon::Control::State.delete_all
    @cache = ActiveSupport::Cache::MemoryStore.new
    @control = Solakon::Control::State.current
  end

  teardown { Solakon::Control::State.delete_all }

  def roster
    Plugs::Roster.new([ Plug.new(id: "fridge", role: :consumer, name: "Kühlschrank") ])
  end

  def reading(soc: 55, pv: 0, temp: 30, battery: 0, at: NOW)
    Solakon::Reading.new(taken_at: at, active_power_w: 0, pv_power_w: pv,
                         battery_power_w: battery, battery_soc_pct: soc, battery_temperature_c: temp)
  end

  def measuring(watt, at: NOW)
    Plugs::Sample.create!(plug_id: "fridge", ts: at.to_i - 5, apower_w: watt, aenergy_wh: 1)
  end

  def tick(client:, now: NOW, reading: reading(), control: @control)
    Solakon::Control::Tick.call(reading: reading, roster: roster, client: client,
                                control: control, now: now, cache: @cache)
  end

  test "applies a target derived from measured consumption, with the min_soc guard" do
    measuring(250)
    client = FakeClient.new

    outcome = tick(client: client)

    assert_equal [ [ :apply_power, 250, 10 ] ], client.calls
    assert_equal :applied, outcome.status
    assert_equal :normal, outcome.decision.state
  end

  test "stores the applied decision with the time it was written" do
    measuring(250)

    tick(client: FakeClient.new)

    stored = @control.reload.stored
    assert_equal :normal, stored.decision_state
    assert_equal 250, stored.target_w
    refute stored.trim
    assert_equal NOW, stored.at
  end

  test "the stored decision carries into the next tick" do
    measuring(800)
    @control.store!(Solakon::Control::Decision.new(state: :normal, target_w: 240, trim: false),
                    at: NOW - 30.seconds)
    client = FakeClient.new

    tick(client: client)

    assert_equal [ [ :apply_power, 440, 10 ] ], client.calls # 240 + the 200 W rise limit
  end

  # Past the inverter's remote-control watchdog the device has dropped back to
  # its own behaviour, so there is nothing left to continue from.
  test "a decision older than the inverter watchdog is not continued" do
    measuring(700)
    @control.store!(Solakon::Control::Decision.new(state: :normal, target_w: 100, trim: false),
                    at: NOW - Solakon::Client::REMOTE_TIMEOUT_S.seconds)
    client = FakeClient.new

    tick(client: client)

    assert_equal [ [ :apply_power, 700, 10 ] ], client.calls
  end

  test "falls back to the guaranteed floor when no measurement is fresh" do
    Plugs::Sample.create!(plug_id: "fridge", ts: NOW.to_i - 600, apower_w: 146, aenergy_wh: 1)
    client = FakeClient.new

    outcome = tick(client: client)

    assert_equal [ [ :apply_power, 146, 10 ] ], client.calls
    assert_nil outcome.load.current_w
  end

  # Every write re-arms the inverter's 150s watchdog, so an unchanged target is
  # still written.
  test "writes every tick even when the target is unchanged" do
    measuring(386)
    tick(client: FakeClient.new)

    second = FakeClient.new
    tick(client: second, now: NOW + 30.seconds, reading: reading(at: NOW + 30.seconds))

    assert_equal [ [ :apply_power, 386, 10 ] ], second.calls
  end

  test "a paused loop writes nothing" do
    measuring(250)
    @control.pause!
    client = FakeClient.new

    outcome = tick(client: client)

    assert_empty client.calls
    assert_equal :paused, outcome.status
  end

  test "a single write failure neither relinquishes control nor stores the decision" do
    measuring(250)
    client = FakeClient.new(fail: true)

    outcome = tick(client: client)

    refute_includes client.calls, :release
    assert_equal :failed, outcome.status
    assert_equal 1, outcome.failures
    assert_nil @control.reload.stored
  end

  test "relinquishes remote control after three consecutive write failures" do
    measuring(250)
    @control.store!(Solakon::Control::Decision.new(state: :surplus, target_w: 500, trim: false),
                    at: NOW - 30.seconds)
    client = FakeClient.new(fail: true)

    outcomes = 3.times.map { tick(client: client) }

    assert_equal [ :failed, :failed, :released ], outcomes.map(&:status)
    assert_equal 1, client.calls.count(:release)
    assert_nil @control.reload.stored
  end

  test "a successful tick resets the failure count" do
    measuring(250)
    failing = FakeClient.new(fail: true)
    2.times { tick(client: failing) }

    tick(client: FakeClient.new)

    assert_equal 0, @control.reload.failures
    second_run = FakeClient.new(fail: true)
    2.times { tick(client: second_run) }
    refute_includes second_run.calls, :release
  end

  test "a failed release keeps remote control and says so" do
    measuring(250)
    @control.store!(Solakon::Control::Decision.new(state: :surplus, target_w: 500, trim: false),
                    at: NOW - 30.seconds)
    client = FakeClient.new(fail: true, release_fail: true)

    outcomes = 3.times.map { tick(client: client) }

    assert_equal :failed, outcomes.last.status
    assert_equal "down; could not relinquish remote control: release down", outcomes.last.error
    assert_not_nil @control.reload.stored
  end
end
