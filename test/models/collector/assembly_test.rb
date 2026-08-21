require "test_helper"
require "config_loader"
require "logger"
require "stringio"

class CollectorAssemblyTest < ActiveSupport::TestCase
  cover "Collector::Assembly*"

  MQTT = ConfigLoader::MqttCfg.new(host: "localhost", port: 1883, topic_prefix: "shellies")

  # timeout_seconds deliberately differs from FritzDectClient's own default (2),
  # so a wiring test can't pass by accident when the kwarg is dropped.
  FRITZ_POLL = ConfigLoader::FritzPollCfg.new(active_interval_seconds: 5, idle_interval_seconds: 60,
    idle_threshold_w: 2.0, timeout_seconds: 9)

  FRITZ_BOX = ConfigLoader::FritzBoxCfg.new(host: "fritz.box", user: "fritz-user", password: "fritz-pw")

  setup do
    @log_io = StringIO.new
    @logger = Logger.new(@log_io)
  end

  def plug(id, driver: :shelly)
    ConfigLoader::PlugCfg.new(id: id, name: id.capitalize, role: :consumer, driver: driver,
      ain: driver == :fritz_dect ? "1234" : nil, room: nil, switchable: false)
  end

  def govee_cfg(api_key:)
    ConfigLoader::GoveeCfg.new(api_key: api_key, lan_poll_seconds: 8, api_poll_seconds: 180,
      pending_window_seconds: 5, names: {})
  end

  def components(plugs: [ plug("fridge") ], govee: nil, fritz_box: FRITZ_BOX)
    config = ConfigLoader::Config.new(timezone: "Europe/Berlin", mqtt: MQTT, plugs: plugs,
      fritz_poll: FRITZ_POLL, fritz_box: fritz_box, govee: govee)
    Collector::Assembly.new(config: config, logger: @logger).components
  end

  def wiring(object, *names) = names.to_h { |name| [ name, object.instance_variable_get(name) ] }

  test "the first component is an mqtt router wired to the mqtt config and the logger" do
    router = components.first

    assert_equal "mqtt_router", router.name
    assert_instance_of MqttRouter, router.runnable
    assert_equal({ :@mqtt_config => MQTT, :@logger => @logger },
      wiring(router.runnable, :@mqtt_config, :@logger))
  end

  test "the router carries a shelly handler for the configured plugs and the govee subscriber" do
    shelly, subscriber = components(plugs: [ plug("fridge"), plug("bkw") ])
      .first.runnable.instance_variable_get(:@handlers)

    assert_instance_of ShellyStatusHandler, shelly
    assert_equal MQTT, shelly.instance_variable_get(:@mqtt_config)
    assert_equal @logger, shelly.instance_variable_get(:@logger)
    assert_equal [ "fridge", "bkw" ], shelly.instance_variable_get(:@plug_map).keys

    assert_instance_of Govees::Subscriber, subscriber
    assert_equal @logger, subscriber.instance_variable_get(:@logger)
  end

  test "every fritz_dect plug gets its own bridge, shelly plugs get none" do
    plugs = [ plug("fridge"), plug("dryer", driver: :fritz_dect), plug("desk", driver: :fritz_dect) ]

    bridges = components(plugs: plugs).select { |c| c.runnable.is_a?(FritzMqttBridge) }

    assert_equal [ "fritz_bridge_dryer", "fritz_bridge_desk" ], bridges.map(&:name)
    assert_equal [ "dryer", "desk" ],
      bridges.map { |b| b.runnable.instance_variable_get(:@plug).id }
  end

  test "a fritz bridge is wired to the mqtt config, the poll config and the logger" do
    bridge = components(plugs: [ plug("dryer", driver: :fritz_dect) ]).last.runnable

    assert_equal({ :@mqtt_config => MQTT, :@fritz_poll_cfg => FRITZ_POLL, :@logger => @logger },
      wiring(bridge, :@mqtt_config, :@fritz_poll_cfg, :@logger))
  end

  test "all fritz bridges share one client built from the fritz_box credentials" do
    plugs = [ plug("dryer", driver: :fritz_dect), plug("desk", driver: :fritz_dect) ]

    clients = components(plugs: plugs)
      .select { |c| c.runnable.is_a?(FritzMqttBridge) }
      .map { |c| c.runnable.instance_variable_get(:@fritz_client) }

    assert_equal 1, clients.map(&:object_id).uniq.size
    assert_instance_of FritzDectClient, clients.first
    assert_equal({ :@host => "fritz.box", :@user => "fritz-user", :@password => "fritz-pw", :@timeout => 9 },
      wiring(clients.first, :@host, :@user, :@password, :@timeout))
  end

  test "without a fritz_dect plug no client is built, so no fritz_box is needed" do
    assert_equal [ "mqtt_router" ], components(fritz_box: nil).map(&:name)
  end

  test "a govee api_key adds a bridge wired to the govee config and a platform api" do
    bridge = components(govee: govee_cfg(api_key: "secret")).find { |c| c.name == "govees_bridge" }

    assert_instance_of Govees::Bridge, bridge.runnable
    assert_equal({ :@mqtt_config => MQTT, :@logger => @logger },
      wiring(bridge.runnable, :@mqtt_config, :@logger))
    assert_equal "secret", bridge.runnable.instance_variable_get(:@cfg).api_key

    api = bridge.runnable.instance_variable_get(:@registry).instance_variable_get(:@api)
    assert_instance_of Govees::PlatformApi, api
    assert_equal "secret", api.instance_variable_get(:@api_key)
    refute_match(/Govees bridge disabled/, @log_io.string)
  end

  test "a govee section without an api_key is skipped with a warning" do
    names = components(govee: govee_cfg(api_key: "")).map(&:name)

    assert_equal [ "mqtt_router" ], names
    assert_match(/Govees bridge disabled: missing govee.api_key in ziwoas.yml/, @log_io.string)
  end

  test "no govee section means no bridge and no warning" do
    assert_equal [ "mqtt_router" ], components.map(&:name)
    assert_equal "", @log_io.string
  end
end
