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

  test "a sample goes stale long before its plug counts as offline" do
    now = Time.at(1_000_000)
    sample("fridge", 130, 120.0, now: now)

    measurement = PlugMeasurement.for([ "fridge" ], now: now, stale_after_s: 120)["fridge"]

    assert measurement.stale?
    refute measurement.offline?
  end

  test "a plug that stopped reporting altogether is offline" do
    now = Time.at(1_000_000)
    sample("fridge", 6 * 60, 120.0, now: now)

    measurement = PlugMeasurement.for([ "fridge" ], now: now, stale_after_s: 120)["fridge"]

    assert measurement.offline?
    assert measurement.stale?
  end

  test "a plug that never reported has no reading and is offline" do
    now = Time.at(1_000_000)

    measurement = PlugMeasurement.for([ "fridge" ], now: now)["fridge"]

    assert_nil measurement.watt
    assert_nil measurement.last_seen_at
    assert measurement.offline?
    assert measurement.stale?
  end

  test "total_w adds up the samples that are not stale" do
    now = Time.at(1_000_000)
    sample("fridge", 5,   120.0, now: now)
    sample("tv",     5,   30.0,  now: now)
    sample("heater", 130, 500.0, now: now)

    collection = PlugMeasurement.for(%w[fridge tv heater], now: now, stale_after_s: 120)

    assert_in_delta 150.0, collection.total_w
  end

  test "total_w is unknown rather than zero when nothing is fresh" do
    now = Time.at(1_000_000)
    sample("fridge", 130, 120.0, now: now)

    collection = PlugMeasurement.for([ "fridge" ], now: now, stale_after_s: 120)

    assert_nil collection.total_w
  end

  test "a measured zero counts, unlike a missing sample" do
    now = Time.at(1_000_000)
    sample("fridge", 5, 0.0, now: now)

    collection = PlugMeasurement.for(%w[fridge tv], now: now, stale_after_s: 120)

    assert_equal 0.0, collection.total_w
  end

  test "total_w can be narrowed to some of the plugs" do
    now = Time.at(1_000_000)
    sample("fridge", 5, 120.0, now: now)
    sample("bkw",    5, 500.0, now: now)

    collection = PlugMeasurement.for(%w[fridge bkw], now: now, stale_after_s: 120)

    assert_in_delta 120.0, collection.total_w([ "fridge" ])
  end

  test "total_w of no plugs at all is unknown" do
    assert_nil PlugMeasurement.for([], now: Time.at(1_000_000)).total_w
  end
end
