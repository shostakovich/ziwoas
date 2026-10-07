defmodule Ziwoas.Energy.AmountTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Energy.Amount

  test "zero is the empty amount" do
    assert Amount.zero() == Amount.wh(0)
    assert Amount.zero?(Amount.zero())
  end

  test "two amounts of the same size are equal" do
    assert Amount.wh(250) == Amount.from_kwh(0.25)
  end
end
