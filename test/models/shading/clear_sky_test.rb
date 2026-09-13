require "test_helper"

class Shading::ClearSkyTest < ActiveSupport::TestCase
  cover "Shading::ClearSky*"

  test "gives no radiation while the sun is at or below the horizon" do
    assert_equal 0.0, Shading::ClearSky.w_per_m2(0.0)
    assert_equal 0.0, Shading::ClearSky.w_per_m2(-5.0)
  end

  test "reaches its maximum with the sun in the zenith" do
    assert_in_delta 1035.1, Shading::ClearSky.w_per_m2(90.0), 0.1
  end

  test "follows Haurwitz down the sky" do
    assert_in_delta 487.9, Shading::ClearSky.w_per_m2(30.0), 0.1
    assert_in_delta 48.6, Shading::ClearSky.w_per_m2(5.0), 0.1
  end

  test "rises with the sun" do
    elevations = [ 10.0, 20.0, 40.0, 60.0 ]

    assert_equal elevations, elevations.sort_by { |elevation| Shading::ClearSky.w_per_m2(elevation) }
  end
end
