defmodule Ziwoas.Energy.AmountTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Energy.Amount

  test "zero is the empty amount" do
    assert Amount.zero() == Amount.wh(0)
    assert Amount.zero?(Amount.zero())
  end
end
