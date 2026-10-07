defmodule Ziwoas.Plugs.EnergyDeltasTest do
  use Ziwoas.DataCase

  import Ecto.Query

  alias Ziwoas.Plugs.EnergyDeltas
  alias Ziwoas.Repo

  @t0 1_700_000_000

  defp deltas(plug_ids \\ nil, start_ts \\ @t0, end_ts \\ @t0 + 86_400) do
    from(d in subquery(EnergyDeltas.query(start_ts, end_ts, plug_ids)),
      order_by: [d.plug_id, d.ts],
      select: {d.plug_id, d.ts, d.delta_wh}
    )
    |> Repo.all()
    |> Enum.map(fn {plug_id, ts, delta} -> {plug_id, ts - @t0, delta} end)
  end

  defp counter!(plug_id, readings) do
    for {offset, wh} <- readings, do: insert_sample!(plug_id, @t0 + offset, 0.0, wh)
  end

  test "a counter's increments, the first sample of the window counting nothing" do
    counter!("fridge", [{0, 100.0}, {60, 101.5}, {120, 104.0}])

    assert deltas() == [{"fridge", 0, 0}, {"fridge", 60, 1.5}, {"fridge", 120, 2.5}]
  end

  test "a counter that goes backwards was reset: that step counts nothing, the next ones do" do
    counter!("fridge", [{0, 5000.0}, {60, 5001.0}, {120, 0.5}, {180, 2.0}])

    assert deltas() == [
             {"fridge", 0, 0},
             {"fridge", 60, 1.0},
             {"fridge", 120, 0},
             {"fridge", 180, 1.5}
           ]
  end

  test "an unchanged counter is a zero step, not a reset" do
    counter!("fridge", [{0, 7.0}, {60, 7.0}])

    assert deltas() == [{"fridge", 0, 0}, {"fridge", 60, 0.0}]
  end

  test "a jump above 20 kW over its gap is a glitch; up to the limit it counts" do
    limit_wh_per_minute = EnergyDeltas.max_plausible_w() / 60

    counter!("fridge", [
      {0, 0.0},
      {60, limit_wh_per_minute},
      {120, 2 * limit_wh_per_minute + 0.1}
    ])

    assert [{_, 0, 0}, {_, 60, at_limit}, {_, 120, 0}] = deltas()
    assert_in_delta at_limit, limit_wh_per_minute, 1.0e-9
  end

  test "a gap in the samples spreads the plausible energy over its length" do
    counter!("heater", [{0, 0.0}, {7200, 30_000.0}])
    counter!("glitch", [{0, 0.0}, {7200, 50_000.0}])

    assert deltas() == [
             {"glitch", 0, 0},
             {"glitch", 7200, 0},
             {"heater", 0, 0},
             {"heater", 7200, 30_000.0}
           ]
  end

  test "the window is start-inclusive and end-exclusive; the step into it is not counted" do
    counter!("fridge", [{-60, 10.0}, {0, 11.0}, {60, 12.0}, {120, 13.0}])

    assert deltas(nil, @t0, @t0 + 120) == [{"fridge", 0, 0}, {"fridge", 60, 1.0}]
  end

  test "plugs are independent; the plug filter keeps only the listed ones" do
    counter!("fridge", [{0, 1.0}, {60, 2.0}])
    counter!("tv", [{30, 50.0}, {90, 49.0}])

    assert deltas(["tv"]) == [{"tv", 30, 0}, {"tv", 90, 0}]
    assert length(deltas(["fridge", "tv"])) == 4
    assert deltas([]) == []
  end
end
