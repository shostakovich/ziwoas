defmodule Ziwoas.Govee.TypesTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Govee.Types

  describe "bool/1" do
    test "takes booleans, 1/0 and their word forms" do
      for value <- [true, 1, "1", "on", "ON", "true", "True", "t", "yes", "Y"],
          do: assert(Types.bool(value) == {:ok, true}, inspect(value))

      for value <- [false, 0, "0", "off", "Off", "false", "FALSE", "f", "no", "N"],
          do: assert(Types.bool(value) == {:ok, false}, inspect(value))
    end

    test "refuses anything else" do
      for value <- [nil, "", "2", 2, "maybe", " true", 1.0, [], %{}],
          do: assert(Types.bool(value) == :error, inspect(value))
    end
  end

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

  test "strings: a name is non-empty, neither is ever coerced" do
    assert Types.name("Forest") == {:ok, "Forest"}
    assert Types.name("") == :error
    assert Types.name(:forest) == :error
    assert Types.string("") == {:ok, ""}
    assert Types.string(1) == :error
  end

  test "optional integers are strict" do
    assert Types.optional_integer(nil) == {:ok, nil}
    assert Types.optional_integer(2700) == {:ok, 2700}
    assert Types.optional_integer("2700") == :error
    assert Types.optional_integer(2700.0) == :error
  end

  test "list_of coerces every element in order or fails as a whole" do
    assert Types.list_of(["1", 2, 3.5], &Types.integer/1) == {:ok, [1, 2, 3]}
    assert Types.list_of([], &Types.integer/1) == {:ok, []}
    assert Types.list_of(["1", "x"], &Types.integer/1) == :error
    assert Types.list_of("1", &Types.integer/1) == :error
  end
end
