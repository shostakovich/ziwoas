defmodule Ziwoas.GermanNumberTest do
  use ExUnit.Case, async: true

  alias Ziwoas.GermanNumber

  describe "format/2" do
    test "groups thousands with dots and uses a decimal comma" do
      assert GermanNumber.format(1_234_567) == "1.234.567"
      assert GermanNumber.format(1234.5, precision: 2) == "1.234,50"
      assert GermanNumber.format(999) == "999"
    end

    test "pads integers to the precision" do
      assert GermanNumber.format(5, precision: 2) == "5,00"
    end

    test "rounds half away from zero on the shortest decimal form" do
      assert GermanNumber.format(2.5) == "3"
      assert GermanNumber.format(-2.5) == "−3"
      assert GermanNumber.format(2.675, precision: 2) == "2,68"
      assert GermanNumber.format(0.125, precision: 2) == "0,13"
    end

    test "writes a true minus, but none for a value that rounds to zero" do
      assert GermanNumber.format(-1234.4) == "−1.234"
      assert GermanNumber.format(-0.4) == "0"
      assert GermanNumber.format(-0.004, precision: 2) == "0,00"
      assert GermanNumber.format(-0.0) == "0"
    end

    test "takes decimals" do
      assert GermanNumber.format(Decimal.new("-1234.567"), precision: 1) == "−1.234,6"
    end

    test "reads nil and NaN as a dash" do
      assert GermanNumber.format(nil) == "—"
      assert GermanNumber.format(:nan, unit: "W") == "— W"
      assert GermanNumber.format(Decimal.new("NaN")) == "—"
    end

    test "appends the unit" do
      assert GermanNumber.format(21.04, precision: 1, unit: "°C") == "21,0 °C"
    end
  end

  describe "flow/2" do
    @words [positive: "Bezug", negative: "Einspeisung"]

    test "names the direction instead of a sign" do
      assert GermanNumber.flow(1500, @words) == "Bezug 1.500 W"
      assert GermanNumber.flow(-230.6, @words) == "Einspeisung 231 W"

      assert GermanNumber.flow(Decimal.new("-1.25"), [precision: 1, unit: "kWh"] ++ @words) ==
               "Einspeisung 1,3 kWh"
    end

    test "a flow that rounds to zero has no direction" do
      assert GermanNumber.flow(0.4, @words) == "0 W"
      assert GermanNumber.flow(-0.4, @words) == "0 W"
    end

    test "a missing flow is a dash" do
      assert GermanNumber.flow(nil, @words) == "— W"
    end
  end
end
