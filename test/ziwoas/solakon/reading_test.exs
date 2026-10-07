defmodule Ziwoas.Solakon.ReadingTest do
  # Mirrors the read side of test/models/solakon/reading_test.rb and
  # snapshot_test.rb, and the status decoder of test/lib/solakon/client_test.rb.
  use Ziwoas.DataCase, async: true

  alias Ziwoas.{Repo, Solakon}
  alias Ziwoas.Solakon.{Reading, Snapshot}

  @now ~U[2026-06-20 10:00:00.000000Z]

  defp reading(attrs),
    do:
      struct!(
        %Reading{
          active_power_w: 120.0,
          pv_power_w: 200.0,
          battery_power_w: 0.0,
          battery_soc_pct: 50
        },
        attrs
      )

  test "battery_state ranks fault, heat, cold, a low charge, then the flow" do
    assert Reading.battery_state(reading(battery_power_w: 40.0, battery_soc_pct: 18)) == "low"
    assert Reading.battery_state(reading(battery_power_w: 40.0)) == "charging"
    assert Reading.battery_state(reading(battery_power_w: -40.0)) == "discharging"
    assert Reading.battery_state(reading(battery_power_w: 10.0)) == "normal"
    assert Reading.battery_state(reading(battery_power_w: -10.0)) == "normal"

    assert Reading.battery_state(reading(battery_temperature_c: 45.0, battery_soc_pct: 5)) ==
             "hot"

    assert Reading.battery_state(reading(battery_temperature_c: 5.0, battery_soc_pct: 5)) ==
             "cold"

    assert Reading.battery_state(reading(battery_temperature_c: 44.9)) == "normal"
    assert Reading.battery_state(reading(alarm3: 2, battery_temperature_c: 50.0)) == "fault"
  end

  test "battery_display_power_w is positive while charging and negative while discharging" do
    assert Reading.battery_display_power_w(reading(battery_power_w: 50.0)) === 50.0
    assert Reading.battery_display_power_w(reading(battery_power_w: -50.0)) === -50.0
  end

  test "latest_fresh returns the newest reading inside the stale threshold" do
    for {seconds_ago, soc} <- [{300, 80}, {10, 81}] do
      Repo.insert!(%{reading(battery_soc_pct: soc) | taken_at: DateTime.add(@now, -seconds_ago)})
    end

    assert %Reading{battery_soc_pct: 81} = Reading.latest_fresh(@now, 120)
    assert Reading.latest_fresh(DateTime.add(@now, 180), 120) == nil
    assert %Reading{battery_soc_pct: 81} = Reading.newest()
  end

  test "status_messages are user-facing" do
    messages =
      Reading.status_messages(
        reading(status1: 0b0100, status3: 0, alarm1: 0, alarm2: 0b1000, alarm3: 0)
      )

    assert "Wechselrichter in Betrieb" in messages
    assert "Temperatur zu hoch" in messages
    refute Enum.any?(messages, &(&1 =~ ~r/SOH|EPS|390|Alarm 2|Bit/))
  end

  test "a snapshot's status adds the battery management's faults" do
    snapshot = %Snapshot{
      status1: 4,
      status3: 0,
      alarm1: 0,
      alarm2: 8,
      alarm3: 0,
      bms_faults: [0, 0, 0]
    }

    assert Snapshot.status_messages(snapshot) == [
             "Wechselrichter in Betrieb",
             "Temperatur zu hoch"
           ]

    assert Snapshot.status_messages(%{snapshot | bms_faults: [0, 3]}) ==
             ["Wechselrichter in Betrieb", "Temperatur zu hoch", "Batterie-Warnung"]
  end

  test "the decoder reads every status and alarm bit, and is quiet without one" do
    registers = %{
      status1: 0b0100_0101,
      status3: 1,
      alarm1: 0b1100_1011_0000_0111,
      alarm2: 0b0100_0110_0000_1111,
      alarm3: 0b110_0001_1000
    }

    assert Solakon.status_messages(registers, []) == [
             "Wechselrichter bereit",
             "Wechselrichter in Betrieb",
             "Wechselrichter meldet Fehler",
             "Inselbetrieb aktiv",
             "PV-Spannung zu hoch",
             "DC-Lichtbogenfehler",
             "PV-String verpolt",
             "Netzausfall",
             "Netzspannung auffällig",
             "Netzfrequenz auffällig",
             "Ausgangsstrom zu hoch",
             "DC-Anteil im Ausgangsstrom zu groß",
             "Fehlerstrom auffällig",
             "Erdung auffällig",
             "Isolationswiderstand zu niedrig",
             "Temperatur zu hoch",
             "Energiespeicher auffällig",
             "Inselbetrieb erkannt",
             "Außensteckdose überlastet",
             "Lüfter auffällig",
             "Energiespeicher verpolt",
             "Zählerverbindung verloren",
             "Batteriemanagement nicht erreichbar"
           ]

    nothing = %{status1: nil, status3: nil, alarm1: nil, alarm2: nil, alarm3: nil}
    assert Solakon.status_messages(nothing, []) == ["Alles ruhig"]
  end

  test "a snapshot's panels: every one, unwired ones at zero; PV power is their sum" do
    snapshot = %Snapshot{
      pv1_power_w: 100.0,
      pv1_voltage_v: 40.5,
      pv1_current_a: 2.47,
      pv2_power_w: 50.0
    }

    assert [
             %{label: "Panel 1", power_w: 100.0, voltage_v: 40.5, current_a: 2.47},
             %{label: "Panel 2", power_w: 50.0, voltage_v: +0.0, current_a: +0.0},
             %{label: "Panel 3", power_w: +0.0},
             %{label: "Panel 4", power_w: +0.0}
           ] = Snapshot.panels(snapshot)

    assert Snapshot.pv_power_w(snapshot) === 150.0
  end
end
