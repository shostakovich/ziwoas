require "test_helper"

class SwitchRules::ContractsTest < ActiveSupport::TestCase
  def window(**overrides)
    SwitchRules::Contracts::Window.new.call(
      { on_at_time: "10:00", off_at_time: "20:00", days: [ 1, 2 ] }.merge(overrides)
    )
  end

  def single(**overrides)
    SwitchRules::Contracts::Single.new.call(
      { at_minute_time: "22:00", action: "off", days: [ 1 ] }.merge(overrides)
    )
  end

  def messages(result) = result.errors.map(&:text)

  # --- Window -----------------------------------------------------------

  test "Window passes and coerces the weekdays from the checkbox strings" do
    result = window(days: %w[1 2])

    assert result.success?
    assert_equal({ on_at_time: "10:00", off_at_time: "20:00", days: [ 1, 2 ] }, result.to_h)
  end

  test "Window accepts a window running past midnight — the day shift is the service's job" do
    assert window(on_at_time: "22:00", off_at_time: "06:00").success?
  end

  test "Window rejects a malformed or missing time" do
    assert_equal [ SwitchRules::Contracts::MESSAGES[:time] ], messages(window(on_at_time: "25:00"))
    assert_equal [ SwitchRules::Contracts::MESSAGES[:time] ], messages(window(off_at_time: ""))
    assert_equal [ SwitchRules::Contracts::MESSAGES[:time] ], messages(window(on_at_time: nil))
  end

  test "Window rejects two identical times — a window without duration" do
    assert_equal [ SwitchRules::Contracts::MESSAGES[:same] ],
                 messages(window(on_at_time: "10:00", off_at_time: "10:00"))
  end

  test "Window rejects an empty or out-of-range set of weekdays" do
    assert_equal [ SwitchRules::Contracts::MESSAGES[:days] ], messages(window(days: []))
    assert_equal [ SwitchRules::Contracts::MESSAGES[:days] ], messages(window(days: [ 8 ]))
  end

  # --- Single -----------------------------------------------------------

  test "Single passes for both directions" do
    assert single(action: "off").success?
    assert single(action: "on").success?
    assert_equal({ at_minute_time: "22:00", action: "on", days: [ 1 ] }, single(action: "on").to_h)
  end

  test "Single rejects a direction that is neither on nor off" do
    assert_equal [ SwitchRules::Contracts::MESSAGES[:action] ], messages(single(action: "toggle"))
    assert_equal [ SwitchRules::Contracts::MESSAGES[:action] ], messages(single(action: nil))
  end

  test "Single rejects a malformed time and an empty set of weekdays" do
    assert_equal [ SwitchRules::Contracts::MESSAGES[:time] ], messages(single(at_minute_time: "7:60"))
    assert_equal [ SwitchRules::Contracts::MESSAGES[:days] ], messages(single(days: []))
  end
end
