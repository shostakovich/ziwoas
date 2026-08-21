require "test_helper"

class PlugStateTest < ActiveSupport::TestCase
  setup { Plugs::State.delete_all }

  test "record_output creates a row and returns true" do
    assert Plugs::State.record_output("fridge", true)
    assert_equal true, Plugs::State.find_by(plug_id: "fridge").output
  end

  test "record_output with unchanged output writes nothing and returns false" do
    travel_to Time.zone.local(2026, 6, 15, 12, 0) do
      Plugs::State.record_output("fridge", true)
    end
    travel_to Time.zone.local(2026, 6, 15, 12, 5) do
      refute Plugs::State.record_output("fridge", true)
    end
    assert_equal Time.zone.local(2026, 6, 15, 12, 0), Plugs::State.find_by(plug_id: "fridge").updated_at
  end

  test "record_output updates on change" do
    Plugs::State.record_output("fridge", true)
    assert Plugs::State.record_output("fridge", false)
    assert_equal false, Plugs::State.find_by(plug_id: "fridge").output
    assert_equal 1, Plugs::State.count
  end
end
