defmodule Ziwoas.SensorsTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Config, Repo, Sensors}
  alias Ziwoas.Sensors.{Reading, RoomReading}

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

  test "create_reading stores the measurements, rounding CO₂ and battery given as floats" do
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
    assert {reading.humidity, reading.co2, reading.battery_pct} == {52.7, 612, 100}
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

  describe "room air" do
    @config Config.from_yaml!("""
            location:
              timezone: Europe/Berlin
            plugs: []
            sensors:
              - { id: MTR, name: Meter, type: meter_pro_co2, room: Wohnzimmer }
              - { id: BAL, name: Balkon, type: outdoor_meter }
              - { id: SEN, name: Raumluft, type: sen66, room: Wohnzimmer, port: /dev/x }
              - { id: KCH, name: Küche, type: meter_pro_co2, room: Küche }
            """)

    defp insert!(device_id, seconds_ago, attrs) do
      taken_at = DateTime.add(@now, -seconds_ago, :second)
      Repo.insert!(struct!(%Reading{device_id: device_id, taken_at: taken_at}, attrs))
    end

    defp room(values) do
      %RoomReading{
        room: "Wohnzimmer",
        values:
          Map.new(RoomReading.quantities(), fn quantity ->
            {quantity, if(value = values[quantity], do: %{value: value})}
          end)
      }
    end

    defp outdoor(temperature, humidity),
      do: %Reading{device_id: "BAL", temperature: temperature, humidity: humidity}

    test "rooms come in config order, sensors without a room name none" do
      assert Sensors.rooms(@config) == ["Wohnzimmer", "Küche"]
    end

    test "the room on show is the first SEN66's, else the first measuring CO₂, else none" do
      sensors = fn yaml ->
        Config.from_yaml!("location:\n  timezone: Europe/Berlin\nplugs: []\nsensors:\n" <> yaml)
      end

      assert Sensors.display_room(
               sensors.("""
                 - { id: KCH, name: Küche, type: meter_pro_co2, room: Küche }
                 - { id: SEN, name: Raumluft, type: sen66, room: Wohnzimmer, port: /dev/x }
               """)
             ) == "Wohnzimmer"

      assert Sensors.display_room(
               sensors.("""
                 - { id: SEN, name: Raumluft, type: sen66, port: /dev/x }
                 - { id: BAL, name: Balkon, type: outdoor_meter, room: Balkon }
                 - { id: KCH, name: Küche, type: meter_pro_co2, room: Küche }
               """)
             ) == "Küche"

      assert Sensors.display_room(
               sensors.("  - { id: BAL, name: Balkon, type: outdoor_meter, room: Balkon }\n")
             ) == nil
    end

    test "the balcony's air at room temperature holds its water, so its humidity changes" do
      assert Float.round(Sensors.humidity_at(outdoor(32.0, 50.0), 27), 1) == 65.6
      assert Float.round(Sensors.humidity_at(outdoor(14.0, 82.0), 14), 1) == 82.0
      assert Sensors.humidity_at(outdoor(14.0, nil), 27) == nil
    end

    test "a room measures what its sensors measure between them" do
      assert Sensors.room_quantities(@config, "Wohnzimmer") == RoomReading.quantities()
      assert Sensors.room_quantities(@config, "Küche") == [:co2, :temperature, :humidity]
      assert Sensors.room_quantities(@config, "Bad") == []
    end

    test "the room reading takes each quantity from the freshest sensor in rank order" do
      insert!("MTR", 300, co2: 640, temperature: 21.0, humidity: 47.0)

      insert!("SEN", 30,
        co2: nil,
        pm2_5: 4.2,
        temperature: 22.5,
        humidity: 51.3,
        device_status: 0
      )

      insert!("SEN", 90, co2: 900, pm2_5: 9.9)

      reading = Sensors.room_reading(@config, "Wohnzimmer", @now)

      assert reading.lead.id == "SEN"
      assert reading.lead_fresh
      assert %{value: 640, source: :stand_in, sensor_id: "MTR"} = reading.values.co2
      assert %{value: 4.2, source: :lead} = reading.values.pm2_5
      assert %{value: 51.3, source: :lead} = reading.values.humidity
      assert reading.values.voc_index == nil

      assert Sensors.room_reading(@config, "Bad", @now) == nil
    end

    test "the room series reads the readings before its start and none after its end" do
      insert!("SEN", 20 * 60, co2: 700)
      insert!("SEN", 5 * 60, co2: 710)
      insert!("SEN", 60, co2: 720)
      insert!("SEN", -60, co2: 999)

      from = DateTime.add(@now, -10 * 60, :second)
      series = Sensors.room_series(@config, "Wohnzimmer", from, @now)

      assert Enum.map(series.co2, &{&1.value, &1.source}) ==
               [{nil, nil}, {710, :lead}, {nil, nil}, {720, :lead}]

      assert Sensors.room_series(@config, "Bad", from, @now).co2 == []
    end

    test "the freshest outdoor reading comes from the config's outdoor meters" do
      insert!("BAL", 29 * 60, temperature: 12.0)
      insert!("MTR", 60, temperature: 21.0)

      assert %Reading{device_id: "BAL"} = Sensors.fresh_outdoor(@config, @now)
      assert Sensors.fresh_outdoor(@config, DateTime.add(@now, 2 * 60, :second)) == nil
    end

    test "levels change at their limits" do
      for {quantity, value, level} <- [
            {:co2, 999, :good},
            {:co2, 1000, :warn},
            {:co2, 1400, :warn},
            {:co2, 1401, :bad},
            {:pm2_5, 15.0, :good},
            {:pm2_5, 15.1, :warn},
            {:pm2_5, 35.0, :warn},
            {:pm2_5, 35.1, :bad},
            {:pm10, 45.0, :good},
            {:pm10, 45.1, :warn},
            {:pm10, 100.0, :warn},
            {:pm10, 100.1, :bad},
            {:voc_index, 150, :good},
            {:voc_index, 151, :warn},
            {:voc_index, 250, :warn},
            {:voc_index, 251, :bad},
            {:nox_index, 20, :good},
            {:nox_index, 21, :warn},
            {:nox_index, 150, :warn},
            {:nox_index, 151, :bad},
            {:humidity, 29.9, :bad},
            {:humidity, 30.0, :warn},
            {:humidity, 39.9, :warn},
            {:humidity, 40.0, :good},
            {:humidity, 60.0, :good},
            {:humidity, 60.1, :warn},
            {:humidity, 70.0, :warn},
            {:humidity, 70.1, :bad},
            {:temperature, 17.9, :warn},
            {:temperature, 18.0, :good},
            {:temperature, 26.0, :good},
            {:temperature, 26.1, :warn}
          ] do
        assert Sensors.level(quantity, value) == level, "#{quantity} #{value}"
      end

      assert Sensors.level(:co2, nil) == nil
      assert Sensors.level(:pm1_0, 3.0) == nil
      assert Sensors.level_limits(:pm2_5) == [15, 35]
      assert Sensors.level_limits(:pm4_0) == nil
    end

    test "the air verdict is the worst level among CO₂, PM2.5, PM10, VOC and NOx" do
      assert Sensors.air_verdict(room(co2: 800, pm2_5: 3.0, voc_index: 100)) ==
               {:good, [:co2, :pm2_5, :voc_index]}

      assert Sensors.air_verdict(room(co2: 1200, pm2_5: 20.0, nox_index: 1)) ==
               {:warn, [:co2, :pm2_5]}

      assert Sensors.air_verdict(room(co2: 1500, pm10: 120.0, voc_index: 300)) ==
               {:bad, [:co2, :pm10, :voc_index]}

      assert Sensors.air_verdict(room(temperature: 30.0, humidity: 80.0, co2: 600)) ==
               {:good, [:co2]}

      assert Sensors.air_verdict(room(temperature: 30.0, humidity: 80.0)) == nil
      assert Sensors.air_verdict(room([])) == nil
    end

    test "airing cools only above 24 °C and with outside at least 1 K cooler" do
      assert Sensors.ventilation_hint(
               room(temperature: 24.1, humidity: 50.0),
               outdoor(23.1, 50.0)
             ) ==
               [:cools]

      assert Sensors.ventilation_hint(
               room(temperature: 24.3, humidity: 50.0),
               outdoor(23.3, 50.0)
             ) ==
               [:cools]

      assert Sensors.ventilation_hint(
               room(temperature: 24.0, humidity: 50.0),
               outdoor(15.0, 50.0)
             ) ==
               nil

      assert Sensors.ventilation_hint(
               room(temperature: 26.0, humidity: 50.0),
               outdoor(25.1, 50.0)
             ) ==
               nil
    end

    test "airing warms only above 24 °C and with outside at least 1 K warmer" do
      assert Sensors.ventilation_hint(
               room(temperature: 27.0, humidity: 48.0),
               outdoor(30.5, 40.0)
             ) ==
               [:warms]

      assert Sensors.ventilation_hint(
               room(temperature: 24.3, humidity: 50.0),
               outdoor(25.3, 45.0)
             ) ==
               [:warms]

      assert Sensors.ventilation_hint(
               room(temperature: 24.0, humidity: 50.0),
               outdoor(30.0, 40.0)
             ) ==
               nil

      assert Sensors.ventilation_hint(
               room(temperature: 26.0, humidity: 50.0),
               outdoor(26.9, 45.0)
             ) ==
               nil
    end

    test "airing dries or humidifies only a room outside 40–60 %, by absolute humidity" do
      # 21 °C / 70 % holds about 12.8 g/m³; 21 °C / 30 % about 5.5 g/m³
      assert Sensors.ventilation_hint(
               room(temperature: 21.0, humidity: 70.0),
               outdoor(10.0, 80.0)
             ) ==
               [:dries]

      assert Sensors.ventilation_hint(
               room(temperature: 21.0, humidity: 30.0),
               outdoor(18.0, 60.0)
             ) ==
               [:humidifies]

      assert Sensors.ventilation_hint(room(temperature: 21.0, humidity: 30.0), outdoor(5.0, 60.0)) ==
               [:dries]

      assert Sensors.ventilation_hint(room(temperature: 21.0, humidity: 60.0), outdoor(5.0, 60.0)) ==
               nil

      # within 0.3 g/m³ of the room's air
      assert Sensors.ventilation_hint(
               room(temperature: 21.0, humidity: 61.0),
               outdoor(21.0, 60.0)
             ) ==
               nil
    end

    test "a summer evening: airing a warm room cools it, its humidity is fine" do
      # The balcony holds less water (12.8 against 13.8 g/m³), but 55 % needs no drying.
      assert Sensors.ventilation_hint(
               room(temperature: 26.5, humidity: 55.0),
               outdoor(21.0, 70.0)
             ) ==
               [:cools]

      assert Sensors.ventilation_hint(
               room(temperature: 26.5, humidity: 62.0),
               outdoor(21.0, 70.0)
             ) ==
               [:cools, :dries]
    end

    test "no hint without an outdoor reading or what it needs" do
      assert Sensors.ventilation_hint(room(temperature: 28.0, humidity: 70.0), nil) == nil

      assert Sensors.ventilation_hint(room(temperature: 28.0, humidity: 70.0), outdoor(nil, nil)) ==
               nil

      assert Sensors.ventilation_hint(room(humidity: 70.0), outdoor(10.0, 50.0)) == nil
    end

    test "device status bits become flags" do
      assert Sensors.device_status_flags(0) == []
      assert Sensors.device_status_flags(nil) == []

      all = Enum.reduce([4, 6, 7, 9, 10, 11, 12, 21], 0, &(Bitwise.bsl(1, &1) + &2))

      assert Sensors.device_status_flags(all) == [
               :fan_error,
               :rht_error,
               :gas_error,
               :co2_2_error,
               :hcho_error,
               :pm_error,
               :co2_1_error,
               :fan_speed_warning
             ]

      assert Sensors.device_status_flags(Bitwise.bsl(1, 5) + Bitwise.bsl(1, 21)) ==
               [:fan_speed_warning]
    end
  end
end
