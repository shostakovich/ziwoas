defmodule ZiwoasWeb.SensorsLiveTest do
  use ZiwoasWeb.ConnCase

  import Bitwise
  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Config, Repo, Sensors, TestClock, TestConfigs}
  alias Ziwoas.Sensors.Reading

  @now "2026-05-04T12:00:00+02:00"

  setup do
    TestClock.freeze(@now)
    :ok
  end

  defp reading!(device_id, minutes_ago, attrs) do
    taken_at = @now |> Clock.parse!() |> DateTime.add(-minutes_ago * 60, :second)
    Repo.insert!(struct!(%Reading{device_id: device_id, taken_at: taken_at}, attrs))
  end

  defp page(conn),
    do: conn |> get(~p"/sensors") |> html_response(200) |> LazyHTML.from_document()

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp attrs(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp squish(text),
    do: text |> String.replace(["\u00A0", "\u2060"], " ") |> String.split() |> Enum.join(" ")

  defp ms(minutes_ago),
    do: Clock.parse!(@now) |> DateTime.to_unix(:millisecond) |> Kernel.-(minutes_ago * 60_000)

  defp tile(doc, room, quantity), do: texts(doc, "##{room} [data-quantity=#{quantity}]")

  # The strip renders its trailing badge twice: at the title on phones, in its column from md.
  defp verdict_badge(doc, room) do
    [level] = doc |> attrs("##{room}-strip [data-level]", "data-level") |> Enum.uniq()
    [word] = doc |> texts("##{room}-strip [data-level]") |> Enum.uniq()
    {level, word}
  end

  describe "the test config: one meter in the Wohnzimmer, the balcony without a room" do
    test "the room view shows CO₂ with its verdict, and tiles only for what the room measures",
         %{conn: conn} do
      reading!("TEST_INDOOR", 5, temperature: 21.0, humidity: 50.0, co2: 1200, battery_pct: 90)
      reading!("TEST_OUTDOOR", 5, temperature: 12.0, humidity: 70.0, battery_pct: 100)

      doc = page(conn)

      assert texts(doc, "title") == ["Sensoren"]
      assert texts(doc, "#app-shell-nav a[aria-current=page]") == ["Sensoren"]
      assert texts(doc, "#room-strip a") == ["Wohnzimmer"]
      assert attrs(doc, "#room-strip a", "href") == ["#room-wohnzimmer"]
      assert hd(texts(doc, "#room-wohnzimmer-strip")) =~ "1.200 ppm"
      assert verdict_badge(doc, "room-wohnzimmer") == {"warn", "Bald lüften"}

      assert texts(doc, "#room-wohnzimmer-name") == ["Wohnzimmer"]

      assert texts(doc, "#room-wohnzimmer-sources") == [
               "Leitsensor: Test Wohnzimmer · vor 5 Min"
             ]

      assert attrs(doc, "#room-wohnzimmer-co2-now [role=img]:has(.co2-gauge svg)", "aria-label") ==
               ["CO₂ 1.200 ppm, erhöht"]

      assert texts(doc, "#room-wohnzimmer-co2-now") == ["CO₂ 1.200 ppm erhöht"]

      assert texts(doc, "#room-wohnzimmer-verdict") == [
               "Lüftungsempfehlung Bald lüften CO₂ erhöht"
             ]

      assert count(doc, "#room-wohnzimmer-hint") == 0,
             "a room at 21 °C and 50 % has nothing to gain from the balcony"

      assert attrs(doc, "#room-wohnzimmer [data-quantity]", "data-quantity") ==
               ~w[temperature humidity]

      assert tile(doc, "room-wohnzimmer", "temperature") == ["Temperatur 21,0 °C angenehm"]

      assert attrs(doc, "#room-wohnzimmer-charts [phx-hook=RoomAirChart]", "data-chart") ==
               ~w[co2 temperature humidity]

      assert attrs(doc, "#room-wohnzimmer-charts [phx-hook=RoomAirChart]", "data-room") ==
               List.duplicate("room-wohnzimmer", 3)

      assert count(doc, "h3#room-wohnzimmer-history") == 1
      assert texts(doc, "#room-wohnzimmer-charts h4") == ["CO₂", "Temperatur", "Luftfeuchte"]

      assert texts(doc, "#other-sensors-heading") == ["Weitere Sensoren"]

      assert texts(doc, "#sensor-TEST_OUTDOOR") == [
               "Test Balkon 12,0 °C Luftfeuchte 70 % · vor 5 Min"
             ]

      assert attrs(doc, "#sensors_chart [phx-hook=SensorsChart]", "data-series") ==
               ~w[temperature humidity]

      assert texts(doc, "#sensors_chart h3") == ["Temperatur", "Luftfeuchte"]
      assert count(doc, "main [role=alert], main [role=status]") == 0
    end

    test "without rooms the sensors' charts sit right under the page heading", %{conn: conn} do
      TestConfigs.put(
        Config.from_yaml!("""
        location:
          timezone: Europe/Berlin
        plugs: []
        sensors:
          - { id: TEST_OUTDOOR, name: Test Balkon, type: outdoor_meter }
        """)
      )

      reading!("TEST_OUTDOOR", 5, temperature: 12.0, humidity: 70.0, battery_pct: 100)

      assert texts(page(conn), "#sensors_chart h2") == ["Temperatur", "Luftfeuchte"]
    end

    test "sensors with a low battery are named", %{conn: conn} do
      reading!("TEST_INDOOR", 5, temperature: 21.0, co2: 600, battery_pct: 90)
      reading!("TEST_OUTDOOR", 5, temperature: 12.0, battery_pct: 15)

      assert texts(page(conn), "#battery-warning[role=status]") == [
               "Batterie schwach Test Balkon"
             ]
    end

    test "without any reading the page says so", %{conn: conn} do
      doc = page(conn)

      assert texts(doc, "main h2") == ["Noch keine Sensordaten"]
      assert count(doc, "#room-wohnzimmer") == 0
      assert count(doc, "#sensors_chart") == 0
    end

    test "a stale meter says since when, and its quantities collapse into one line",
         %{conn: conn} do
      reading!("TEST_INDOOR", 45, temperature: 21.0, humidity: 50.0, co2: 800)

      doc = page(conn)

      assert texts(doc, "#room-wohnzimmer-sources") == [
               "Leitsensor: Test Wohnzimmer · keine Daten seit 11:15"
             ]

      assert texts(doc, "#room-wohnzimmer-lead-alert") == [
               "Test Wohnzimmer: keine Daten seit 11:15 – CO₂, Temperatur und Luftfeuchte fehlen."
             ]

      assert texts(doc, "#room-wohnzimmer-verdict") == [
               "Lüftungsempfehlung Keine aktuellen Werte"
             ]

      assert count(doc, "#room-wohnzimmer [data-quantity]") == 0

      assert texts(doc, "#room-wohnzimmer-hint") == [
               "Kein Lüftungshinweis: keine aktuellen Balkonwerte"
             ]
    end
  end

  test "without an outdoor meter the hint says nothing about the balcony", %{conn: conn} do
    TestConfigs.put(
      Config.from_yaml!("""
      location:
        timezone: Europe/Berlin
      plugs: []
      sensors:
        - { id: KRABBE, name: Krabbe, type: meter_pro_co2, room: Wohnzimmer }
      """)
    )

    reading!("KRABBE", 5, co2: 900, temperature: 21.0, humidity: 50.0)

    doc = page(conn)

    assert count(doc, "#room-wohnzimmer-hint") == 0
    refute LazyHTML.text(doc) =~ "Balkonwerte"
  end

  test "a stand-in SEN66 says what it reports as the lead does", %{conn: conn} do
    TestConfigs.put(
      Config.from_yaml!("""
      location:
        timezone: Europe/Berlin
      plugs: []
      sensors:
        - { id: SEN, name: SEN66, type: sen66, room: Wohnzimmer, port: /dev/x }
        - { id: SEN2, name: Zweiter SEN66, type: sen66, room: Wohnzimmer, port: /dev/y }
      """)
    )

    sen66!(1, device_status: 0)
    reading!("SEN2", 1, temperature: 22.0, device_status: 1 <<< 4)

    assert texts(page(conn), "#room-wohnzimmer-device-alert[role=alert]") == [
             "Zweiter SEN66 meldet: Lüfter ausgefallen – Feinstaubwerte fehlen oder sind falsch."
           ]
  end

  defp put_room_config do
    TestConfigs.put(
      Config.from_yaml!("""
      location:
        timezone: Europe/Berlin
      plugs: []
      sensors:
        - { id: KRABBE, name: Krabbe, type: meter_pro_co2, room: Wohnzimmer }
        - { id: SEN, name: SEN66, type: sen66, room: Wohnzimmer, port: /dev/x }
        - { id: ROBBE, name: Robbe, type: meter_pro_co2, room: Schlafzimmer }
        - { id: BALKON, name: Balkon, type: outdoor_meter }
      """)
    )

    reading!("KRABBE", 10, co2: 900, temperature: 25.0, humidity: 60.0, battery_pct: 80)
    reading!("ROBBE", 10, co2: 700, temperature: 19.5, humidity: 45.0, battery_pct: 90)
    reading!("BALKON", 10, temperature: 14.0, humidity: 80.0, battery_pct: 100)
  end

  defp sen66!(minutes_ago, attrs \\ []) do
    reading!(
      "SEN",
      minutes_ago,
      Keyword.merge(
        [
          co2: nil,
          pm1_0: 20.0,
          pm2_5: 38.0,
          pm4_0: 40.0,
          pm10: 44.0,
          voc_index: nil,
          nox_index: nil,
          temperature: 26.5,
          humidity: 65.0,
          device_status: 1 <<< 21,
          firmware_version: "dev (SEN66 4.0)"
        ],
        attrs
      )
    )
  end

  describe "a fresh SEN66 leading a meter, a bedroom with its own meter and the balcony" do
    setup do
      put_room_config()
      sen66!(1)
      :ok
    end

    test "each value comes from the lead sensor unless it lacks one", %{conn: conn} do
      doc = page(conn)

      assert texts(doc, "#room-wohnzimmer-sources li") == [
               "Leitsensor: SEN66 · vor 1 Min · Warnung",
               "Ersatzsensor: Krabbe · vor 10 Min"
             ]

      assert texts(doc, "#room-wohnzimmer-sources [data-level=warn]") == ["Warnung"]

      assert texts(doc, "#room-wohnzimmer-co2-now") == ["CO₂ 900 ppm gut vom Ersatzsensor"]

      assert attrs(doc, "#room-wohnzimmer [data-quantity]", "data-quantity") ==
               ~w[pm2_5 pm10 temperature humidity]

      assert tile(doc, "room-wohnzimmer", "pm2_5") == ["Feinstaub PM2,5 38,0 µg/m³ hoch"]
      assert tile(doc, "room-wohnzimmer", "temperature") == ["Temperatur 26,5 °C zu warm"]
      assert tile(doc, "room-wohnzimmer", "humidity") == ["Luftfeuchte 65 % zu feucht"]
    end

    test "the verdict names its culprits, the hint what airing would do", %{conn: conn} do
      doc = page(conn)

      assert texts(doc, "#room-wohnzimmer-verdict") == [
               "Lüftungsempfehlung Jetzt lüften Feinstaub hoch"
             ]

      assert attrs(doc, "#room-wohnzimmer-verdict", "data-level") == ["bad"]

      assert texts(doc, "#room-wohnzimmer-hint[role=status]") == [
               "Lüften kühlt und trocknet Balkon 14,0 °C · 80 % · bei 26,5 °C: 39 %"
             ]

      assert texts(doc, "#room-wohnzimmer-device-alert[role=status]") == [
               "SEN66 meldet: Lüfterdrehzahl weicht ab – Feinstaubwerte können ungenau sein."
             ]

      assert texts(doc, "#room-wohnzimmer-pm-shares li") == [
               "bis 1 µm 20,0 · 45 %",
               "1–2,5 µm 18,0 · 41 %",
               "2,5–4 µm 2,0 · 5 %",
               "4–10 µm 4,0 · 9 %"
             ]

      assert texts(doc, "#room-wohnzimmer-pm-shares > div:first-child") == ["PM10 44,0 µg/m³"]
      assert texts(doc, "#room-wohnzimmer-pm-split h4") == ["Feinstaub nach Größe"]

      assert attrs(doc, "#room-wohnzimmer-pm-shares[role=group]", "data-series") == [
               "seq-1 seq-2 seq-4 seq-5"
             ]
    end

    test "the bedroom's meter alone judges CO₂ only and shows no dust, VOC or NOx",
         %{conn: conn} do
      doc = page(conn)

      assert texts(doc, "#room-strip a") == ["Wohnzimmer", "Schlafzimmer"]
      assert hd(texts(doc, "#room-wohnzimmer-strip")) =~ "900 ppm · Lüften kühlt und trocknet"
      assert verdict_badge(doc, "room-wohnzimmer") == {"bad", "Jetzt lüften"}
      assert verdict_badge(doc, "room-schlafzimmer") == {"good", "CO₂ gut"}

      assert attrs(doc, "main section[aria-labelledby$=-name]", "id") == [
               "room-wohnzimmer",
               "room-schlafzimmer"
             ]

      assert texts(doc, "#room-schlafzimmer-name") == ["Schlafzimmer"]

      assert attrs(doc, "#room-schlafzimmer [data-quantity]", "data-quantity") ==
               ~w[temperature humidity]

      assert count(doc, "#room-schlafzimmer-pm-split") == 0
      assert texts(doc, "#room-schlafzimmer-verdict") == ["Lüftungsempfehlung CO₂ gut"]
      assert attrs(doc, "#room-schlafzimmer-verdict", "data-level") == ["good"]

      assert [co2_line] = texts(doc, "#room-schlafzimmer-co2-now")
      refute co2_line =~ "gut", "the verdict already says it"

      assert attrs(doc, "#room-schlafzimmer-charts [phx-hook]", "data-chart") ==
               ~w[co2 temperature humidity]

      assert attrs(doc, "#room-wohnzimmer-charts [phx-hook]", "data-chart") ==
               ~w[co2 pm voc_index nox_index temperature humidity]

      assert texts(doc, "#room-wohnzimmer-pm li") == [
               "PM2,5",
               "PM10",
               "Grenzen für PM2,5",
               "keine Messung"
             ]

      assert texts(doc, "#room-wohnzimmer-humidity li") == ["angenehm 40–60 %", "Ersatzsensor"]

      assert texts(doc, "#room-wohnzimmer-sensor-SEN dd") == [
               "11:59 · vor 1 Min",
               "Warnung",
               "dev (SEN66 4.0)",
               "SEN"
             ]
    end

    test "the charts get the last 24 hours on connect, each point with its source",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sensors")

      assert_push_event(view, "room_air_chart:data", %{
        room: "room-wohnzimmer",
        replace: true,
        series: %{co2: co2, pm2_5: pm2_5},
        charts: [%{key: :co2, lines: [%{value: 1000, label: "1.000 Bald lüften"}, _]} | _]
      })

      assert co2 == [[ms(24 * 60), nil, 0], [ms(10), 900, 1]]
      assert List.last(pm2_5) == [ms(1), 38.0, 0]
    end

    test "a stored reading updates the view and appends to the charts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sensors")
      assert_push_event(view, "room_air_chart:data", %{room: "room-wohnzimmer", replace: true})

      TestClock.freeze(DateTime.add(Clock.parse!(@now), 60))
      {:ok, _reading} = Sensors.create_reading("SEN", Clock.now(), %{co2: 1500, pm2_5: 4.0})

      doc = view |> render() |> LazyHTML.from_fragment()

      assert texts(doc, "#room-wohnzimmer-verdict > div") == [
               "Lüftungsempfehlung",
               "Jetzt lüften",
               "CO₂ hoch"
             ]

      assert_push_event(view, "room_air_chart:data", %{
        room: "room-wohnzimmer",
        replace: false,
        series: %{co2: co2}
      })

      assert List.last(co2) == [ms(-1), 1500, 0]
    end
  end

  test "a SEN66 a moment past its 3 minutes is stale everywhere on the page", %{conn: conn} do
    put_room_config()

    taken_at = @now |> Clock.parse!() |> DateTime.add(-180_500, :millisecond)

    Repo.insert!(%Reading{
      device_id: "SEN",
      taken_at: taken_at,
      pm2_5: 5.0,
      temperature: 22.0,
      device_status: 0
    })

    doc = page(conn)

    assert texts(doc, "#room-wohnzimmer-sources li") == [
             "Leitsensor: SEN66 · keine Daten seit 11:56",
             "Ersatzsensor: Krabbe · vor 10 Min"
           ]

    assert texts(doc, "#room-wohnzimmer-lead-alert") == [
             "SEN66: keine Daten seit 11:56 – CO₂, Temperatur und Luftfeuchte kommen vom " <>
               "Ersatzsensor, Feinstaub, VOC und NOx fehlen."
           ]
  end

  describe "appending to the charts" do
    setup do
      put_room_config()
      sen66!(0, co2: 800)
      TestClock.freeze(DateTime.add(Clock.parse!(@now), 30))
      :ok
    end

    test "a reading from the same source is averaged into its bucket as a full payload would",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sensors")

      assert_push_event(view, "room_air_chart:data", %{
        room: "room-wohnzimmer",
        replace: true,
        series: %{co2: charted}
      })

      TestClock.freeze(DateTime.add(Clock.parse!(@now), 60))
      {:ok, _reading} = Sensors.create_reading("SEN", Clock.now(), %{co2: 810})

      assert_push_event(view, "room_air_chart:data", %{
        room: "room-wohnzimmer",
        replace: false,
        from: from,
        series: %{co2: appended}
      })

      assert {from, appended} == {ms(0), [[ms(0), 805, 0]]}

      {:ok, fresh, _html} = live(conn, ~p"/sensors")

      assert_push_event(fresh, "room_air_chart:data", %{
        room: "room-wohnzimmer",
        replace: true,
        series: %{co2: replaced}
      })

      recent = fn points -> Enum.filter(points, fn [at | _] -> at >= ms(30) end) end
      merged = Enum.filter(charted, fn [at | _] -> at < from end) ++ appended

      assert recent.(merged) == recent.(replaced)
      assert recent.(replaced) == [[ms(10), 900, 1], [ms(0), 805, 0]]
    end
  end

  test "the charts are replaced every quarter hour on their own, no SwitchBot poll needed",
       %{conn: conn} do
    put_room_config()
    {:ok, view, _html} = live(conn, ~p"/sensors")
    assert_push_event(view, "room_air_chart:data", %{room: "room-wohnzimmer", replace: true})

    send(view.pid, :replace_charts)

    assert_push_event(view, "room_air_chart:data", %{room: "room-wohnzimmer", replace: true})
  end

  describe "a silent SEN66 with the meter standing in" do
    setup do
      put_room_config()
      sen66!(10, device_status: 0)
      reading!("KRABBE", 5, co2: 900, temperature: 25.0, humidity: 60.0, battery_pct: 15)
      :ok
    end

    test "says what the stand-in covers and what is missing", %{conn: conn} do
      doc = page(conn)

      assert texts(doc, "#room-wohnzimmer-lead-alert") == [
               "SEN66: keine Daten seit 11:50 – CO₂, Temperatur und Luftfeuchte kommen vom " <>
                 "Ersatzsensor, Feinstaub, VOC und NOx fehlen."
             ]

      assert texts(doc, "#room-wohnzimmer-verdict") == [
               "Lüftungsempfehlung CO₂ gut"
             ]

      assert attrs(doc, "#room-wohnzimmer [data-quantity]", "data-quantity") ==
               ~w[temperature humidity]

      assert tile(doc, "room-wohnzimmer", "humidity") == [
               "Luftfeuchte 60 % angenehm vom Ersatzsensor"
             ]

      assert texts(doc, "#room-wohnzimmer-sources [data-level=warn]") == [
               "keine Daten seit 11:50"
             ]

      assert texts(doc, "#room-wohnzimmer [id^=room-wohnzimmer-sensor-] [data-level=warn]") == [
               "keine Daten seit 11:50",
               "15 %"
             ]

      assert Enum.at(texts(doc, "#room-wohnzimmer-sensor-SEN dd"), 1) == "keine Daten seit 11:50"
    end
  end
end
