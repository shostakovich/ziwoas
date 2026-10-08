defmodule Ziwoas.Trmnl.SensorPayloadTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Repo, TestConfigs}
  alias Ziwoas.Sensors.Reading
  alias Ziwoas.Trmnl.{Push, SensorPayload}

  # 21:40 in Berlin; the trend's quarter hours run from 18:45 to 21:45 local.
  @now ~U[2026-05-12 19:40:00.000000Z]
  @window_start ~U[2026-05-12 16:45:00.000000Z]

  @sensors """
  sensors:
    - { id: METER, name: Wohnzimmer, type: meter_pro_co2, room: Wohnzimmer }
    - { id: SEN, name: Raumluft, type: sen66, room: Wohnzimmer, port: /dev/x }
    - { id: OUTDOOR, name: Balkon, type: outdoor_meter }
  """

  @sen66 %{
    co2: 780,
    pm1_0: 4.1,
    pm2_5: 6.24,
    pm4_0: 7.7,
    pm10: 8.46,
    voc_index: 118,
    nox_index: 2,
    temperature: 22.14,
    humidity: 50.6
  }
  @meter %{co2: 815, temperature: 22.44, humidity: 49.4, battery_pct: 80}

  setup do
    %{config: TestConfigs.plugs(@sensors)}
  end

  defp reading(device_id, seconds_ago, attrs) do
    taken_at = DateTime.add(@now, -seconds_ago, :second)
    Repo.insert!(struct!(%Reading{device_id: device_id, taken_at: taken_at}, attrs))
  end

  defp readings(device_id, from, to, every_s, attrs) do
    rows =
      for at <-
            Stream.iterate(from, &DateTime.add(&1, every_s, :second))
            |> Enum.take_while(&(DateTime.compare(&1, to) != :gt)) do
        Map.merge(attrs, %{
          device_id: device_id,
          taken_at: at,
          inserted_at: @now,
          updated_at: @now
        })
      end

    Repo.insert_all(Reading, rows)
  end

  defp json(config), do: config |> SensorPayload.build(@now) |> JSON.encode!()

  defp payload(config), do: config |> json() |> JSON.decode!() |> Map.fetch!("merge_variables")

  defp nothing,
    do: Map.new(~w[co2 pm2_5 pm10 voc nox temperature humidity], &{&1, nil})

  test "normal: the SEN66 leads, every value with its level", %{config: config} do
    readings("SEN", DateTime.add(@now, -30 - 90 * 120), DateTime.add(@now, -30), 120, @sen66)
    reading("METER", 120, @meter)
    reading("OUTDOOR", 300, temperature: 14.23, humidity: 78.4)

    assert payload(config) == %{
             "stand" => "21:40",
             "stand_at" => DateTime.to_unix(@now),
             "room" => "Wohnzimmer",
             "source" => "sen66",
             "lead" => "sen66",
             "lead_fresh" => true,
             "lead_off_since" => nil,
             "stand_in_since" => nil,
             "data_until" => "21:39",
             "trend_from" => "18:45",
             "trend_to" => "21:45",
             "verdict" => "good",
             "verdict_because" => ~w[co2 pm2_5 pm10 voc nox],
             "values" => %{
               "co2" => 780,
               "pm2_5" => 6.2,
               "pm10" => 8.5,
               "voc" => 118,
               "nox" => 2,
               "temperature" => 22.1,
               "humidity" => 51
             },
             "levels" => Map.new(Map.keys(nothing()), &{&1, "good"}),
             "stand_in" => [],
             "co2_trend" => List.duplicate(780, 12),
             "co2_trend_stand_in" => [],
             "balcony" => %{"temperature" => 14.2, "humidity" => 78, "humidity_indoors" => 49},
             "hint" => nil
           }
  end

  test "stand-in: the SEN66 is stale, the SwitchBot serves CO₂, temperature and humidity", %{
    config: config
  } do
    reading("SEN", 20 * 60, @sen66)
    reading("METER", 3 * 60, @meter)

    payload = payload(config)

    assert Map.take(
             payload,
             ~w[source lead lead_fresh lead_off_since stand_in_since data_until stand_in]
           ) == %{
             "source" => "switchbot",
             "lead" => "sen66",
             "lead_fresh" => false,
             "lead_off_since" => "21:20",
             "stand_in_since" => "21:37",
             "data_until" => "21:37",
             "stand_in" => ~w[co2 temperature humidity]
           }

    assert {payload["verdict"], payload["verdict_because"]} == {"good", ["co2"]}

    assert payload["values"] ==
             %{nothing() | "co2" => 815, "temperature" => 22.4, "humidity" => 49}

    assert payload["levels"] ==
             %{nothing() | "co2" => "good", "temperature" => "good", "humidity" => "good"}

    assert payload["balcony"] == nil
    assert payload["hint"] == nil
  end

  test "nothing fresh: no values, but when each sensor was last heard", %{config: config} do
    reading("SEN", 28 * 60, @sen66)
    reading("METER", 40 * 60, @meter)
    reading("OUTDOOR", 45 * 60, temperature: 14.0, humidity: 70.0)

    payload = payload(config)

    assert Map.take(payload, ~w[source lead_off_since stand_in_since data_until]) == %{
             "source" => nil,
             "lead_off_since" => "21:12",
             "stand_in_since" => "21:00",
             "data_until" => "21:12"
           }

    assert {payload["verdict"], payload["verdict_because"]} == {nil, []}
    assert payload["values"] == nothing()
    assert payload["levels"] == nothing()
    assert {payload["stand_in"], payload["balcony"], payload["hint"]} == {[], nil, nil}
    assert {payload["stand"], payload["room"]} == {"21:40", "Wohnzimmer"}
  end

  test "start-up: VOC and NOx are null while the SEN66 is fresh", %{config: config} do
    reading("SEN", 30, %{@sen66 | voc_index: nil, nox_index: nil})
    reading("METER", 60, @meter)

    payload = payload(config)

    assert {payload["values"]["voc"], payload["values"]["nox"]} == {nil, nil}
    assert {payload["levels"]["voc"], payload["levels"]["nox"]} == {nil, nil}
    assert payload["verdict_because"] == ~w[co2 pm2_5 pm10]

    assert {payload["source"], payload["lead_fresh"], payload["lead_off_since"],
            payload["stand_in_since"]} == {"sen66", true, nil, nil}

    assert payload["stand_in"] == []
  end

  test "the SwitchBot's time comes along whenever it serves a quantity", %{config: config} do
    reading("SEN", 30, %{@sen66 | co2: nil})
    reading("METER", 60, @meter)

    payload = payload(config)

    assert {payload["source"], payload["stand_in"]} == {"switchbot", ["co2"]}
    assert {payload["lead_off_since"], payload["stand_in_since"]} == {nil, "21:39"}
  end

  test "a SEN66 that never reported is not fresh, and has no time to tell", %{config: config} do
    reading("METER", 60, @meter)

    payload = payload(config)

    assert Map.take(
             payload,
             ~w[source lead lead_fresh lead_off_since stand_in_since data_until stand_in]
           ) == %{
             "source" => "switchbot",
             "lead" => "sen66",
             "lead_fresh" => false,
             "lead_off_since" => nil,
             "stand_in_since" => "21:39",
             "data_until" => "21:39",
             "stand_in" => ~w[co2 temperature humidity]
           }
  end

  test "the source is the SEN66 while CO₂ is unknown but its other values are fresh" do
    config =
      TestConfigs.plugs("""
      sensors:
        - { id: SEN, name: Raumluft, type: sen66, room: Wohnzimmer, port: /dev/x }
      """)

    reading("SEN", 30, %{@sen66 | co2: nil})

    payload = payload(config)

    assert {payload["source"], payload["values"]["co2"], payload["values"]["pm2_5"]} ==
             {"sen66", nil, 6.2}
  end

  test "a time older than 20 hours comes as the day, as on the page", %{config: config} do
    reading("SEN", 26 * 3600, @sen66)
    reading("METER", 60, @meter)

    assert {payload(config)["lead_off_since"], payload(config)["stand_in_since"]} ==
             {"11.05.", "21:39"}
  end

  test "the times follow the stand-in that serves the values, not the first in rank" do
    config =
      TestConfigs.plugs("""
      sensors:
        - { id: SEN, name: Raumluft, type: sen66, room: Wohnzimmer, port: /dev/x }
        - { id: OLD, name: Alt, type: meter_pro_co2, room: Wohnzimmer }
        - { id: NEW, name: Neu, type: meter_pro_co2, room: Wohnzimmer }
      """)

    reading("SEN", 600, @sen66)
    reading("OLD", 3600, @meter)
    reading("NEW", 120, @meter)

    payload = payload(config)

    assert {payload["source"], payload["stand_in"]} ==
             {"switchbot", ["co2", "temperature", "humidity"]}

    assert {payload["stand_in_since"], payload["data_until"]} == {"21:38", "21:38"}
  end

  describe "a room with a Meter Pro alone" do
    setup do
      config =
        TestConfigs.plugs("""
        sensors:
          - { id: METER, name: Wohnzimmer, type: meter_pro_co2, room: Wohnzimmer }
        """)

      %{config: config}
    end

    test "the meter leads while fresh, and nothing stands in", %{config: config} do
      reading("METER", 60, @meter)

      assert Map.take(
               payload(config),
               ~w[source lead lead_fresh lead_off_since stand_in_since data_until stand_in]
             ) == %{
               "source" => "switchbot",
               "lead" => "switchbot",
               "lead_fresh" => true,
               "lead_off_since" => nil,
               "stand_in_since" => nil,
               "data_until" => "21:39",
               "stand_in" => []
             }
    end

    test "a silent meter is the lead off since its last reading", %{config: config} do
      reading("METER", 40 * 60, @meter)

      assert Map.take(
               payload(config),
               ~w[source lead lead_fresh lead_off_since stand_in_since data_until]
             ) == %{
               "source" => nil,
               "lead" => "switchbot",
               "lead_fresh" => false,
               "lead_off_since" => "21:00",
               "stand_in_since" => nil,
               "data_until" => "21:00"
             }
    end
  end

  test "the trend's axis names its quarter hours' bounds, across a DST change" do
    config = TestConfigs.plugs(@sensors)
    # 04:10 CEST on the night the clocks went forward; three hours back is 00:15 CET.
    payload =
      config
      |> SensorPayload.build(~U[2026-03-29 02:10:00Z])
      |> JSON.encode!()
      |> JSON.decode!()
      |> Map.fetch!("merge_variables")

    assert {payload["stand"], payload["trend_from"], payload["trend_to"]} ==
             {"04:10", "00:15", "04:15"}
  end

  test "summer: airing cools and dries, the balcony air shown at room temperature", %{
    config: config
  } do
    reading("SEN", 30, %{@sen66 | temperature: 26.5, humidity: 62.0})
    reading("OUTDOOR", 300, temperature: 21.0, humidity: 70.0)

    payload = payload(config)

    assert payload["hint"] == ["cools", "dries"]

    assert payload["balcony"] == %{
             "temperature" => 21.0,
             "humidity" => 70,
             "humidity_indoors" => 51
           }

    assert {payload["levels"]["temperature"], payload["levels"]["humidity"]} ==
             {"warn", "warn"}
  end

  test "summer heat: airing a warm room warms it", %{config: config} do
    reading("SEN", 30, %{@sen66 | temperature: 27.0, humidity: 48.0})
    reading("OUTDOOR", 300, temperature: 30.5, humidity: 40.0)

    assert payload(config)["hint"] == ["warms"]
  end

  test "the balcony's humidity indoors is null without a room temperature", %{config: config} do
    reading("SEN", 30, %{@sen66 | temperature: nil})
    reading("OUTDOOR", 300, temperature: 21.0, humidity: 70.0)

    assert payload(config)["balcony"] ==
             %{"temperature" => 21.0, "humidity" => 70, "humidity_indoors" => nil}
  end

  describe "co2_trend" do
    test "time-weighted quarter-hour means; the stand-in's quarter hours are those it served mostly",
         %{config: config} do
      readings("SEN", DateTime.add(@window_start, -300), ~U[2026-05-12 19:00:00Z], 120, @sen66)

      readings("METER", @window_start, DateTime.add(@now, -60), 300, %{@meter | co2: 900})

      payload = payload(config)

      # 19:00–19:03:01 the SEN66's 780, then the SwitchBot's 900
      assert payload["co2_trend"] == List.duplicate(780, 9) ++ [876, 900, 900]
      assert payload["co2_trend_stand_in"] == [9, 10, 11]
    end

    test "quarter hours without a value are null", %{config: config} do
      reading("SEN", 2 * 3600 + 20 * 60, %{@sen66 | co2: 1000})
      reading("SEN", 60, %{@sen66 | co2: 600})

      payload = payload(config)

      assert payload["co2_trend"] ==
               [nil, nil, 1000, nil, nil, nil, nil, nil, nil, nil, nil, 600]

      assert payload["co2_trend_stand_in"] == []
    end
  end

  describe "the room" do
    test "is the first SEN66's, even when another room comes first" do
      config =
        TestConfigs.plugs("""
        sensors:
          - { id: KITCHEN, name: Küche, type: meter_pro_co2, room: Küche }
          - { id: SEN, name: Raumluft, type: sen66, room: Wohnzimmer, port: /dev/x }
        """)

      assert payload(config)["room"] == "Wohnzimmer"
    end

    test "is the first room measuring CO₂ without a SEN66 in a room" do
      config =
        TestConfigs.plugs("""
        sensors:
          - { id: SEN, name: Raumluft, type: sen66, port: /dev/x }
          - { id: OUTDOOR, name: Balkon, type: outdoor_meter, room: Balkon }
          - { id: KITCHEN, name: Küche, type: meter_pro_co2, room: Küche }
        """)

      reading("KITCHEN", 60, @meter)

      payload = payload(config)
      assert {payload["room"], payload["source"]} == {"Küche", "switchbot"}
      assert payload["values"]["co2"] == 815
    end

    test "is null without a room measuring CO₂, and so is every value" do
      config =
        TestConfigs.plugs("""
        sensors:
          - { id: OUTDOOR, name: Balkon, type: outdoor_meter }
        """)

      reading("OUTDOOR", 60, temperature: 9.04, humidity: 81.0)

      payload = payload(config)

      assert Map.drop(payload, ~w[stand stand_at]) == %{
               "room" => nil,
               "source" => nil,
               "lead" => nil,
               "lead_fresh" => false,
               "lead_off_since" => nil,
               "stand_in_since" => nil,
               "data_until" => nil,
               "trend_from" => "18:45",
               "trend_to" => "21:45",
               "verdict" => nil,
               "verdict_because" => [],
               "values" => nothing(),
               "levels" => nothing(),
               "stand_in" => [],
               "co2_trend" => List.duplicate(nil, 12),
               "co2_trend_stand_in" => [],
               "balcony" => %{"temperature" => 9.0, "humidity" => 81, "humidity_indoors" => nil},
               "hint" => nil
             }
    end
  end

  test "a full payload with a long room name stays under 2 kB" do
    room = "Schlafzimmer im Dachgeschoss Nord"

    config =
      TestConfigs.plugs("""
      sensors:
        - { id: SEN, name: Raumluft, type: sen66, room: #{room}, port: /dev/x }
        - { id: METER, name: Meter, type: meter_pro_co2, room: #{room} }
        - { id: OUTDOOR, name: Balkon, type: outdoor_meter }
      """)

    worst = %{
      co2: 1999,
      pm1_0: 999.9,
      pm2_5: 999.9,
      pm4_0: 999.9,
      pm10: 999.9,
      voc_index: 500,
      nox_index: 500,
      temperature: 26.55,
      humidity: 99.9
    }

    readings("METER", DateTime.add(@window_start, -300), @now, 60, %{@meter | co2: 1888})
    reading("SEN", 90, worst)
    reading("SEN", 30, worst)
    reading("OUTDOOR", 60, temperature: -12.34, humidity: 100.0)

    payload = payload(config)
    assert payload["room"] == room
    assert payload["verdict_because"] == ~w[co2 pm2_5 pm10 voc nox]
    assert payload["co2_trend_stand_in"] == Enum.to_list(0..11)
    assert payload["hint"] == ["cools", "dries"]
    assert byte_size(json(config)) <= Push.max_payload_bytes()
  end
end
