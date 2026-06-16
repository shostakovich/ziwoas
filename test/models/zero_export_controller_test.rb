require "test_helper"

class ZeroExportControllerTest < Minitest::Test
  def test_follows_fresh_consumption
    assert_equal 250, ZeroExportController.target_output_w(consumption_w: 250.4, floor_w: 100)
  end

  def test_fresh_consumption_below_floor_is_NOT_raised_to_floor
    # The whole point of the fix: fresh low load must not be overridden by the
    # historical floor (that would feed into the grid).
    assert_equal 40, ZeroExportController.target_output_w(consumption_w: 40, floor_w: 100)
  end

  def test_falls_back_to_floor_when_consumption_unknown
    assert_equal 146, ZeroExportController.target_output_w(consumption_w: nil, floor_w: 146)
  end

  def test_capped_at_max_output
    assert_equal 800, ZeroExportController.target_output_w(consumption_w: 1500, floor_w: 100)
  end

  def test_never_negative_with_fresh_data
    assert_equal 0, ZeroExportController.target_output_w(consumption_w: -50, floor_w: 100)
  end

  def test_never_negative_in_fallback
    assert_equal 0, ZeroExportController.target_output_w(consumption_w: nil, floor_w: -10)
  end

  def test_constants
    assert_equal 800, ZeroExportController::MAX_OUTPUT_W
    assert_equal 10, ZeroExportController::MIN_SOC_PCT
  end
end
