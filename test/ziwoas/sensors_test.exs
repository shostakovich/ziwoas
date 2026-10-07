defmodule Ziwoas.SensorsTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Repo, Sensors}
  alias Ziwoas.Sensors.Reading

  @now ~U[2026-05-04 10:00:00.000000Z]

  defp reading!(device_id, minutes_ago, temperature) do
    taken_at = DateTime.add(@now, -minutes_ago * 60, :second)
    Repo.insert!(%Reading{device_id: device_id, taken_at: taken_at, temperature: temperature})
  end

  test "since returns rows at or after the timestamp, oldest first" do
    older = reading!("X", 120, 1.0)
    newer = reading!("X", 10, 2.0)
    newest = reading!("X", 5, 3.0)
    reading!("Y", 5, 4.0)

    ids = Enum.map(Sensors.since(["X"], DateTime.add(@now, -30 * 60, :second)), & &1.id)

    refute older.id in ids
    assert ids == [newer.id, newest.id]
  end

  test "latest_per_device returns one row per device with max taken_at" do
    reading!("A", 120, 18.0)
    a_new = reading!("A", 5, 22.0)
    b_new = reading!("B", 10, 14.0)
    reading!("C", 1, 10.0)

    latest = Sensors.latest_per_device(["A", "B"])

    assert Map.keys(latest) |> Enum.sort() == ["A", "B"]
    assert latest["A"].id == a_new.id
    assert latest["B"].id == b_new.id
    assert Sensors.latest_per_device([]) == %{}
  end

  test "max_id follows the newest reading" do
    assert Sensors.max_id() == nil
    reading = reading!("A", 0, 20.0)
    assert Sensors.max_id() == reading.id
  end
end
