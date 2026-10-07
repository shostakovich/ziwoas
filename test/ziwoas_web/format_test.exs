defmodule ZiwoasWeb.FormatTest do
  use ExUnit.Case, async: true

  alias ZiwoasWeb.Format

  describe "number/2" do
    test "appends the unit after a space" do
      assert Format.number(1234.5, precision: 2, unit: "kWh") == "1.234,50 kWh"
    end

    test "groups thousands with dots and uses a decimal comma" do
      assert Format.number(1_234_567) == "1.234.567"
      assert Format.number(1234.5, precision: 2) == "1.234,50"
      assert Format.number(999) == "999"
    end

    test "pads integers to the precision" do
      assert Format.number(5, precision: 2) == "5,00"
    end

    test "rounds half away from zero on the shortest decimal form" do
      assert Format.number(2.5) == "3"
      assert Format.number(-2.5) == "−3"
      assert Format.number(2.675, precision: 2) == "2,68"
      assert Format.number(0.125, precision: 2) == "0,13"
    end

    test "writes a true minus, but none for a value that rounds to zero" do
      assert Format.number(-1234.4) == "−1.234"
      assert Format.number(-0.4) == "0"
      assert Format.number(-0.004, precision: 2) == "0,00"
      assert Format.number(-0.0) == "0"
    end

    test "takes decimals" do
      assert Format.number(Decimal.new("-1234.567"), precision: 1) == "−1.234,6"
    end

    test "reads nil and NaN as a dash" do
      assert Format.number(nil) == "—"
      assert Format.number(:nan, unit: "W") == "— W"
      assert Format.number(Decimal.new("NaN")) == "—"
    end

    test "appends the unit" do
      assert Format.number(21.04, precision: 1, unit: "°C") == "21,0 °C"
    end
  end

  describe "flow/2" do
    @words [positive: "Bezug", negative: "Einspeisung"]

    test "names the direction instead of a sign" do
      assert Format.flow(1500, @words) == "Bezug 1.500 W"
      assert Format.flow(-230.6, @words) == "Einspeisung 231 W"

      assert Format.flow(Decimal.new("-1.25"), [precision: 1, unit: "kWh"] ++ @words) ==
               "Einspeisung 1,3 kWh"
    end

    test "a flow that rounds to zero has no direction" do
      assert Format.flow(0.4, @words) == "0 W"
      assert Format.flow(-0.4, @words) == "0 W"
    end

    test "a missing flow is a dash" do
      assert Format.flow(nil, @words) == "— W"
    end
  end

  describe "eur/1" do
    test "euros with cents, a dash when unknown" do
      assert Format.eur(1234.5) == "1.234,50 €"
      assert Format.eur(-0.5) == "−0,50 €"
      assert Format.eur(nil) == "—"
    end
  end

  describe "dates" do
    test "date/1 and day_month/1" do
      assert Format.date(~D[2026-10-07]) == "07.10.2026"
      assert Format.day_month(~D[2026-03-01]) == "01.03."
    end
  end

  describe "clock/2" do
    test "the local wall-clock time of an instant" do
      assert Format.clock(~U[2026-10-07 05:04:00Z], "Europe/Berlin") == "07:04"
      assert Format.clock(~U[2026-01-07 23:30:00Z], "Europe/Berlin") == "00:30"
    end
  end
end
