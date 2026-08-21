require "test_helper"
require "config_loader"
require "logger"
require "stringio"

class CollectorTest < ActiveSupport::TestCase
  cover "Collector*"

  class FakeRunnable
    attr_reader :thread_name

    def initialize = @gate = Queue.new

    def run
      @thread_name = Thread.current.name
      @gate.pop
    end

    def stop! = @gate.push(:stop)
  end

  class StubbornRunnable
    def run = sleep
    def stop! = nil
  end

  class DyingRunnable
    def run = raise(Errno::EHOSTUNREACH, "no route to host")
    def stop! = nil
  end

  class UnstoppableRunnable
    def run = sleep
    def stop! = raise(IOError, "socket already closed")
  end

  setup do
    @log_io = StringIO.new
    @logger = Logger.new(@log_io)
  end

  def build(runnables, join_timeout: 5)
    components = runnables.map.with_index { |r, i| Collector::Component.new(name: "fake_#{i}", runnable: r) }
    Collector.new(config: nil, logger: @logger, components: components, join_timeout: join_timeout)
  end

  def run_until_started(collector, count)
    thread = Thread.new { collector.run }
    sleep(0.01) until count.times.all? { |i| Thread.list.any? { |t| t.name == "fake_#{i}" } }
    thread
  end

  test "run starts one named thread per component and logs how many" do
    runnables = [ FakeRunnable.new, FakeRunnable.new ]
    collector = build(runnables)

    thread = run_until_started(collector, runnables.size)
    collector.stop!
    assert thread.join(5), "expected run to return after stop!"

    assert_equal [ "fake_0", "fake_1" ], runnables.map(&:thread_name)
    assert_match(/started 2 threads/, @log_io.string)
  end

  test "run blocks until stop! is called, then stops every component" do
    runnables = [ FakeRunnable.new, FakeRunnable.new ]
    collector = build(runnables)

    thread = run_until_started(collector, runnables.size)
    refute thread.join(0.1), "expected run to keep blocking without a stop request"
    refute_match(/stopping/, @log_io.string)

    collector.stop!

    assert thread.join(5), "expected run to return after stop!"
    assert_match(/stopping/, @log_io.string)
    assert_match(/stopped/, @log_io.string)
  end

  test "a component that ignores stop! is force-killed once the join times out" do
    collector = build([ FakeRunnable.new, StubbornRunnable.new ], join_timeout: 0.05)

    thread = run_until_started(collector, 2)
    collector.stop!
    assert thread.join(5), "expected run to return after the force-kill"

    assert_match(/force-killing fake_1/, @log_io.string)
    # Thread#kill only marks the thread; give it a moment to actually unwind.
    deadline = Time.now + 5
    sleep(0.01) while Thread.list.any? { |t| t.name == "fake_1" } && Time.now < deadline
    assert_nil Thread.list.find { |t| t.name == "fake_1" }
  end

  test "a component that stops on request is joined without a force-kill" do
    collector = build([ FakeRunnable.new ], join_timeout: 5)

    thread = run_until_started(collector, 1)
    collector.stop!
    assert thread.join(5), "expected run to return after stop!"

    refute_match(/force-killing/, @log_io.string)
  end

  test "a component that dies on its own is logged and does not abort the shutdown" do
    survivor  = FakeRunnable.new
    collector = build([ DyingRunnable.new, survivor ], join_timeout: 0.05)

    thread = Thread.new { collector.run }
    sleep(0.01) until survivor.thread_name
    collector.stop!
    assert thread.join(5), "expected run to return although a component died"

    assert_match(/fake_0 died: Errno::EHOSTUNREACH: .*no route to host/i, @log_io.string)
    assert_match(/stopped/, @log_io.string)
    refute_match(/force-killing/, @log_io.string)
  end

  test "a component that raises in stop! is logged and the rest still stops" do
    survivor  = FakeRunnable.new
    collector = build([ UnstoppableRunnable.new, survivor ], join_timeout: 0.05)

    thread = run_until_started(collector, 2)
    collector.stop!
    assert thread.join(5), "expected run to return although a component failed to stop"

    assert_match(/fake_0 failed to stop: IOError: socket already closed/, @log_io.string)
    assert_match(/force-killing fake_0/, @log_io.string)
    refute_match(/force-killing fake_1/, @log_io.string)
    assert_match(/stopped/, @log_io.string)
  end

  test "without injected components the collector assembles them from the config" do
    mqtt   = ConfigLoader::MqttCfg.new(host: "localhost", port: 1883, topic_prefix: "shellies")
    config = ConfigLoader::Config.new(timezone: "Europe/Berlin", mqtt: mqtt, plugs: [], govee: nil)

    collector = Collector.new(config: config, logger: @logger)

    assert_equal [ "mqtt_router" ], collector.instance_variable_get(:@components).map(&:name)
    assert_equal Collector::JOIN_TIMEOUT_SECONDS, collector.instance_variable_get(:@join_timeout)
    assert_equal 5, Collector::JOIN_TIMEOUT_SECONDS
  end

  test "the default assembly is built with the collector's own logger, not a nil one" do
    mqtt   = ConfigLoader::MqttCfg.new(host: "localhost", port: 1883, topic_prefix: "shellies")
    govee  = ConfigLoader::GoveeCfg.new(api_key: "", lan_poll_seconds: 8, api_poll_seconds: 180,
      pending_window_seconds: 5, names: {})
    config = ConfigLoader::Config.new(timezone: "Europe/Berlin", mqtt: mqtt, plugs: [], govee: govee)

    # A nil logger would raise NoMethodError before reaching the assertion.
    Collector.new(config: config, logger: @logger)

    assert_match(/Govees bridge disabled/, @log_io.string)
  end
end
