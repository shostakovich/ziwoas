require "test_helper"

class SchedulerStateTest < ActiveSupport::TestCase
  setup { Switching::SchedulerState.delete_all }

  test "last_tick_at is nil without a row for that plug" do
    assert_nil Switching::SchedulerState.last_tick_at("fridge")
  end

  test "advance! creates then updates a single row per plug" do
    t1 = Time.zone.local(2026, 6, 15, 12, 0)
    t2 = Time.zone.local(2026, 6, 15, 12, 1)

    Switching::SchedulerState.advance!("fridge", t1)
    assert_equal t1, Switching::SchedulerState.last_tick_at("fridge")

    Switching::SchedulerState.advance!("fridge", t2)
    assert_equal t2, Switching::SchedulerState.last_tick_at("fridge")
    assert_equal 1, Switching::SchedulerState.count
  end

  test "each plug carries its own watermark" do
    t1 = Time.zone.local(2026, 6, 15, 12, 0)
    t2 = Time.zone.local(2026, 6, 15, 13, 0)

    Switching::SchedulerState.advance!("fridge", t1)
    Switching::SchedulerState.advance!("senseo", t2)

    assert_equal t1, Switching::SchedulerState.last_tick_at("fridge")
    assert_equal t2, Switching::SchedulerState.last_tick_at("senseo")
  end

  test "a plug is watermarked only once" do
    Switching::SchedulerState.advance!("fridge", Time.current)

    assert_raises(ActiveRecord::RecordNotUnique) do
      Switching::SchedulerState.insert!({ plug_id: "fridge", last_tick_at: Time.current })
    end
  end
end
