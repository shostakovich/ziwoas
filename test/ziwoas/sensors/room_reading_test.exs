defmodule Ziwoas.Sensors.RoomReadingTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Config.Sensor
  alias Ziwoas.Sensors.{Reading, RoomReading}

  @now ~U[2026-10-08 12:00:00.000000Z]

  @sen66 %Sensor{id: "SEN", name: "Raumluft", type: :sen66, room: "Wohnzimmer", port: "/dev/x"}
  @meter %Sensor{id: "MTR", name: "Meter", type: :meter_pro_co2, room: "Wohnzimmer"}
  @kitchen %Sensor{id: "KCH", name: "Küche", type: :meter_pro_co2, room: "Küche"}
  @balcony %Sensor{id: "BAL", name: "Balkon", type: :outdoor_meter}

  defp at(seconds_ago), do: DateTime.add(@now, -seconds_ago, :second)

  defp sen66(seconds_ago, attrs \\ []) do
    struct!(
      %Reading{
        device_id: "SEN",
        taken_at: at(seconds_ago),
        co2: 800,
        pm1_0: 1.0,
        pm2_5: 2.0,
        pm4_0: 3.0,
        pm10: 4.0,
        voc_index: 100,
        nox_index: 1,
        temperature: 22.0,
        humidity: 50.0,
        device_status: 0
      },
      attrs
    )
  end

  defp meter(seconds_ago, attrs \\ []) do
    struct!(
      %Reading{
        device_id: "MTR",
        taken_at: at(seconds_ago),
        co2: 650,
        temperature: 21.0,
        humidity: 48.0
      },
      attrs
    )
  end

  defp select(readings, now \\ @now) do
    newest = Map.new(readings, &{&1.device_id, &1})
    RoomReading.select("Wohnzimmer", [@sen66, @meter], newest, now)
  end

  test "the room's sensors are ranked SEN66 first, whatever the config order" do
    sensors = [@meter, @kitchen, @balcony, @sen66]

    assert RoomReading.ranked(sensors, "Wohnzimmer") == [@sen66, @meter]
    assert RoomReading.ranked(sensors, "Küche") == [@kitchen]
    assert RoomReading.ranked(sensors, "Bad") == []
  end

  test "a fresh SEN66 gives every quantity, the Meter Pro none" do
    reading = select([sen66(60), meter(60)])

    assert reading.lead == @sen66
    assert reading.stand_ins == [@meter]
    assert reading.lead_fresh

    assert reading.values.co2 == %{
             value: 800,
             source: :lead,
             sensor_id: "SEN",
             taken_at: at(60)
           }

    assert Enum.all?(RoomReading.quantities(), &(reading.values[&1].source == :lead))
  end

  test "a quantity the SEN66's newest reading lacks comes from the stand-in" do
    reading = select([sen66(60, co2: nil, humidity: nil), meter(600)])

    assert %{value: 650, source: :stand_in, sensor_id: "MTR"} = reading.values.co2
    assert %{value: 48.0, source: :stand_in} = reading.values.humidity
    assert %{value: 22.0, source: :lead} = reading.values.temperature
    assert reading.values.pm2_5.source == :lead
  end

  test "the SEN66 counts for 3 minutes, then the stand-in fills in what it measures" do
    assert select([sen66(180), meter(60)]).values.co2.source == :lead

    stale = select([sen66(181), meter(60)])
    assert %{value: 650, source: :stand_in} = stale.values.co2
    assert stale.values.pm2_5 == nil
    refute stale.lead_fresh
  end

  test "the stand-in counts for 30 minutes, then the quantity is unknown" do
    assert select([sen66(600), meter(1800)]).values.co2.source == :stand_in

    reading = select([sen66(600), meter(1801)])
    assert Enum.all?(RoomReading.quantities(), &is_nil(reading.values[&1]))
  end

  test "without any reading the room knows nothing, and its lead is not fresh" do
    reading = select([])

    refute reading.lead_fresh
    assert reading.device_status == []
    assert Enum.all?(RoomReading.quantities(), &is_nil(reading.values[&1]))
  end

  test "one freshness rule, to the microsecond" do
    assert RoomReading.fresh?(@sen66, sen66(180), @now)

    refute RoomReading.fresh?(
             @sen66,
             %{sen66(180) | taken_at: at(180) |> DateTime.add(-1, :microsecond)},
             @now
           )

    assert RoomReading.fresh?(@meter, meter(1800), @now)
    refute RoomReading.fresh?(@meter, meter(1801), @now)
    refute RoomReading.fresh?(@sen66, nil, @now)

    assert select([sen66(180)]).lead_fresh
    refute select([sen66(181)]).lead_fresh
    refute select([]).lead_fresh
  end

  test "a stale lead reports no device status: its last word may be days old" do
    status = Bitwise.bsl(1, 4)

    assert select([sen66(180, device_status: status)]).device_status == [:fan_error]
    assert select([sen66(181, device_status: status), meter(60)]).device_status == []
  end

  test "the lead's device status is decoded" do
    status = Bitwise.bsl(1, 11) + Bitwise.bsl(1, 21)

    assert select([sen66(30, device_status: status)]).device_status ==
             [:pm_error, :fan_speed_warning]
  end

  test "a Meter Pro leads a room without a SEN66 and counts for 30 minutes" do
    reading =
      RoomReading.select("Küche", [@kitchen], %{"KCH" => meter(1800, device_id: "KCH")}, @now)

    assert %{value: 650, source: :lead, sensor_id: "KCH"} = reading.values.co2
  end

  describe "series" do
    defp series(readings, from, to), do: RoomReading.series([@sen66, @meter], readings, from, to)

    defp compact(points),
      do: Enum.map(points, &{DateTime.diff(&1.at, @now), &1.value, &1.source})

    test "a running SEN66 gives one point per reading" do
      readings = [sen66(180, co2: 700), sen66(120, co2: 710), sen66(60, co2: 720)]

      assert compact(series(readings, at(150), @now).co2) == [
               {-150, 700, :lead},
               {-120, 710, :lead},
               {-60, 720, :lead}
             ]
    end

    test "the stand-in fills in while the SEN66 is stale, and a gap opens when both are" do
      readings = [
        meter(1500, co2: 600),
        sen66(1200, co2: 800),
        meter(600, co2: 610),
        sen66(240, co2: 820)
      ]

      assert compact(series(readings, at(1300), @now).co2) == [
               # the meter's reading from before the series started
               {-1300, 600, :stand_in},
               {-1200, 800, :lead},
               # the SEN66 went stale 181 s after its reading
               {-1019, 600, :stand_in},
               {-600, 610, :stand_in},
               {-240, 820, :lead},
               {-59, 610, :stand_in}
             ]

      # the meter's last reading goes stale 1801 s after it was taken
      later = series(readings, at(1300), DateTime.add(@now, 1300, :second)).co2
      assert compact(later) |> Enum.take(-2) == [{-59, 610, :stand_in}, {1201, nil, nil}]
    end

    test "a quantity the lead lacks is the stand-in's, a repeated reading adds no point" do
      readings = [
        meter(300, humidity: 47.0),
        sen66(180, humidity: nil),
        sen66(120, humidity: nil),
        sen66(60, humidity: 51.0)
      ]

      assert compact(series(readings, at(200), @now).humidity) == [
               {-200, 47.0, :stand_in},
               {-60, 51.0, :lead}
             ]
    end

    test "without readings a quantity is one gap" do
      assert compact(series([], at(600), @now).co2) == [{-600, nil, nil}]
    end
  end
end
