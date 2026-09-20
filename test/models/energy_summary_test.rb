require "test_helper"

class EnergySummaryTest < ActiveSupport::TestCase
  cover "EnergySummary*"

  setup do
    Plugs::Sample.delete_all
    Plugs::DailyTotal.delete_all

    plug_bkw    = ConfigLoader::PlugCfg.new(id: "bkw",    name: "BKW",   role: :producer, driver: :shelly, ain: nil)
    plug_fridge = ConfigLoader::PlugCfg.new(id: "fridge", name: "Fridge", role: :consumer, driver: :shelly, ain: nil)
    mqtt = ConfigLoader::MqttCfg.new(host: "localhost", port: 1883, topic_prefix: "shellies")
    Economics::ElectricityPrice.delete_all
    Economics::ElectricityPrice.create!(valid_from: "2020-01-01", eur_per_kwh: 0.32)

    @config = ConfigLoader::Config.new(
      location: Location.new(timezone: "Europe/Berlin"),
      mqtt: mqtt,
      fritz_poll: nil,
      plugs: [ plug_bkw, plug_fridge ],
      fritz_box: nil
    )
  end

  test "compute_today saves nothing from energy no consumer took at the time" do
    tz       = TZInfo::Timezone.get("Europe/Berlin")
    midnight = tz.local_to_utc(Time.parse("#{Date.today} 00:00:00")).to_i

    Plugs::Sample.create!(plug_id: "bkw",    ts: midnight + 60,   apower_w: 0, aenergy_wh: 0.0)
    Plugs::Sample.create!(plug_id: "bkw",    ts: midnight + 3600, apower_w: 0, aenergy_wh: 1000.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: midnight + 60,   apower_w: 0, aenergy_wh: 500.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: midnight + 3600, apower_w: 0, aenergy_wh: 600.0)

    summary = EnergySummary.new(config: @config).compute_today

    assert_in_delta 1000.0, summary.produced.wh
    assert_in_delta 100.0,  summary.consumed.wh
    # Counters without simultaneous power: nothing was demonstrably self-consumed,
    # so the produced kilowatt-hour replaced no bought one.
    assert_in_delta 0.0,    summary.savings_eur
    assert_equal Date.today.to_s, summary.date
  end

  test "compute_today returns zero when no samples" do
    summary = EnergySummary.new(config: @config).compute_today
    assert_in_delta 0.0, summary.produced.wh
    assert_in_delta 0.0, summary.consumed.wh
    assert_in_delta 0.0, summary.savings_eur
    assert_equal Date.today.to_s, summary.date
  end

  test "compute_today handles meter reset" do
    tz       = TZInfo::Timezone.get("Europe/Berlin")
    midnight = tz.local_to_utc(Time.parse("#{Date.today} 00:00:00")).to_i

    Plugs::Sample.create!(plug_id: "fridge", ts: midnight + 60,  apower_w: 0, aenergy_wh: 424_440.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: midnight + 120, apower_w: 0, aenergy_wh: 0.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: midnight + 180, apower_w: 0, aenergy_wh: 50.0)

    summary = EnergySummary.new(config: @config).compute_today

    assert_in_delta 50.0, summary.consumed.wh
  end

  test "compute_today ignores glitch zero then jump back" do
    tz       = TZInfo::Timezone.get("Europe/Berlin")
    midnight = tz.local_to_utc(Time.parse("#{Date.today} 00:00:00")).to_i

    Plugs::Sample.create!(plug_id: "fridge", ts: midnight + 60, apower_w: 145, aenergy_wh: 425_000.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: midnight + 65, apower_w: 145, aenergy_wh: 0.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: midnight + 70, apower_w: 145, aenergy_wh: 425_005.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: midnight + 75, apower_w: 145, aenergy_wh: 425_010.0)

    summary = EnergySummary.new(config: @config).compute_today

    assert_in_delta 5.0, summary.consumed.wh
  end

  test "compute_today returns self_consumed_wh from simultaneous overlap" do
    tz       = TZInfo::Timezone.get("Europe/Berlin")
    midnight = tz.local_to_utc(Time.parse("#{Date.today} 00:00:00")).to_i

    # 1h of producer 200W and consumer 100W simultaneously
    (0..3600).step(60) do |dt|
      Plugs::Sample.create!(plug_id: "bkw",    ts: midnight + dt, apower_w: 200.0, aenergy_wh: 200.0 * dt / 3600.0)
      Plugs::Sample.create!(plug_id: "fridge", ts: midnight + dt, apower_w: 100.0, aenergy_wh: 100.0 * dt / 3600.0)
    end

    summary = EnergySummary.new(config: @config).compute_today

    assert_in_delta 200.0, summary.produced.wh,      2.0
    assert_in_delta 100.0, summary.consumed.wh,      2.0
    assert_in_delta 100.0, summary.self_consumed.wh, 2.0
    assert_in_delta 1.0,   summary.autarky_ratio,           0.05
    assert_in_delta 0.5,   summary.self_consumption_ratio,  0.05
    # 100 Wh self-consumed at 0.32 €/kWh.
    assert_in_delta 0.032, summary.savings_eur, 0.001
  end

  test "compute_today reports no savings at all while no price is on record" do
    Economics::ElectricityPrice.delete_all

    assert_nil EnergySummary.new(config: @config).compute_today.savings_eur
  end

  test "compute_today ratios are zero when denominator is zero" do
    summary = EnergySummary.new(config: @config).compute_today
    assert_equal 0.0, summary.autarky_ratio
    assert_equal 0.0, summary.self_consumption_ratio
  end

  test "compute_today excludes samples from beyond today's window" do
    tz       = TZInfo::Timezone.get("Europe/Berlin")
    midnight = tz.local_to_utc(Time.parse("#{Date.today} 00:00:00")).to_i

    Plugs::Sample.create!(plug_id: "bkw", ts: midnight + 60,   apower_w: 0, aenergy_wh: 0.0)
    Plugs::Sample.create!(plug_id: "bkw", ts: midnight + 3600, apower_w: 0, aenergy_wh: 100.0)
    # Tomorrow, well past the end of today's 24h window — must not feed the delta.
    Plugs::Sample.create!(plug_id: "bkw", ts: midnight + 90_000, apower_w: 0, aenergy_wh: 99_999.0)

    summary = EnergySummary.new(config: @config).compute_today

    assert_in_delta 100.0, summary.produced.wh
  end

  # Europe/Berlin 2026-10-25 is 25 hours long: a fixed 86_400-second window
  # drops the last hour of the day from today's balance.
  test "compute_today covers all 25 hours of a long DST day" do
    midnight = 1_792_879_200 # 2026-10-25 00:00 Berlin
    Plugs::Sample.create!(plug_id: "bkw", ts: midnight + 24 * 3600,        apower_w: 0, aenergy_wh: 1000.0)
    Plugs::Sample.create!(plug_id: "bkw", ts: midnight + 24 * 3600 + 1800, apower_w: 0, aenergy_wh: 1250.0)

    summary = travel_to(Time.at(midnight + 24 * 3600 + 3000)) do
      EnergySummary.new(config: @config).compute_today
    end

    assert_equal "2026-10-25", summary.date
    assert_in_delta 250.0, summary.produced.wh
  end
end
