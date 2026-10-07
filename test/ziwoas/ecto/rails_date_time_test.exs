defmodule Ziwoas.Ecto.RailsDateTimeTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Clock
  alias Ziwoas.Ecto.RailsDateTime

  setup do
    on_exit(&Clock.unfreeze/0)
  end

  test "timestamps take the frozen clock, as ActiveRecord's under travel_to" do
    Clock.freeze("2026-10-05T12:00:00.5+02:00")
    assert RailsDateTime.utc_now() == ~U[2026-10-05 10:00:00.500000Z]
    assert RailsDateTime.dump(RailsDateTime.utc_now()) == {:ok, "2026-10-05 10:00:00.500000"}
  end
end
