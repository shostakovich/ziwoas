require "test_helper"

class TrmnlPayloadBuilderTest < ActiveSupport::TestCase
  setup do
    Sample.delete_all
    plug_bkw    = ConfigLoader::PlugCfg.new(id: "bkw",    name: "BKW",   role: :producer, driver: :shelly, ain: nil)
    plug_fridge = ConfigLoader::PlugCfg.new(id: "fridge", name: "Fridge", role: :consumer, driver: :shelly, ain: nil)
    mqtt = ConfigLoader::MqttCfg.new(host: "localhost", port: 1883, topic_prefix: "shellies")
    @config = ConfigLoader::Config.new(
      electricity_price_eur_per_kwh: 0.32,
      timezone: "Europe/Berlin",
      mqtt: mqtt,
      fritz_poll: nil,
      plugs: [ plug_bkw, plug_fridge ],
      fritz_box: nil,
      weather: nil,
      trmnl_webhook_url: nil,
    )
    @tz = TZInfo::Timezone.get("Europe/Berlin")
    @midnight_local = @tz.local_to_utc(Time.parse("#{Date.today} 00:00:00")).to_i
  end

  test "build returns merge_variables hash with today aggregate fields" do
    Sample.create!(plug_id: "bkw",    ts: @midnight_local + 60,   apower_w: 0, aenergy_wh: 0.0)
    Sample.create!(plug_id: "bkw",    ts: @midnight_local + 3600, apower_w: 0, aenergy_wh: 1000.0)
    Sample.create!(plug_id: "fridge", ts: @midnight_local + 60,   apower_w: 0, aenergy_wh: 500.0)
    Sample.create!(plug_id: "fridge", ts: @midnight_local + 3600, apower_w: 0, aenergy_wh: 1100.0)

    payload = TrmnlPayloadBuilder.new(config: @config).build
    mv = payload.fetch("merge_variables")

    assert_in_delta 1.00,  mv["pv_kwh"],     0.001
    assert_in_delta 0.60,  mv["cons_kwh"],   0.001
    assert_in_delta 0.40,  mv["bilanz_kwh"], 0.001
    assert_kind_of Integer, mv["autarky"]
    assert_kind_of Integer, mv["self_use"]
  end

  test "build returns zeros when no samples exist" do
    payload = TrmnlPayloadBuilder.new(config: @config).build
    mv = payload.fetch("merge_variables")
    assert_equal 0.0, mv["pv_kwh"]
    assert_equal 0.0, mv["cons_kwh"]
    assert_equal 0.0, mv["bilanz_kwh"]
    assert_equal 0,   mv["autarky"]
    assert_equal 0,   mv["self_use"]
  end
end
