defmodule ZiwoasWeb.Charts.DashboardTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Clock, Config}
  alias Ziwoas.Plugs.{Plug, Roster}
  alias ZiwoasWeb.Charts.Dashboard

  @plugs [
    %Plug{id: "bkw", name: "BKW", role: :producer},
    %Plug{id: "fridge", name: "Fridge", role: :consumer}
  ]
  @end_ts "2026-06-01T12:30:00Z" |> Clock.parse!() |> DateTime.to_unix()

  defp today, do: Dashboard.today(%Config{plugs: @plugs}, @end_ts)

  defp hour(index), do: @end_ts - 86_400 - 1800 + index * 3600

  test "energy per hour across the 24 h window, the producer's noise as nothing" do
    for minute <- 0..59 do
      insert_sample!("bkw", hour(0) + minute * 60, -600.0, minute * 10.0)
      insert_sample!("fridge", hour(23) + minute * 60, 120.0, minute * 2.0)
      insert_sample!("bkw", hour(5) + minute * 60, -1.0, 0.0)
    end

    energy = today().energy

    assert length(energy.hours) == 25
    assert hd(energy.hours) == hour(0) * 1000
    assert Enum.at(energy.produced_kwh, 0) == 0.6
    assert Enum.at(energy.produced_kwh, 5) == 0.0
    assert [%{plug_id: "fridge", name: "Fridge", kwh: kwh}] = energy.consumers
    assert {Enum.at(kwh, 23), Enum.sum(kwh)} == {0.12, 0.12}
  end

  test "power as [ts, watts] per plug, the producer positive" do
    insert_sample!("bkw", @end_ts - 60, -400.0, 1.0)

    assert [%{plug_id: "bkw", role: :producer, points: [[ts, 400.0]]}, %{points: []}] =
             today().power.series

    assert ts == div(@end_ts - 60, 60) * 60
  end

  test "rows and summaries in German, hours on the household's clock" do
    energy = %{
      hours: [hour(0) * 1000, hour(1) * 1000],
      produced_kwh: [0.6, 0.0],
      consumers: [
        %{plug_id: "a", name: "A", kwh: [0.1, 0.2]},
        %{plug_id: "b", name: "B", kwh: [0.0, 0.3]}
      ]
    }

    assert Enum.map(Dashboard.energy_rows(energy, "Europe/Berlin"), &{&1.time, &1.consumed}) ==
             [{"14:00", 0.1}, {"15:00", 0.5}]

    assert Dashboard.energy_summary(energy) ==
             "Energie der letzten 24 Stunden: 0,60 kWh erzeugt, 0,60 kWh an den Steckdosen verbraucht."

    power = %{
      series: [
        %{plug_id: "bkw", points: [[1, 300.0], [2, 512.4]]},
        %{plug_id: "bkw2", points: [[1, 250.0], [2, nil]]},
        %{plug_id: "fridge", points: [[1, 100.0], [2, nil]]},
        %{plug_id: "tv", points: [[1, 50.0], [2, 80.0]]}
      ]
    }

    roster =
      Roster.new(
        @plugs ++
          [
            %Plug{id: "bkw2", name: "BKW 2", role: :producer},
            %Plug{id: "tv", name: "TV", role: :consumer}
          ]
      )

    assert Dashboard.power_summary(power, roster) ==
             "Leistung der letzten 24 Stunden: höchstens 550 W erzeugt, höchstens 150 W verbraucht."
  end
end
