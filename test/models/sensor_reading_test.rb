require "test_helper"

class SensorReadingTest < ActiveSupport::TestCase
  test "for_device scope filters by device_id" do
    a = SensorReading.create!(device_id: "AAA", taken_at: 1.hour.ago, temperature: 20.0)
    SensorReading.create!(device_id: "BBB", taken_at: 1.hour.ago, temperature: 21.0)
    assert_equal [ a.id ], SensorReading.for_device("AAA").pluck(:id)
  end

  test "since scope returns rows at-or-after timestamp" do
    cutoff = 30.minutes.ago
    older  = SensorReading.create!(device_id: "X", taken_at: 2.hours.ago, temperature: 1.0)
    newer  = SensorReading.create!(device_id: "X", taken_at: 10.minutes.ago, temperature: 2.0)
    ids = SensorReading.since(cutoff).pluck(:id)
    refute_includes ids, older.id
    assert_includes ids, newer.id
  end

  test "latest_per_device returns one row per device with max taken_at" do
    SensorReading.create!(device_id: "A", taken_at: 2.hours.ago, temperature: 18.0)
    a_new = SensorReading.create!(device_id: "A", taken_at: 5.minutes.ago, temperature: 22.0)
    b_new = SensorReading.create!(device_id: "B", taken_at: 10.minutes.ago, temperature: 14.0)

    rows = SensorReading.latest_per_device([ "A", "B" ]).order(:device_id)
    assert_equal [ a_new.id, b_new.id ], rows.pluck(:id)
  end
end
