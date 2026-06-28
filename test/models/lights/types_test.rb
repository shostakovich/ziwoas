# test/models/lights/types_test.rb
require "test_helper"

class Lights::TypesTest < ActiveSupport::TestCase
  test "Bool coerces form strings" do
    assert_equal true,  Lights::Types::Bool["true"]
    assert_equal false, Lights::Types::Bool["false"]
  end

  test "Brightness coerces and enforces 1..100" do
    assert_equal 42, Lights::Types::Brightness["42"]
    assert_raises(Dry::Types::ConstraintError) { Lights::Types::Brightness["0"] }
    assert_raises(Dry::Types::ConstraintError) { Lights::Types::Brightness["101"] }
  end

  test "Kelvin accepts the full hardware envelope (per-device clamping is separate)" do
    assert_equal 2200, Lights::Types::Kelvin["2200"]
    assert_equal 6500, Lights::Types::Kelvin["6500"]
    assert_raises(Dry::Types::ConstraintError) { Lights::Types::Kelvin["1000"] }
    assert_raises(Dry::Types::ConstraintError) { Lights::Types::Kelvin["10000"] }
  end

  test "RgbComponent enforces 0..255" do
    assert_equal 255, Lights::Types::RgbComponent["255"]
    assert_raises(Dry::Types::ConstraintError) { Lights::Types::RgbComponent["256"] }
  end
end
