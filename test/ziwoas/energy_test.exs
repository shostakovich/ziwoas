defmodule Ziwoas.EnergyTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Energy

  test "zero is the empty amount" do
    assert Energy.zero() == Energy.wh(0)
    assert Energy.zero?(Energy.zero())
  end

  test "two amounts of the same size are equal" do
    assert Energy.wh(250) == Energy.from_kwh(0.25)
  end
end
