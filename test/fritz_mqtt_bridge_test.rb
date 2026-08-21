require "test_helper"
require "fritz_mqtt_bridge"
require "fritz_dect_client"
require "config_loader"
require "logger"
require "stringio"

class FritzMqttBridgeTest < ActiveSupport::TestCase
  cover "FritzMqttBridge*"

  setup do
    @log_io = StringIO.new
    @logger = Logger.new(@log_io)

    @plug = ConfigLoader::PlugCfg.new(
      id: "robbebike", name: "Waschmaschine",
      role: :consumer, driver: :fritz_dect, ain: "08761 0500475"
    )
    # port deliberately differs from MQTT::Client's own default (1883), so a
    # wiring test can't pass by accident when the kwarg is dropped.
    @mqtt_config = ConfigLoader::MqttCfg.new(
      host: "localhost", port: 18_830, topic_prefix: "shellies"
    )
    @fritz_poll_cfg = ConfigLoader::FritzPollCfg.new(
      active_interval_seconds: 5,
      idle_interval_seconds:   60,
      idle_threshold_w:        10,
      timeout_seconds:         2,
    )
  end

  def fake_fritz_client(apower_w:, aenergy_wh:)
    client = Object.new
    client.define_singleton_method(:fetch) do |_plug|
      FritzDectClient::Reading.new(apower_w: apower_w, aenergy_wh: aenergy_wh)
    end
    client
  end

  def fake_mqtt_client
    published = []
    client = Object.new
    client.define_singleton_method(:connect) { }
    client.define_singleton_method(:disconnect) { }
    client.define_singleton_method(:publish) { |topic, payload| published << [ topic, payload ] }
    client.define_singleton_method(:published) { published }
    client
  end

  # Poll intervals below the one-second granularity of sleep_interruptible, so
  # tests that let the bridge really sleep between polls don't wait for a tick.
  def instant_poll_cfg
    ConfigLoader::FritzPollCfg.new(active_interval_seconds: 0.01, idle_interval_seconds: 0.01,
      idle_threshold_w: 10, timeout_seconds: 2)
  end

  def build_bridge(fritz_client:, mqtt_client: nil, mqtt_factory: nil, backoff_seconds: 1,
                   fritz_poll_cfg: @fritz_poll_cfg)
    mqtt_client ||= fake_mqtt_client
    FritzMqttBridge.new(
      fritz_client:    fritz_client,
      plug:            @plug,
      mqtt_config:     @mqtt_config,
      fritz_poll_cfg:  fritz_poll_cfg,
      logger:          @logger,
      mqtt_factory:    mqtt_factory || -> { mqtt_client },
      backoff_seconds: backoff_seconds,
    )
  end

  # Connects, but drops the first publish — a broker that goes away mid-poll.
  def mqtt_client_failing_once
    published = []
    dropped   = false
    client    = Object.new
    client.define_singleton_method(:connect) { }
    client.define_singleton_method(:disconnect) { }
    client.define_singleton_method(:published) { published }
    client.define_singleton_method(:publish) do |topic, payload|
      next published << [ topic, payload ] if dropped
      dropped = true
      raise Errno::ECONNRESET, "connection reset by peer"
    end
    client
  end

  # Runs the bridge on its own thread until the block's condition holds, then
  # stops it and returns.
  def run_until(bridge)
    thread = Thread.new { bridge.run }
    sleep(0.01) until yield
    bridge.stop!
    assert thread.join(5), "expected run to return after stop!"
  end

  test "poll_and_publish sends correct topic" do
    fritz = fake_fritz_client(apower_w: 42.5, aenergy_wh: 100.0)
    mqtt  = fake_mqtt_client
    bridge = build_bridge(fritz_client: fritz, mqtt_client: mqtt)

    bridge.poll_and_publish(mqtt)

    assert_equal 1, mqtt.published.length
    assert_equal "shellies/robbebike/status/switch:0", mqtt.published.first[0]
  end

  test "poll_and_publish sends correct JSON payload" do
    fritz = fake_fritz_client(apower_w: 42.5, aenergy_wh: 100.0)
    mqtt  = fake_mqtt_client
    bridge = build_bridge(fritz_client: fritz, mqtt_client: mqtt)

    bridge.poll_and_publish(mqtt)

    data = JSON.parse(mqtt.published.first[1])
    assert_in_delta 42.5,  data["apower"]
    assert_in_delta 100.0, data.dig("aenergy", "total")
  end

  test "interval is active when power above threshold" do
    fritz = fake_fritz_client(apower_w: 50.0, aenergy_wh: 1.0)
    mqtt  = fake_mqtt_client
    bridge = build_bridge(fritz_client: fritz, mqtt_client: mqtt)

    bridge.poll_and_publish(mqtt)

    assert_equal 5, bridge.interval
  end

  test "interval is idle when power at or below threshold" do
    fritz = fake_fritz_client(apower_w: 2.0, aenergy_wh: 1.0)
    mqtt  = fake_mqtt_client
    bridge = build_bridge(fritz_client: fritz, mqtt_client: mqtt)

    bridge.poll_and_publish(mqtt)

    assert_equal 60, bridge.interval
  end

  test "interval starts as idle before first poll" do
    fritz = fake_fritz_client(apower_w: 0.0, aenergy_wh: 0.0)
    bridge = build_bridge(fritz_client: fritz)

    assert_equal 60, bridge.interval
  end

  test "before any poll, the last known power reads exactly zero" do
    bridge = build_bridge(fritz_client: fake_fritz_client(apower_w: 0.0, aenergy_wh: 0.0))

    assert_equal 0.0, bridge.instance_variable_get(:@last_apower_w)
  end

  test "poll_and_publish logs warning on fritz error and does not publish" do
    erroring = Object.new
    erroring.define_singleton_method(:fetch) { |_| raise FritzDectClient::Error, "timeout" }
    mqtt   = fake_mqtt_client
    bridge = build_bridge(fritz_client: erroring, mqtt_client: mqtt)

    bridge.poll_and_publish(mqtt)

    assert_equal 0, mqtt.published.length
    assert_match(/FritzMqttBridge robbebike: timeout/, @log_io.string)
  end

  test "poll_and_publish fetches the reading for this bridge's own plug" do
    received = nil
    fritz = Object.new
    fritz.define_singleton_method(:fetch) do |plug|
      received = plug
      FritzDectClient::Reading.new(apower_w: 1.0, aenergy_wh: 1.0)
    end
    mqtt   = fake_mqtt_client
    bridge = build_bridge(fritz_client: fritz, mqtt_client: mqtt)

    bridge.poll_and_publish(mqtt)

    assert_same @plug, received
  end

  test "run retries after an unreachable broker instead of dying" do
    fritz    = fake_fritz_client(apower_w: 42.5, aenergy_wh: 100.0)
    mqtt     = fake_mqtt_client
    attempts = 0
    factory  = -> {
      attempts += 1
      raise Errno::EHOSTUNREACH, "no route to host" if attempts == 1
      mqtt
    }
    bridge = build_bridge(fritz_client: fritz, mqtt_factory: factory, backoff_seconds: 0.01,
      fritz_poll_cfg: instant_poll_cfg)

    run_until(bridge) { mqtt.published.any? }

    assert_operator attempts, :>=, 2, "expected a second connect attempt"
    assert_match(/FritzMqttBridge robbebike: Errno::EHOSTUNREACH: .*no route to host/i, @log_io.string)
    assert_equal "shellies/robbebike/status/switch:0", mqtt.published.first.first
  end

  test "the retry delay grows with every failed connect" do
    fritz  = fake_fritz_client(apower_w: 42.5, aenergy_wh: 100.0)
    delays = []
    bridge = build_bridge(fritz_client: fritz, mqtt_factory: -> { raise MQTT::ProtocolException, "boom" },
      backoff_seconds: 0.01)
    bridge.define_singleton_method(:sleep_interruptible) { |seconds| delays << seconds }

    run_until(bridge) { delays.size >= 3 }

    assert_equal [ 0.01, 0.02, 0.04 ], delays.first(3)
  end

  test "a successful connect resets the retry delay" do
    fritz    = fake_fritz_client(apower_w: 42.5, aenergy_wh: 100.0)
    mqtt     = mqtt_client_failing_once
    attempts = 0
    delays   = []
    factory  = -> {
      attempts += 1
      raise Errno::EHOSTUNREACH, "no route to host" if attempts < 3
      mqtt
    }
    bridge = build_bridge(fritz_client: fritz, mqtt_factory: factory, backoff_seconds: 0.01)
    bridge.define_singleton_method(:sleep_interruptible) { |seconds| delays << seconds }

    run_until(bridge) { delays.size >= 3 }

    assert_equal [ 0.01, 0.02, 0.01 ], delays.first(3),
      "expected the delay to start over after the third attempt connected"
  end

  test "without an injected factory or backoff, the bridge builds its own mqtt client and starts at 1 second" do
    bridge = FritzMqttBridge.new(
      fritz_client:   fake_fritz_client(apower_w: 0.0, aenergy_wh: 0.0),
      plug:           @plug,
      mqtt_config:    @mqtt_config,
      fritz_poll_cfg: @fritz_poll_cfg,
      logger:         @logger,
    )

    assert_equal 1, bridge.instance_variable_get(:@backoff_start)

    default_client = bridge.instance_variable_get(:@mqtt_factory).call

    assert_instance_of MQTT::Client, default_client
    assert_equal "localhost", default_client.host
    assert_equal 18_830, default_client.port
  end

  test "the retry delay is capped at MAX_BACKOFF_SECONDS" do
    fritz  = fake_fritz_client(apower_w: 42.5, aenergy_wh: 100.0)
    delays = []
    bridge = build_bridge(fritz_client: fritz, mqtt_factory: -> { raise MQTT::ProtocolException, "boom" },
      backoff_seconds: 40)
    bridge.define_singleton_method(:sleep_interruptible) { |seconds| delays << seconds }

    run_until(bridge) { delays.size >= 2 }

    assert_equal [ 40, FritzMqttBridge::MAX_BACKOFF_SECONDS ], delays.first(2)
  end

  test "no backoff sleep is scheduled when stop! arrives while a connect is failing" do
    fritz  = fake_fritz_client(apower_w: 42.5, aenergy_wh: 100.0)
    delays = []
    bridge = nil
    factory = -> {
      bridge.stop!
      raise MQTT::ProtocolException, "boom"
    }
    bridge = build_bridge(fritz_client: fritz, mqtt_factory: factory, backoff_seconds: 0.01)
    bridge.define_singleton_method(:sleep_interruptible) { |seconds| delays << seconds }

    bridge.run

    assert_empty delays, "expected no backoff sleep once stop! had already arrived"
  end

  test "connect_and_poll connects once, disconnects on stop and sleeps between polls" do
    fritz = fake_fritz_client(apower_w: 2.0, aenergy_wh: 1.0)
    connect_count    = 0
    disconnect_count = 0
    mqtt = Object.new
    mqtt.define_singleton_method(:connect)    { connect_count += 1 }
    mqtt.define_singleton_method(:disconnect) { disconnect_count += 1 }
    mqtt.define_singleton_method(:publish)    { |_topic, _payload| }
    delays = []
    bridge = build_bridge(fritz_client: fritz, mqtt_client: mqtt)
    bridge.define_singleton_method(:sleep_interruptible) { |seconds| delays << seconds }

    run_until(bridge) { delays.size >= 2 }

    assert_equal 1, connect_count, "expected exactly one connect for an unbroken session"
    assert_equal 1, disconnect_count, "expected disconnect once the session stopped"
    assert_equal [ 60, 60 ], delays.first(2), "expected the idle interval between polls"
  end

  test "a disconnect failure during teardown is swallowed, not logged as a run error" do
    fritz = fake_fritz_client(apower_w: 2.0, aenergy_wh: 1.0)
    published = []
    mqtt = Object.new
    mqtt.define_singleton_method(:connect)    { }
    mqtt.define_singleton_method(:disconnect) { raise IOError, "disk full" }
    mqtt.define_singleton_method(:publish)    { |topic, payload| published << [ topic, payload ] }
    bridge = build_bridge(fritz_client: fritz, mqtt_client: mqtt, fritz_poll_cfg: instant_poll_cfg)

    run_until(bridge) { published.any? }

    refute_match(/IOError/, @log_io.string)
  end

  test "sleep_interruptible caps each wait at one second but never oversleeps a shorter remainder" do
    capped_bridge = build_bridge(fritz_client: fake_fritz_client(apower_w: 0.0, aenergy_wh: 0.0))
    short_bridge  = build_bridge(fritz_client: fake_fritz_client(apower_w: 0.0, aenergy_wh: 0.0))

    assert_in_delta 1,   capped_sleep_argument(capped_bridge, 1.2), 0.05
    assert_in_delta 0.3, capped_sleep_argument(short_bridge, 0.3),  0.05
  end

  private

  # Stubs Kernel#sleep on the bridge itself so the real call never blocks, records
  # the argument it was given, then flips @stopping to end the wait after one chunk.
  def capped_sleep_argument(bridge, seconds)
    captured = nil
    bridge.define_singleton_method(:sleep) do |s|
      captured = s
      bridge.stop!
    end
    bridge.send(:sleep_interruptible, seconds)
    captured
  end
end
