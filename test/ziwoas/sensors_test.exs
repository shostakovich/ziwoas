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

  test "latest_per_device: of readings sharing the newest instant the last stored wins" do
    reading!("A", 5, 20.0)
    last = reading!("A", 5, 21.0)

    assert Sensors.latest_per_device(["A"])["A"].id == last.id
  end

  test "create_reading stores the measurements, rounding whole numbers given as floats" do
    assert {:ok, reading} =
             Sensors.create_reading("A", @now, %{
               temperature: 21,
               humidity: 52.7,
               co2: 612.4,
               battery_pct: 99.5,
               firmware_version: "V1",
               raw: %{"ignored" => true}
             })

    assert {reading.device_id, reading.taken_at, reading.temperature} == {"A", @now, 21.0}
    assert {reading.humidity, reading.co2, reading.battery_pct} == {53, 612, 100}
    assert Sensors.latest("A").id == reading.id
  end

  test "create_reading refuses a measurement that does not cast" do
    assert {:error, %Ecto.Changeset{}} = Sensors.create_reading("A", @now, %{temperature: "warm"})
    assert Sensors.latest("A") == nil
  end

  test "CO₂ traffic light" do
    assert Sensors.co2_level(%Reading{co2: 800}) == :good
    assert Sensors.co2_level(%Reading{co2: 1000}) == :warn
    assert Sensors.co2_level(1399) == :warn
    assert Sensors.co2_level(1400) == :warn
    assert Sensors.co2_level(1401) == :bad
    assert Sensors.co2_level(%Reading{}) == nil
    assert Sensors.co2_level(nil) == nil
  end

  test "battery low at 20 % or less" do
    assert Sensors.battery_low?(%Reading{battery_pct: 20})
    assert Sensors.battery_low?(%Reading{battery_pct: 5})
    refute Sensors.battery_low?(%Reading{battery_pct: 21})
    refute Sensors.battery_low?(%Reading{})
    refute Sensors.battery_low?(nil)
  end

  test "age in whole seconds, offline after 30 minutes or without a reading" do
    ago = &%Reading{taken_at: DateTime.add(@now, -&1, :millisecond)}

    assert Sensors.age_s(ago.(4_999), @now) == 4
    assert Sensors.age_s(nil, @now) == nil
    refute Sensors.offline?(ago.(30 * 60 * 1000), @now)
    assert Sensors.offline?(ago.(30 * 60 * 1000 + 1), @now)
    assert Sensors.offline?(nil, @now)
  end
end
