defmodule ZiwoasWeb.RoomAirComponentsTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Sensors.RoomReading
  alias ZiwoasWeb.Charts.RoomAir, as: RoomAirCharts
  alias ZiwoasWeb.RoomAirComponents, as: RoomAir

  defp reading(values) do
    %RoomReading{
      room: "Wohnzimmer",
      values:
        Map.new(RoomReading.quantities(), fn quantity ->
          {quantity, if(value = values[quantity], do: %{value: value, source: :lead})}
        end)
    }
  end

  test "levels read in each quantity's own words" do
    assert RoomAir.level_word(:co2, 1200) == "erhöht"
    assert RoomAir.level_word(:co2, 1500) == "hoch"
    assert RoomAir.level_word(:pm2_5, 40.0) == "hoch"
    assert RoomAir.level_word(:voc_index, 100) == "normal"
    assert RoomAir.level_word(:temperature, 17.0) == "zu kühl"
    assert RoomAir.level_word(:temperature, 27.0) == "zu warm"
    assert RoomAir.level_word(:humidity, 35.0) == "zu trocken"
    assert RoomAir.level_word(:humidity, 75.0) == "zu feucht"
    assert RoomAir.level_word(:humidity, 50.0) == "angenehm"
    assert RoomAir.level_word(:nox_index, nil) == nil
  end

  test "„Luft gut“ needs all five verdict quantities, else it names what it judged" do
    all = [:co2, :pm2_5, :pm10, :voc_index, :nox_index]

    assert RoomAir.verdict_word({:good, all}) == "Luft gut"
    assert RoomAir.verdict_word({:good, [:co2]}) == "CO₂ gut"
    assert RoomAir.verdict_word({:good, [:co2, :pm2_5, :pm10]}) == "CO₂ und Feinstaub gut"
    assert RoomAir.verdict_word({:warn, [:voc_index]}) == "Bald lüften"
    assert RoomAir.verdict_word({:bad, [:co2]}) == "Jetzt lüften"
    assert RoomAir.verdict_word(nil) == "Keine aktuellen Werte"
  end

  test "the reason names the culprits, or what the room measures but lacks right now" do
    room = %{
      quantities: RoomReading.quantities(),
      reading: reading(co2: 800, pm2_5: 5.0, pm10: 9.0)
    }

    assert RoomAir.verdict_reason({:bad, [:co2, :pm2_5, :pm10]}, room) == "CO₂ und Feinstaub hoch"
    assert RoomAir.verdict_reason({:warn, [:voc_index]}, room) == "VOC erhöht"
    assert RoomAir.verdict_reason({:good, [:co2, :pm2_5, :pm10]}, room) == "ohne VOC und NOx"
    assert RoomAir.verdict_reason({:good, [:co2, :pm2_5, :pm10]}, room, alerted: true) == nil

    starting = %{
      room
      | reading: %{room.reading | lead: %Ziwoas.Config.Sensor{type: :sen66}, lead_fresh: true}
    }

    no_dust = %{starting | reading: %{starting.reading | values: reading(co2: 800).values}}
    assert RoomAir.verdict_reason({:good, [:co2]}, no_dust) == "ohne Feinstaub, VOC und NOx"

    assert RoomAir.verdict_reason({:good, [:co2, :pm2_5, :pm10]}, starting) ==
             "VOC und NOx in der Anlaufphase"

    bedroom = %{quantities: [:co2, :temperature, :humidity], reading: reading(co2: 800)}
    assert RoomAir.verdict_reason({:good, [:co2]}, bedroom) == nil
    assert RoomAir.verdict_reason(nil, room) == nil
  end

  test "the hint joins its effects and warns when airing worsens the humidity" do
    assert RoomAir.hint_text([:cools], reading(humidity: 50.0)) == {"Lüften kühlt", :good}

    assert RoomAir.hint_text([:cools, :dries], reading(humidity: 65.0)) ==
             {"Lüften kühlt und trocknet", :good}

    assert RoomAir.hint_text([:dries], reading(humidity: 35.0)) ==
             {"Lüften trocknet weiter aus – der Raum ist schon zu trocken", :warn}

    assert RoomAir.hint_text([:cools, :humidifies], reading(humidity: 65.0)) ==
             {"Lüften kühlt, befeuchtet aber weiter – der Raum ist schon zu feucht", :warn}

    assert RoomAir.hint_text([:humidifies], reading(humidity: 35.0)) ==
             {"Lüften befeuchtet", :good}

    assert RoomAir.hint_text([:cools, :dries], reading(humidity: 35.0), short: true) ==
             {"Lüften kühlt und trocknet aus", :warn}

    assert RoomAir.hint_text([:warms], reading(humidity: 50.0)) ==
             {"Lüften wärmt – der Raum ist schon warm", :warn}

    assert RoomAir.hint_text([:warms, :humidifies], reading(humidity: 35.0)) ==
             {"Lüften befeuchtet, wärmt aber – der Raum ist schon warm", :warn}

    assert RoomAir.hint_text([:warms, :dries], reading(humidity: 35.0)) ==
             {"Lüften wärmt und trocknet weiter aus – der Raum ist schon warm und zu trocken",
              :warn}

    assert RoomAir.hint_text([:warms, :humidifies], reading(humidity: 35.0), short: true) ==
             {"Lüften befeuchtet und wärmt", :warn}

    assert RoomAir.hint_text(nil, reading(humidity: 35.0)) == nil
  end

  test "device status flags read as problem and consequence, the two CO₂ errors as one" do
    assert RoomAir.device_status_text([:fan_speed_warning]) == [
             "Lüfterdrehzahl weicht ab – Feinstaubwerte können ungenau sein"
           ]

    assert RoomAir.device_status_text([:co2_1_error, :co2_2_error]) == [
             "CO₂-Sensor gestört – CO₂ ist unsicher"
           ]
  end

  test "the balcony line adds the balcony air at room temperature while the hint dries or humidifies" do
    balcony = %Ziwoas.Sensors.Reading{temperature: 32.0, humidity: 50.0}
    room = reading(temperature: 26.7, humidity: 65.0)

    assert RoomAir.balcony_text(balcony, [:dries], room) ==
             "Balkon 32,0 °C · 50 % · bei 26,7 °C: 67 %"

    assert RoomAir.balcony_text(balcony, [:cools], room) == "Balkon 32,0 °C · 50 %"
  end

  test "rooms get anchors without umlauts" do
    assert RoomAir.anchors(["Wohnzimmer", "Gäste Bad/Süd"]) == %{
             "Wohnzimmer" => "room-wohnzimmer",
             "Gäste Bad/Süd" => "room-gaeste-bad-sued"
           }
  end

  test "rooms whose names read the same get distinct anchors, in config order" do
    assert RoomAir.anchors(["Küche", "Kueche", "A B", "A-B", "Kueche 2"]) == %{
             "Küche" => "room-kueche",
             "Kueche" => "room-kueche-2",
             "A B" => "room-a-b",
             "A-B" => "room-a-b-2",
             "Kueche 2" => "room-kueche-2-2"
           }
  end

  test "particle sizes split PM10 by what each cumulative value adds" do
    values = reading(pm1_0: 0.4, pm2_5: 0.9, pm4_0: 1.4, pm10: 1.6).values

    assert Enum.map(RoomAir.pm_bins(values), &{&1.label, Float.round(&1.value, 1), &1.share}) == [
             {"bis 1 µm", 0.4, 25},
             {"1–2,5 µm", 0.5, 31},
             {"2,5–4 µm", 0.5, 31},
             {"4–10 µm", 0.2, 13}
           ]

    assert RoomAir.pm_bins(reading(pm2_5: 0.9).values) == nil
    assert RoomAir.pm_bins(reading(pm1_0: 0.0, pm2_5: 0.0, pm4_0: 0.0, pm10: 0.0).values) == nil
  end

  test "a room gets the charts its sensors can fill" do
    assert Enum.map(RoomAirCharts.charts([:co2, :temperature, :humidity]), & &1.key) ==
             [:co2, :temperature, :humidity]

    [co2 | _] = RoomAirCharts.charts(RoomReading.quantities())

    assert co2.lines == [
             %{value: 1000, label: "1.000 Bald lüften", level: :warn},
             %{value: 1400, label: "1.400 Jetzt lüften", level: :bad}
           ]

    assert %{band: [40, 60], decimals: 0, unit: "%", from_zero: false, suggested_max: 80} =
             Enum.find(RoomAirCharts.charts([:humidity]), &(&1.key == :humidity))

    assert [%{label: "15 Bald lüften"}, %{label: "35 Jetzt lüften"}] =
             Enum.find(RoomAirCharts.charts(RoomReading.quantities()), &(&1.key == :pm)).lines
  end

  test "the SEN66's minutes average into 5-minute buckets; gaps and source changes stay apart" do
    points = [
      [0, 600, 0],
      [60_000, 610, 0],
      [240_000, 620, 0],
      [300_000, 900, 0],
      [360_000, nil, 0],
      [420_000, 21.5, 0],
      [480_000, 22.0, 0],
      [540_000, 950, 1],
      [570_000, 960, 1]
    ]

    assert RoomAirCharts.smooth(points) == [
             [0, 610, 0],
             [300_000, 900, 0],
             [360_000, nil, 0],
             [420_000, 21.75, 0],
             [540_000, 955, 1]
           ]
  end
end
