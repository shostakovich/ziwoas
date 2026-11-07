defmodule Ziwoas.Solakon.Control.StateTest do
  use Ziwoas.DataCase

  alias Ziwoas.Solakon.Control
  alias Ziwoas.Solakon.Control.Decision

  test "a new state holds the battery at 10 %" do
    assert Control.state!().min_soc_pct == 10
  end

  test "the minimum charge takes 10 to 90 %" do
    state = Control.state!()

    assert {:ok, %{min_soc_pct: 25}} = Control.set_min_soc(state, %{"min_soc_pct" => "25"})
    assert Control.state().min_soc_pct == 25

    for value <- ["9", "91", "", " ", "zehn", "12.5"] do
      assert {:error, changeset} = Control.set_min_soc(state, %{"min_soc_pct" => value})

      assert [min_soc_pct: {"Mindestladung zwischen 10 und 90 % angeben", _}] = changeset.errors
    end

    assert Control.state().min_soc_pct == 25
  end

  test "a tick storing its decision on an older read keeps a minimum saved meanwhile" do
    read_by_tick = Control.state!()
    {:ok, _saved} = Control.set_min_soc(Control.state!(), %{"min_soc_pct" => "40"})

    read_by_tick
    |> Control.store!(%Decision{state: :normal, target_w: 200, trim: false}, DateTime.utc_now())
    |> Control.count_failure!()
    |> Control.clear!()

    assert Control.state().min_soc_pct == 40
  end
end
