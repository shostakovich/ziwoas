defmodule Ziwoas.Trmnl.SensorPayloadTest do
  # Mirrors test/models/trmnl_sensor_payload_builder_test.rb.
  use Ziwoas.DataCase, async: true

  alias Ziwoas.{Repo, RubyJSON, TestConfigs}
  alias Ziwoas.Sensors.Reading
  alias Ziwoas.Trmnl.SensorPayload

  # 16:56 Europe/Berlin
  @now ~U[2026-05-12 14:56:00.000000Z]

  setup do
    config =
      TestConfigs.plugs("""
      sensors:
        - { id: INDOOR1, name: Wohnzimmer, type: meter_pro_co2, room: Wohnzimmer }
        - { id: INDOOR2, name: Küche, type: meter_pro_co2, room: Küche }
        - { id: OUTDOOR, name: Balkon, type: outdoor_meter }
      """)

    %{config: config}
  end

  defp reading(device_id, minutes_ago, opts) do
    Repo.insert!(%Reading{
      device_id: device_id,
      taken_at: DateTime.add(@now, -round(minutes_ago * 60), :second),
      temperature: Keyword.get(opts, :temp, 20.0),
      humidity: Keyword.get(opts, :humidity, 40),
      co2: opts[:co2],
      battery_pct: Keyword.get(opts, :battery, 80)
    })
  end

  defp payload(config),
    do:
      config
      |> SensorPayload.build(@now)
      |> Map.new()
      |> Map.fetch!("merge_variables")
      |> Map.new()

  defp sensor(config, id),
    do: payload(config)["sensors"] |> Enum.map(&Map.new/1) |> Enum.find(&(&1["id"] == id))

  test "one entry per configured sensor, in config order", %{config: config} do
    reading("INDOOR1", 4, co2: 1230, temp: 22.4, humidity: 48)
    reading("INDOOR2", 3, co2: 740, temp: 21.8, humidity: 51)
    reading("OUTDOOR", 5, temp: 12.4, humidity: 64, battery: 73)

    sensors = Enum.map(payload(config)["sensors"], &Map.new/1)
    assert Enum.map(sensors, & &1["id"]) == ~w[INDOOR1 INDOOR2 OUTDOOR]
    assert Enum.map(sensors, & &1["name"]) == ~w[Wohnzimmer Küche Balkon]
    assert Enum.map(sensors, & &1["type"]) == ~w[indoor indoor outdoor]
  end

  test "an indoor sensor shows ppm, ampel and unit", %{config: config} do
    reading("INDOOR1", 4, co2: 1230, temp: 22.4, humidity: 48)
    s = sensor(config, "INDOOR1")

    assert {s["primary"], s["unit"], s["ampel"]} == {1230, "ppm CO₂", "warn"}
    assert s["temperature"] == 22.4
    assert s["humidity"] == 48
    refute s["offline"]
  end

  test "an outdoor sensor shows °C with one decimal and no ampel", %{config: config} do
    reading("OUTDOOR", 5, temp: 12.4, humidity: 64)
    s = sensor(config, "OUTDOOR")

    assert {s["primary"], s["unit"], s["ampel"], s["humidity"]} == {12.4, "°C", nil, 64}
  end

  test "the trend has 12 buckets, oldest first, empty ones null", %{config: config} do
    reading("INDOOR1", 5, co2: 1230)
    reading("INDOOR1", 50, co2: 950)
    reading("INDOOR1", 130, co2: 700)

    trend = sensor(config, "INDOOR1")["trend"]
    assert length(trend) == 12
    assert nil in trend
    assert List.last(trend) == 1230
    assert Enum.find_index(trend, &(&1 == 1230)) > Enum.find_index(trend, &(&1 == 700))
  end

  test "trend_min and trend_max bracket the trend", %{config: config} do
    reading("INDOOR1", 5, co2: 1230)
    reading("INDOOR1", 50, co2: 950)
    s = sensor(config, "INDOOR1")

    assert {s["trend_min"], s["trend_max"]} == {950, 1230}
  end

  test "age, battery and offline", %{config: config} do
    reading("INDOOR1", 4, co2: 800, battery: 14)
    s = sensor(config, "INDOOR1")
    assert s["age_label"] == "vor 4 Min"
    assert s["battery_low"]
    assert s["battery_pct"] == 14

    reading("INDOOR2", 120, co2: 800)
    stale = sensor(config, "INDOOR2")
    assert stale["offline"]
    assert {stale["primary"], stale["trend"], stale["ampel"]} == {nil, [], nil}

    missing = sensor(config, "OUTDOOR")
    assert missing["offline"]
    assert missing["age_label"] == "—"
  end

  test "stand is the newest reading's local time, else now", %{config: config} do
    assert payload(config)["stand"] == "16:56"
    reading("INDOOR1", 4, co2: 1230)
    assert payload(config)["stand"] == "16:52"
  end

  test "the serialised payload stays under 2 kB with three full trends", %{config: config} do
    for id <- ~w[INDOOR1 INDOOR2 OUTDOOR], i <- 0..11 do
      reading(id, i * 15, co2: 800 + i, temp: 20.0 + i * 0.1)
    end

    assert byte_size(RubyJSON.encode!(SensorPayload.build(config, @now))) <= 2048
  end
end
