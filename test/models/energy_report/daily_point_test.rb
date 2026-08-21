require "test_helper"

class EnergyReport::DailyPointTest < ActiveSupport::TestCase
  cover "EnergyReport::DailyPoint*"

  test "balance is what the day produced beyond what it consumed" do
    point = EnergyReport::DailyPoint.new(
      date: "2026-04-10",
      produced: Energy.wh(2_000.0),
      consumed: Energy.wh(300.0),
      self_consumed: Energy.wh(250.0),
      covered: true
    )

    assert_equal Energy.wh(1_700.0), point.balance
  end

  test "balance goes negative when the day consumed more than it produced" do
    point = EnergyReport::DailyPoint.new(
      date: "2026-04-10",
      produced: Energy.wh(300.0),
      consumed: Energy.wh(2_000.0),
      self_consumed: Energy.wh(250.0),
      covered: true
    )

    assert_equal Energy.wh(-1_700.0), point.balance
  end

  test "an uncovered day keeps its date and holds no energy at all" do
    point = EnergyReport::DailyPoint.uncovered("2026-04-11")

    assert_equal "2026-04-11", point.date
    assert_equal Energy.zero, point.produced
    assert_equal Energy.zero, point.consumed
    assert_equal Energy.zero, point.self_consumed
    assert_equal Energy.zero, point.balance
    assert_not point.covered
  end
end
