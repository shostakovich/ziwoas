require "test_helper"

class PlugMeasurementTest < ActiveSupport::TestCase
  setup { Sample.delete_all }

  def sample(plug_id, age_s, watt, now:)
    Sample.create!(plug_id: plug_id, ts: now.to_i - age_s, apower_w: watt, aenergy_wh: 1.0)
  end

  test "the newest sample of a plug is the one reported" do
    now = Time.at(1_000_000)
    sample("fridge", 30, 100.0, now: now)
    sample("fridge", 5,  120.0, now: now)

    measurement = PlugMeasurement.for([ "fridge" ], now: now)["fridge"]

    assert_in_delta 120.0, measurement.watt
    assert_equal now - 5, measurement.last_seen_at
  end

  test "a plug goes offline once its newest sample outlives the Frist" do
    now = Time.at(1_000_000)
    sample("fridge", 130, 120.0, now: now)
    sample("tv",     110, 30.0,  now: now)

    collection = PlugMeasurement.for(%w[fridge tv], now: now, offline_after_s: 120)

    assert collection["fridge"].offline?
    refute collection["tv"].offline?
  end

  test "a plug that never reported has no reading and is offline" do
    now = Time.at(1_000_000)

    measurement = PlugMeasurement.for([ "fridge" ], now: now)["fridge"]

    assert_nil measurement.watt
    assert_nil measurement.last_seen_at
    assert measurement.offline?
  end

  test "total_w adds up the plugs that are not offline" do
    now = Time.at(1_000_000)
    sample("fridge", 5,   120.0, now: now)
    sample("tv",     5,   30.0,  now: now)
    sample("heater", 130, 500.0, now: now)

    collection = PlugMeasurement.for(%w[fridge tv heater], now: now, offline_after_s: 120)

    assert_in_delta 150.0, collection.total_w
  end

  test "total_w is unknown rather than zero when everything is offline" do
    now = Time.at(1_000_000)
    sample("fridge", 130, 120.0, now: now)

    collection = PlugMeasurement.for([ "fridge" ], now: now, offline_after_s: 120)

    assert_nil collection.total_w
  end

  test "a measured zero counts, unlike a missing sample" do
    now = Time.at(1_000_000)
    sample("fridge", 5, 0.0, now: now)

    collection = PlugMeasurement.for(%w[fridge tv], now: now, offline_after_s: 120)

    assert_equal 0.0, collection.total_w
  end

  test "total_w can be narrowed to some of the plugs" do
    now = Time.at(1_000_000)
    sample("fridge", 5, 120.0, now: now)
    sample("bkw",    5, 500.0, now: now)

    collection = PlugMeasurement.for(%w[fridge bkw], now: now, offline_after_s: 120)

    assert_in_delta 120.0, collection.total_w([ "fridge" ])
  end

  test "total_w refuses plugs the collection never measured" do
    collection = PlugMeasurement.for([ "fridge" ], now: Time.at(1_000_000))

    assert_raises(ArgumentError) { collection.total_w(%w[fridge tv]) }
  end

  test "total_w of no plugs at all is unknown" do
    assert_nil PlugMeasurement.for([], now: Time.at(1_000_000)).total_w
  end
end
