require "test_helper"

class ZeroExportControllerTest < Minitest::Test
  def test_target_follows_consumption_when_above_floor
    assert_equal 250, ZeroExportController.target_output_w(consumption_w: 250.4, floor_w: 100)
  end

  def test_floor_is_lower_bound
    assert_equal 100, ZeroExportController.target_output_w(consumption_w: 40, floor_w: 100)
  end

  def test_capped_at_max_output
    assert_equal 800, ZeroExportController.target_output_w(consumption_w: 1500, floor_w: 100)
  end

  def test_never_negative
    assert_equal 0, ZeroExportController.target_output_w(consumption_w: -50, floor_w: -10)
  end

  def test_constants
    assert_equal 800, ZeroExportController::MAX_OUTPUT_W
    assert_equal 10, ZeroExportController::MIN_SOC_PCT
  end
end
