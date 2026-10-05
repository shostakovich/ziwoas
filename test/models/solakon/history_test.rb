require "test_helper"

class SolakonHistoryTest < ActiveSupport::TestCase
  cover "Solakon::History#chart_payload"
  cover "Solakon::History#epoch_ms"
  cover "Solakon::History#empty_payload"
  cover "Solakon::History#balance_rows"
  cover "Solakon::History#payload"
  cover "Solakon::Snapshot#pv_power_w"

  setup { Solakon::Snapshot.delete_all }

  test "payload builds signed chart series and balance rows from snapshots" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      # 40 + 10 Wh each way: the middle interval straddles zero and splits into two triangles.
      Solakon::Snapshot.create!(
        taken_at: 6.minutes.ago,
        pv1_power_w: 100, pv2_power_w: 50, pv3_power_w: 30, pv4_power_w: 20,
        battery_power_w: 20, active_power_w: 1200,
        pv_total_kwh: 10.0, battery_charge_total_kwh: 5.0, battery_discharge_total_kwh: 3.0
      )
      Solakon::Snapshot.create!(
        taken_at: 4.minutes.ago,
        pv1_power_w: 150, pv2_power_w: 75, pv3_power_w: 45, pv4_power_w: 30,
        battery_power_w: -40, active_power_w: 1200,
        pv_total_kwh: 10.4, battery_charge_total_kwh: 5.1, battery_discharge_total_kwh: 3.1
      )
      Solakon::Snapshot.create!(
        taken_at: 2.minutes.ago,
        pv1_power_w: 100, pv2_power_w: 50, pv3_power_w: 30, pv4_power_w: 20,
        battery_power_w: 30, active_power_w: -1200,
        pv_total_kwh: 10.8, battery_charge_total_kwh: 5.2, battery_discharge_total_kwh: 3.2
      )
      Solakon::Snapshot.create!(
        taken_at: Time.current,
        pv1_power_w: 120, pv2_power_w: 80, pv3_power_w: 40, pv4_power_w: 10,
        battery_power_w: -10, active_power_w: -1200,
        pv_total_kwh: 11.2, battery_charge_total_kwh: 5.4, battery_discharge_total_kwh: 3.3
      )

      payload = Solakon::History.new(range_key: "24h", now: Time.current).payload

      assert_equal "24h", payload.fetch(:range)
      assert_equal [ "PV", "Akku", "Außensteckdose", "0 W" ], payload.dig(:chart, :datasets).map { |dataset| dataset.fetch(:label) }
      assert_equal [ 200.0, 300.0, 200.0, 250.0 ], payload.dig(:chart, :datasets).first.fetch(:data)
      assert_equal [ 20.0, -40.0, 30.0, -10.0 ], payload.dig(:chart, :datasets)[1].fetch(:data)
      assert_equal [ 1200.0, 1200.0, -1200.0, -1200.0 ], payload.dig(:chart, :datasets)[2].fetch(:data)
      assert_equal [ 0, 0, 0, 0 ], payload.dig(:chart, :datasets)[3].fetch(:data)

      rows = payload.fetch(:balance_rows)
      assert_equal [ "PV-Erzeugung", "Akku geladen", "Akku entladen", "Ins Hausnetz geliefert", "Aus Hausnetz gezogen" ], rows.map { |row| row.fetch(:label) }
      assert_equal [ "solar", "battery", "battery", "grid", "grid" ], rows.map { |row| row.fetch(:role) }
      assert_equal "1,20 kWh", rows[0].fetch(:value)
      assert_equal "0,40 kWh", rows[1].fetch(:value)
      assert_equal "0,30 kWh", rows[2].fetch(:value)
      assert_equal "0,05 kWh", rows[3].fetch(:value)
      assert_equal "0,05 kWh", rows[4].fetch(:value)
      assert_equal [ 100.0, 33.3, 25.0, 4.2, 4.2 ], rows.map { |row| row.fetch(:share) }
      assert_equal "0 W", payload.fetch(:outlet_average)
      assert_nil payload.fetch(:message)
    end
  end

  test "the mean outlet power is a plain figure with its direction in words" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      { 1200 => "liefert 1.200 W", -40.4 => "zieht 40 W", 0.4 => "0 W", -0.4 => "0 W" }.each do |watts, expected|
        Solakon::Snapshot.delete_all
        Solakon::Snapshot.create!(taken_at: 2.minutes.ago, active_power_w: watts)
        Solakon::Snapshot.create!(taken_at: Time.current, active_power_w: watts)

        assert_equal expected, Solakon::History.new(range_key: "24h", now: Time.current).payload.fetch(:outlet_average), "at #{watts} W"
      end
    end
  end

  test "the outlet's mean power takes no share of the energy bars" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      Solakon::Snapshot.create!(taken_at: 2.minutes.ago, active_power_w: 3000, pv_total_kwh: 1.0)
      Solakon::Snapshot.create!(taken_at: Time.current, active_power_w: 3000, pv_total_kwh: 1.5)

      rows = Solakon::History.new(range_key: "24h", now: Time.current).payload.fetch(:balance_rows)

      # 0,5 kWh PV and 0,1 kWh delivered: the 3 kW mean would set the scale if it counted.
      assert_equal [ 100.0, 0.0, 0.0, 20.0, 0.0 ], rows.map { |row| row.fetch(:share) }
    end
  end

  test "whichever outlet direction moved the most energy sets the bars' scale" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      { 3000 => [ 0.0, 0.0, 0.0, 100.0, 0.0 ], -3000 => [ 0.0, 0.0, 0.0, 0.0, 100.0 ] }.each do |watts, shares|
        Solakon::Snapshot.delete_all
        Solakon::Snapshot.create!(taken_at: 2.minutes.ago, active_power_w: watts, pv_total_kwh: 1.0)
        Solakon::Snapshot.create!(taken_at: Time.current, active_power_w: watts, pv_total_kwh: 1.05)

        rows = Solakon::History.new(range_key: "24h", now: Time.current).payload.fetch(:balance_rows)

        assert_equal [ 50.0 ] + shares.drop(1), rows.map { |row| row.fetch(:share) }, "at #{watts} W"
      end
    end
  end

  test "a range without energy draws empty bars" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      Solakon::Snapshot.create!(taken_at: 2.minutes.ago, pv_total_kwh: 1.0)
      Solakon::Snapshot.create!(taken_at: Time.current, pv_total_kwh: 1.0)

      rows = Solakon::History.new(range_key: "24h", now: Time.current).payload.fetch(:balance_rows)

      assert_equal [ 0.0 ] * 5, rows.map { |row| row.fetch(:share) }
    end
  end

  test "the battery can set the bars' scale too" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      Solakon::Snapshot.create!(taken_at: 2.minutes.ago, pv_total_kwh: 1.0, battery_charge_total_kwh: 5.0)
      Solakon::Snapshot.create!(taken_at: Time.current, pv_total_kwh: 1.1, battery_charge_total_kwh: 5.4)

      rows = Solakon::History.new(range_key: "24h", now: Time.current).payload.fetch(:balance_rows)

      assert_equal [ 25.0, 100.0, 0.0, 0.0, 0.0 ], rows.map { |row| row.fetch(:share) }
    end
  end

  test "snapshots outside the range stay out" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      Solakon::Snapshot.create!(taken_at: 25.hours.ago, pv1_power_w: 900)
      Solakon::Snapshot.create!(taken_at: Time.current, pv1_power_w: 100)
      Solakon::Snapshot.create!(taken_at: 5.minutes.from_now, pv1_power_w: 700)

      payload = Solakon::History.new(range_key: "24h", now: Time.current).payload

      assert_equal [ 100.0 ], payload.dig(:chart, :datasets).first.fetch(:data)
    end
  end

  test "snapshots predating the third and fourth panel keep their PV series" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      Solakon::Snapshot.create!(taken_at: 2.minutes.ago, pv1_power_w: 100, pv2_power_w: 50)
      Solakon::Snapshot.create!(taken_at: Time.current, pv1_power_w: 120, pv2_power_w: 80)

      payload = Solakon::History.new(range_key: "24h", now: Time.current).payload

      assert_equal [ 150.0, 200.0 ], payload.dig(:chart, :datasets).first.fetch(:data)
    end
  end

  test "sign-straddling interval contributes to both directions, not zero" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      Solakon::Snapshot.create!(taken_at: 2.minutes.ago, active_power_w: 1200)
      Solakon::Snapshot.create!(taken_at: Time.current, active_power_w: -1200)

      rows = Solakon::History.new(range_key: "24h", now: Time.current).payload.fetch(:balance_rows)
      delivered = rows.find { |row| row.fetch(:label) == "Ins Hausnetz geliefert" }
      drawn = rows.find { |row| row.fetch(:label) == "Aus Hausnetz gezogen" }

      # Averaging the endpoints first would report 0,00 kWh both ways.
      assert_equal "0,01 kWh", delivered.fetch(:value)
      assert_equal "0,01 kWh", drawn.fetch(:value)
    end
  end

  test "chart_payload rounds series precisely and leaves the labels to the chart" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      Solakon::Snapshot.create!(
        taken_at: Time.current,
        pv1_power_w: 100.111, pv2_power_w: 20.222, pv3_power_w: 3.033, pv4_power_w: 0.09,
        battery_power_w: 45.67,
        active_power_w: 12.34
      )

      payload = Solakon::History.new(range_key: "24h", now: Time.current).payload
      datasets = payload.dig(:chart, :datasets)

      # Fractional inputs tell round(1) apart from truncation and every other rounding.
      assert_not payload.fetch(:chart).key?(:labels), "the chart names the instants itself"
      assert_equal [ 123.5 ], datasets[0].fetch(:data)
      assert_equal [ 45.7 ], datasets[1].fetch(:data)
      assert_equal [ 12.3 ], datasets[2].fetch(:data)
    end
  end

  test "chart_payload carries each snapshot's instant in epoch milliseconds for the time axis" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      taken_at = Time.current - 0.25
      Solakon::Snapshot.create!(taken_at: taken_at, pv1_power_w: 100)

      payload = Solakon::History.new(range_key: "24h", now: Time.current).payload

      assert_equal [ (taken_at.to_i * 1000) + 750 ], payload.dig(:chart, :times)
    end
  end

  test "chart_payload drops what is left of an instant below the millisecond" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      taken_at = Time.current - 0.2505
      Solakon::Snapshot.create!(taken_at: taken_at, pv1_power_w: 100)

      payload = Solakon::History.new(range_key: "24h", now: Time.current).payload

      assert_equal [ (taken_at.to_i * 1000) + 749 ], payload.dig(:chart, :times)
    end
  end

  test "empty payload is stable" do
    payload = Solakon::History.new(range_key: "7d", now: Time.zone.local(2026, 6, 20, 12, 0, 0)).payload

    assert_equal "7d", payload.fetch(:range)
    assert_equal [ :times, :datasets ], payload.fetch(:chart).keys
    assert_equal [], payload.dig(:chart, :times)
    assert_equal [ "PV", "Akku", "Außensteckdose", "0 W" ], payload.dig(:chart, :datasets).map { |dataset| dataset.fetch(:label) }
    assert_equal [ [], [], [], [] ], payload.dig(:chart, :datasets).map { |dataset| dataset.fetch(:data) }
    assert_equal [], payload.fetch(:balance_rows)
    assert_nil payload.fetch(:outlet_average)
    assert_equal "Keine Solakon-Historie", payload.fetch(:message)
  end
end
