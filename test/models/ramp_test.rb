require "test_helper"

class RampTest < ActiveSupport::TestCase
  cover "Ramp*"

  test "ends of the ramp are the outer stops" do
    ramp = Ramp.fetch(:amber)

    assert_equal "#fff8e1", ramp.color(0.0)
    assert_equal "#a85300", ramp.color(1.0)
  end

  test "mixes between the two stops a fraction falls into" do
    ramp = Ramp.new(%w[#000000 #ffffff])

    assert_equal "#808080", ramp.color(0.5)
    assert_equal "#333333", ramp.color(0.2)
  end

  test "picks the right pair out of a longer ramp" do
    ramp = Ramp.new(%w[#000000 #ff0000 #ffffff])

    assert_equal "#ff0000", ramp.color(0.5)
    assert_equal "#800000", ramp.color(0.25)
    assert_equal "#ff8080", ramp.color(0.75)
  end

  test "clamps fractions outside the ramp" do
    ramp = Ramp.new(%w[#000000 #ffffff])

    assert_equal "#000000", ramp.color(-4.0)
    assert_equal "#ffffff", ramp.color(9.0)
  end

  test "offers the ramp as a css gradient for the legend" do
    assert_equal "linear-gradient(90deg, #000000, #ffffff)", Ramp.new(%w[#000000 #ffffff]).css_gradient
  end

  test "knows the three named ramps and nothing else" do
    assert_equal %i[amber blue grey diverging], Ramp::STOPS.keys
    assert_raises(KeyError) { Ramp.fetch(:violet) }
  end
end
