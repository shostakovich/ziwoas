defmodule Ziwoas.RampTest do
  # Mirrors test/models/ramp_test.rb.
  use ExUnit.Case, async: true

  alias Ziwoas.Ramp

  test "snaps a fraction to the nearest of 64 levels" do
    assert Ramp.level(0.5) === 0.5
    assert Ramp.level(0.8) === 51 / 64.0
    assert Ramp.level(0.805) === 52 / 64.0
    assert Ramp.level(0.007) === 0.0
    assert Ramp.level(0.008) === 1 / 64.0
    assert Ramp.level(1.4) === 90 / 64.0, "past the end; the colour clamps it"
  end

  test "ends of the ramp are the outer stops" do
    ramp = Ramp.fetch(:amber)

    assert Ramp.color(ramp, 0.0) == "var(--ramp-amber-0)"
    assert Ramp.color(ramp, 1.0) == "var(--ramp-amber-2)"
  end

  test "mixes between the two stops a fraction falls into" do
    ramp = Ramp.new(~w[black white])

    assert Ramp.color(ramp, 0.5) == "color-mix(in oklab, white 50%, black)"
    assert Ramp.color(ramp, 0.2) == "color-mix(in oklab, white 20%, black)"
  end

  test "picks the right pair out of a longer ramp" do
    ramp = Ramp.new(~w[black red white])

    assert Ramp.color(ramp, 0.5) == "red"
    assert Ramp.color(ramp, 0.25) == "color-mix(in oklab, red 50%, black)"
    assert Ramp.color(ramp, 0.75) == "color-mix(in oklab, white 50%, red)"
  end

  test "finds the pair in the upper half of a ramp with many stops" do
    ramp = Ramp.new(~w[a b c d e])

    assert Ramp.color(ramp, 0.9) == "color-mix(in oklab, e 60%, d)"
    assert Ramp.color(ramp, 1.0) == "e"
  end

  test "writes the share with one decimal at most" do
    ramp = Ramp.new(~w[black white])

    assert Ramp.color(ramp, 1 / 3.0) == "color-mix(in oklab, white 33.3%, black)"
    assert Ramp.color(ramp, 0.0625) == "color-mix(in oklab, white 6.3%, black)"
  end

  test "a share that rounds to a stop is that stop" do
    ramp = Ramp.new(~w[black white])

    assert Ramp.color(ramp, 0.0004) == "black"
    assert Ramp.color(ramp, 0.9996) == "white"
  end

  test "clamps fractions outside the ramp" do
    ramp = Ramp.new(~w[black white])

    assert Ramp.color(ramp, -4.0) == "black"
    assert Ramp.color(ramp, 9.0) == "white"
  end

  test "offers the ramp as a css gradient for the legend" do
    assert Ramp.css_gradient(Ramp.new(~w[black white])) == "linear-gradient(90deg, black, white)"
  end

  test "knows the named ramps and nothing else" do
    assert Ramp.names() == [:amber, :blue, :grey, :diverging]

    assert Ramp.css_gradient(Ramp.fetch(:diverging)) ==
             "linear-gradient(90deg, var(--ramp-low), var(--ramp-neutral), var(--ramp-high))"

    assert_raise KeyError, fn -> Ramp.fetch(:violet) end
  end
end
