defmodule Ziwoas.Govee.TypesTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Govee.Types

  describe "integer/1" do
    test "takes integers, truncates floats and parses decimal strings" do
      assert Types.integer(42) == {:ok, 42}
      assert Types.integer(4.9) == {:ok, 4}
      assert Types.integer(-4.9) == {:ok, -4}
      assert Types.integer("42") == {:ok, 42}
      assert Types.integer(" 42\n") == {:ok, 42}
      assert Types.integer("+5") == {:ok, 5}
      assert Types.integer("-3") == {:ok, -3}
      assert Types.integer("1_000") == {:ok, 1000}
      # A leading zero is decimal, not octal.
      assert Types.integer("010") == {:ok, 10}
    end

    test "refuses fractions, garbage and other types" do
      for value <- ["4.2", "", " ", "4 2", "12abc", "0x10", "1__0", "_1", nil, true, ["1"]],
          do: assert(Types.integer(value) == :error, inspect(value))
    end
  end

  test "the ranged integers" do
    assert Types.brightness("0") == {:ok, 0}
    assert Types.brightness(100) == {:ok, 100}
    assert Types.brightness(101) == :error
    assert Types.brightness(-1) == :error

    assert Types.kelvin(0) == {:ok, 0}
    assert Types.kelvin(9000) == {:ok, 9000}
    assert Types.kelvin(-1) == :error

    assert Types.rgb_component("255") == {:ok, 255}
    assert Types.rgb_component(256) == :error
    assert Types.rgb_component("x") == :error
  end

  test "a string is never coerced" do
    assert Types.string("") == {:ok, ""}
    assert Types.string(1) == :error
  end
end
