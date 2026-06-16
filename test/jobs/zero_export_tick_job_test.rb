require "test_helper"

class ZeroExportTickJobTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :writes
    def initialize(state: nil)
      @state  = state
      @writes = []
    end

    def ensure_remote_control!     = (@writes << :remote)
    def ensure_minimum_soc!(pct)   = (@writes << [ :min_soc, pct ])
    def write_output_power!(watts) = (@writes << [ :power, watts ])
    def read_state                 = @state
  end

  Plug = Struct.new(:id, :role, :name, keyword_init: true)
  Sol  = Struct.new(:host, :port, :unit_id, :enabled, :stale_after_s, keyword_init: true)
  Cfg  = Struct.new(:plugs, :solakon, keyword_init: true)

  def config(enabled: true, solakon: true)
    sol = solakon ? Sol.new(host: "h", port: 502, unit_id: 1, enabled: enabled, stale_after_s: 120) : nil
    Cfg.new(plugs: [ Plug.new(id: "fridge", role: :consumer, name: "Kühlschrank") ], solakon: sol)
  end

  setup do
    Sample.delete_all
    Rails.cache.clear
  end

  test "writes target derived from measured consumption" do
    now = Time.at(1_000_000)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 250, aenergy_wh: 1)
    client = FakeClient.new(state: SolakonClient::State.new(
      battery_soc: 55, active_power_w: 250, pv_power_w: 0, battery_power_w: 0))

    ConfigLoader.stub(:app_config, config) do
      ZeroExportTickJob.new.perform(client: client, reader_now: now)
    end

    assert_includes client.writes, :remote
    assert_includes client.writes, [ :min_soc, 10 ]
    assert_includes client.writes, [ :power, 250 ]
  end

  test "no-op when disabled" do
    client = FakeClient.new
    ConfigLoader.stub(:app_config, config(enabled: false)) do
      ZeroExportTickJob.new.perform(client: client, reader_now: Time.now)
    end
    assert_empty client.writes
  end

  test "no-op when solakon not configured" do
    client = FakeClient.new
    ConfigLoader.stub(:app_config, config(solakon: false)) do
      ZeroExportTickJob.new.perform(client: client, reader_now: Time.now)
    end
    assert_empty client.writes
  end

  test "swallows Modbus errors" do
    now = Time.at(1_000_000)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 250, aenergy_wh: 1)
    client = FakeClient.new
    def client.ensure_remote_control! = raise(SolakonClient::Error, "down")

    ConfigLoader.stub(:app_config, config) do
      assert_nothing_raised do
        ZeroExportTickJob.new.perform(client: client, reader_now: now)
      end
    end
  end
end
