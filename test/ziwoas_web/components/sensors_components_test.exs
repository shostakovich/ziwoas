defmodule ZiwoasWeb.SensorsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Ziwoas.Config.Sensor
  alias ZiwoasWeb.SensorsComponents

  defp gauge(ppm),
    do:
      render_component(&SensorsComponents.co2_gauge/1, ppm: ppm)
      |> LazyHTML.from_fragment()

  defp attrs(node, selector, name),
    do: node |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp needle_angle(ppm) do
    [transform] = attrs(gauge(ppm), "g.co2-gauge-needle", "transform")
    [_, angle] = Regex.run(~r/rotate\((-?[\d.]+)/, transform)
    String.to_float(angle)
  end

  test "the chart legends name the sensors on a free series in config order, the rest Weitere" do
    names = ~w[Eins Zwei Drei Vier Fünf Sechs Sieben]

    sensors =
      for {name, index} <- Enum.with_index(names),
          do: %Sensor{
            id: "S#{index}",
            name: name,
            type: if(name in ~w[Zwei Sieben], do: :meter_pro_co2, else: :outdoor_meter)
          }

    doc =
      render_component(&SensorsComponents.charts/1, sensors: sensors) |> LazyHTML.from_fragment()

    legend =
      &(doc
        |> LazyHTML.query("##{&1} li")
        |> Enum.map(fn li -> String.trim(LazyHTML.text(li)) end))

    assert legend.("sensors-temperature") == ~w[Eins Zwei Drei Vier Fünf Sechs Weitere]
    assert legend.("sensors-co2") == ~w[Zwei Weitere]
  end

  test "the gauge's name gives the value and its level" do
    assert SensorsComponents.co2_label(850) == "CO₂ 850 ppm, gut"
    assert SensorsComponents.co2_label(1200) == "CO₂ 1.200 ppm, erhöht"
    assert SensorsComponents.co2_label(1600) == "CO₂ 1.600 ppm, hoch"
  end

  test "three zones split the arc at the presenter's thresholds, a hairline apart" do
    assert attrs(gauge(1200), "path.co2-gauge-zone", "data-level") == ~w[good warn bad]

    assert attrs(gauge(1200), "path.co2-gauge-zone", "d") == [
             "M 8.0 52.0 A 44 44 0 0 1 34.4 11.7 L 37.6 19.0 A 36 36 0 0 0 16.0 52.0 Z",
             "M 34.8 8.2 A 47 47 0 0 1 69.2 8.2 L 64.1 21.3 A 33 33 0 0 0 39.9 21.3 Z",
             "M 69.6 11.7 A 44 44 0 0 1 96.0 52.0 L 88.0 52.0 A 36 36 0 0 0 66.4 19.0 Z"
           ]
  end

  test "only the zone the value falls in is current, and it is the wider band" do
    current = &attrs(gauge(&1), "path[data-current=true]", "data-level")

    assert current.(850) == ["good"]
    assert current.(1000) == ["warn"]
    assert current.(1401) == ["bad"]

    assert [good, _warn, _bad] = attrs(gauge(850), "path.co2-gauge-zone", "d")
    assert good =~ "A 47 47" and good =~ "A 33 33"
  end

  test "the gauge is drawn flat: no textures, filters or references" do
    gauge = gauge(850)

    assert attrs(gauge, "image, pattern, filter, use, defs", "id") == []
    assert gauge |> LazyHTML.query("[id]") |> Enum.count() == 0
  end

  test "the needle turns from the left end by the value's share of the scale" do
    assert needle_angle(400) == 0.0
    assert needle_angle(1000) == 67.5
    assert needle_angle(1200) == 90.0
    assert needle_angle(2000) == 180.0
  end

  test "values beyond the scale pin the needle to its ends" do
    assert needle_angle(300) == 0.0
    assert needle_angle(5000) == 180.0
    assert SensorsComponents.co2_label(5000) == "CO₂ 5.000 ppm, hoch"
  end

  test "a CO₂ meter's card names its gauge, the figure at the tile's end" do
    now = ~U[2026-05-04 12:00:00.000000Z]

    card =
      render_component(&SensorsComponents.sensor_card/1,
        sensor: %{id: "CO2", name: "Flur", type: :meter_pro_co2},
        reading: %Ziwoas.Sensors.Reading{taken_at: now, temperature: 21.0, co2: 850},
        now: now
      )
      |> LazyHTML.from_fragment()

    assert attrs(card, "#sensor-CO2 [role=img]", "aria-label") == ["CO₂ 850 ppm, gut"]
    assert card |> LazyHTML.query("#sensor-CO2 [role=img] .co2-gauge") |> Enum.count() == 1
  end

  test "a sensor's age reads in the largest whole unit and never breaks inside" do
    now = ~U[2026-05-04 12:00:00.000000Z]
    reading = &%Ziwoas.Sensors.Reading{taken_at: DateTime.add(now, -&1)}

    assert SensorsComponents.age_label(reading.(42), now) == "vor 42 s"
    assert SensorsComponents.age_label(reading.(5 * 60), now) == "vor 5 Min"
    assert SensorsComponents.age_label(reading.(3 * 3600), now) == "vor 3 h"
    assert SensorsComponents.age_label(nil, now) == "—"

    room_value = %{value: 640, source: :stand_in, taken_at: DateTime.add(now, 3)}
    assert SensorsComponents.age_label(room_value, now) == "vor\u00A00\u00A0s"
  end
end
