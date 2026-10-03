require "test_helper"

class RampTest < ActiveSupport::TestCase
  cover "Ramp*"

  test "ends of the ramp are the outer stops" do
    ramp = Ramp.fetch(:amber)

    assert_equal "var(--ramp-amber-0)", ramp.color(0.0)
    assert_equal "var(--ramp-amber-2)", ramp.color(1.0)
  end

  test "mixes between the two stops a fraction falls into" do
    ramp = Ramp.new(%w[black white])

    assert_equal "color-mix(in oklab, white 50%, black)", ramp.color(0.5)
    assert_equal "color-mix(in oklab, white 20%, black)", ramp.color(0.2)
  end

  test "picks the right pair out of a longer ramp" do
    ramp = Ramp.new(%w[black red white])

    assert_equal "red", ramp.color(0.5)
    assert_equal "color-mix(in oklab, red 50%, black)", ramp.color(0.25)
    assert_equal "color-mix(in oklab, white 50%, red)", ramp.color(0.75)
  end

  test "finds the pair in the upper half of a ramp with many stops" do
    ramp = Ramp.new(%w[a b c d e])

    assert_equal "color-mix(in oklab, e 60%, d)", ramp.color(0.9)
    assert_equal "e", ramp.color(1.0)
  end

  test "writes the share with one decimal at most" do
    ramp = Ramp.new(%w[black white])

    assert_equal "color-mix(in oklab, white 33.3%, black)", ramp.color(1 / 3.0)
    assert_equal "color-mix(in oklab, white 6.3%, black)", ramp.color(0.0625)
  end

  test "a share that rounds to a stop is that stop" do
    ramp = Ramp.new(%w[black white])

    assert_equal "black", ramp.color(0.0004)
    assert_equal "white", ramp.color(0.9996)
  end

  test "clamps fractions outside the ramp" do
    ramp = Ramp.new(%w[black white])

    assert_equal "black", ramp.color(-4.0)
    assert_equal "white", ramp.color(9.0)
  end

  test "offers the ramp as a css gradient for the legend" do
    assert_equal "linear-gradient(90deg, black, white)", Ramp.new(%w[black white]).css_gradient
  end

  test "knows the named ramps and nothing else" do
    assert_equal %i[amber blue grey diverging], Ramp::STOPS.keys
    assert_equal "linear-gradient(90deg, var(--ramp-low), var(--ramp-neutral), var(--ramp-high))",
                 Ramp.fetch(:diverging).css_gradient
    assert_raises(KeyError) { Ramp.fetch(:violet) }
  end
end
