require "test_helper"
require "shelly_status_handler"
require "config_loader"
require "logger"
require "stringio"

class ShellyStatusHandlerTest < ActiveSupport::TestCase
  cover "ShellyStatusHandler*"

  setup do
    Plugs::Sample.delete_all
    Plugs::State.delete_all
    @log_io = StringIO.new
    @logger = Logger.new(@log_io)
    @now    = 1_700_000_000.0
    @mqtt_config = ConfigLoader::MqttCfg.new(host: "localhost", port: 1883, topic_prefix: "shellies")
    @plugs = [
      ConfigLoader::PlugCfg.new(id: "bkw",   name: "Solar",  role: :producer, driver: :shelly, ain: nil),
      ConfigLoader::PlugCfg.new(id: "fridge", name: "Fridge", role: :consumer, driver: :shelly, ain: nil)
    ]
    @handler = ShellyStatusHandler.new(
      mqtt_config: @mqtt_config, plugs: @plugs, logger: @logger, clock: -> { @now }
    )
  end

  def status_payload(apower:, total:, output: nil)
    h = { "apower" => apower, "aenergy" => { "total" => total } }
    h["output"] = output unless output.nil?
    JSON.generate(h)
  end

  # The handler's job ends at handing batched deltas to DashboardBroadcaster;
  # what the broadcast renders is DashboardBroadcasterTest's concern.
  def capture_live_broadcasts
    calls = []
    DashboardBroadcaster.stub(:broadcast_live, ->(deltas: []) { calls << deltas.map(&:to_h) }) do
      yield calls
    end
  end

  test "subscriptions targets the shelly status topic" do
    assert_equal [ "shellies/+/status/switch:0" ], @handler.subscriptions
  end

  test "matches only shellies topics" do
    assert @handler.matches?("shellies/bkw/status/switch:0")
    refute @handler.matches?("govee/lamp/status")
  end

  test "handle_message inserts sample for known plug" do
    @handler.handle("shellies/bkw/status/switch:0",
                    status_payload(apower: 300.0, total: 1234.5))
    assert_equal 1, Plugs::Sample.count
    s = Plugs::Sample.first
    assert_equal "bkw", s.plug_id
    assert_equal @now.to_i, s.ts
    assert_in_delta 300.0, s.apower_w
    assert_in_delta 1234.5, s.aenergy_wh
  end

  test "handle_message warns and skips unknown plug" do
    @handler.handle("shellies/unknown/status/switch:0",
                    status_payload(apower: 1.0, total: 1.0))
    assert_equal 0, Plugs::Sample.count
    assert_match(/unknown plug.*unknown/i, @log_io.string)
  end

  test "handle_message ignores invalid JSON" do
    assert_nothing_raised do
      @handler.handle("shellies/bkw/status/switch:0", "not-json{")
    end
    assert_equal 0, Plugs::Sample.count
    assert_match(/invalid json/i, @log_io.string)
  end

  test "handle_message handles duplicate ts gracefully" do
    Plugs::Sample.create!(plug_id: "bkw", ts: @now.to_i, apower_w: 1.0, aenergy_wh: 1.0)
    assert_nothing_raised do
      @handler.handle("shellies/bkw/status/switch:0",
                      status_payload(apower: 300.0, total: 1234.5))
    end
    assert_equal 1, Plugs::Sample.where(plug_id: "bkw").count
  end

  test "handle_message broadcasts immediately on first message after startup" do
    capture_live_broadcasts do |calls|
      @handler.handle("shellies/bkw/status/switch:0",
                      status_payload(apower: 300.0, total: 1234.5))
      assert_equal 1, calls.length
      deltas = calls.first
      assert_equal 1, deltas.length
      assert_equal "bkw",    deltas.first[:id]
      assert_equal "Solar",  deltas.first[:name]
      assert_equal :producer, deltas.first[:role]
      assert_in_delta 300.0, deltas.first[:apower_w]
      assert_equal @now.to_i, deltas.first[:last_seen_ts]
      assert_equal (@now.to_i / 60) * 60, deltas.first[:bucket_ts]
    end
  end

  test "handle_message broadcasts producer avg_power_w as a positive magnitude" do
    capture_live_broadcasts do |calls|
      @handler.handle("shellies/bkw/status/switch:0",
                      status_payload(apower: -300.0, total: 1234.5))
      producer = calls.first.first
      assert_in_delta(-300.0, producer[:apower_w])
      assert_in_delta 300.0,  producer[:avg_power_w]
    end
  end

  test "handle_message leaves consumer avg_power_w signed" do
    capture_live_broadcasts do |calls|
      @handler.handle("shellies/fridge/status/switch:0",
                      status_payload(apower: -80.0, total: 1234.5))
      consumer = calls.first.first
      assert_in_delta(-80.0, consumer[:avg_power_w])
    end
  end

  test "handle_message batches messages within the 5-second window" do
    capture_live_broadcasts do |calls|
      @handler.handle("shellies/bkw/status/switch:0",
                      status_payload(apower: 300.0, total: 1234.5))
      @now += 1
      @handler.handle("shellies/bkw/status/switch:0",
                      status_payload(apower: 350.0, total: 1234.6))
      assert_equal 1, calls.length
    end
  end

  test "handle_message sends a new broadcast after the 5-second interval elapses" do
    capture_live_broadcasts do |calls|
      @handler.handle("shellies/bkw/status/switch:0",
                      status_payload(apower: 300.0, total: 1234.5))
      @now += 5
      @handler.handle("shellies/bkw/status/switch:0",
                      status_payload(apower: 350.0, total: 1234.6))
      assert_equal 2, calls.length
    end
  end

  test "handle_message merges multiple plugs into one broadcast" do
    capture_live_broadcasts do |calls|
      # First message triggers immediate broadcast (cold start)
      @handler.handle("shellies/bkw/status/switch:0",
                      status_payload(apower: 300.0, total: 1234.5))
      # Fridge message arrives within the window — buffered
      @now += 1
      @handler.handle("shellies/fridge/status/switch:0",
                      status_payload(apower: 50.0, total: 100.0))
      # Next bkw message arrives after interval — triggers broadcast with both plugs
      @now += 5
      @handler.handle("shellies/bkw/status/switch:0",
                      status_payload(apower: 310.0, total: 1234.6))

      assert_equal 2, calls.length
      plug_ids = calls.last.map { |p| p[:id] }
      assert_includes plug_ids, "fridge"
      assert_includes plug_ids, "bkw"
    end
  end

  test "handle_message records output state" do
    @handler.handle("shellies/fridge/status/switch:0",
                    status_payload(apower: 50.0, total: 1.0, output: true))
    assert_equal true, Plugs::State.find_by(plug_id: "fridge").output
  end

  test "handle_message updates output state on change" do
    @handler.handle("shellies/fridge/status/switch:0",
                    status_payload(apower: 50.0, total: 1.0, output: true))
    @now += 1
    @handler.handle("shellies/fridge/status/switch:0",
                    status_payload(apower: 0.0, total: 1.0, output: false))
    assert_equal false, Plugs::State.find_by(plug_id: "fridge").output
    assert_equal 1, Plugs::State.count
  end

  test "handle_message without output field leaves plug_states untouched" do
    @handler.handle("shellies/fridge/status/switch:0",
                    status_payload(apower: 50.0, total: 1.0))
    assert_equal 0, Plugs::State.count
  end

  test "handle_message includes output in the broadcast payload" do
    capture_live_broadcasts do |calls|
      @handler.handle("shellies/fridge/status/switch:0",
                      status_payload(apower: 50.0, total: 1.0, output: true))
      assert_equal true, calls.first.first[:output]
    end
  end

  test "handle_message tolerates non-boolean output without raising" do
    # An empty string casts to nil for the boolean `output` column, which
    # fails Plugs::State's inclusion validation and raises RecordInvalid.
    assert_nothing_raised do
      @handler.handle("shellies/fridge/status/switch:0",
                      status_payload(apower: 50.0, total: 1.0, output: ""))
    end
    assert_equal 0, Plugs::State.count
    assert_match(/invalid output/i, @log_io.string)
  end
end
