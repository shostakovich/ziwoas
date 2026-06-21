require "test_helper"

class SolakonHistoryTest < ActiveSupport::TestCase
  setup { SolakonSnapshot.delete_all }

  test "payload builds signed chart series and balance rows from snapshots" do
    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      SolakonSnapshot.create!(
        taken_at: 2.hours.ago,
        pv1_power_w: 100,
        pv2_power_w: 50,
        battery_power_w: 20,
        active_power_w: 300,
        grid_power_w: 30,
        pv_total_kwh: 10.0,
        battery_charge_total_kwh: 5.0,
        battery_discharge_total_kwh: 3.0,
        grid_import_total_kwh: 7.0,
        grid_export_total_kwh: 1.0
      )
      SolakonSnapshot.create!(
        taken_at: 1.hour.ago,
        pv1_power_w: 150,
        pv2_power_w: 75,
        battery_power_w: -40,
        active_power_w: -120,
        grid_power_w: -60,
        pv_total_kwh: 11.2,
        battery_charge_total_kwh: 5.4,
        battery_discharge_total_kwh: 3.3,
        grid_import_total_kwh: 7.5,
        grid_export_total_kwh: 1.2
      )

      payload = SolakonHistory.new(range_key: "24h", now: Time.current).payload

      assert_equal "24h", payload.fetch(:range)
      assert_equal [ "PV", "Akku", "Außensteckdose", "0 W" ], payload.dig(:chart, :datasets).map { |dataset| dataset.fetch(:label) }
      assert_equal [ 150.0, 225.0 ], payload.dig(:chart, :datasets).first.fetch(:data)
      assert_equal [ 20.0, -40.0 ], payload.dig(:chart, :datasets)[1].fetch(:data)
      assert_equal [ 300.0, -120.0 ], payload.dig(:chart, :datasets)[2].fetch(:data)
      assert_equal [ 0, 0 ], payload.dig(:chart, :datasets)[3].fetch(:data)

      rows = payload.fetch(:balance_rows)
      assert_equal [ "PV-Erzeugung", "Akku geladen", "Akku entladen", "Netzbezug", "Netzeinspeisung", "Ø Netzleistung" ], rows.map { |row| row.fetch(:label) }
      assert_equal "1,20 kWh", rows[0].fetch(:value)
      assert_equal "0,40 kWh", rows[1].fetch(:value)
      assert_equal "0,30 kWh", rows[2].fetch(:value)
      assert_equal "0,50 kWh", rows[3].fetch(:value)
      assert_equal "0,20 kWh", rows[4].fetch(:value)
    end
  end

  test "empty payload is stable" do
    payload = SolakonHistory.new(range_key: "7d", now: Time.zone.local(2026, 6, 20, 12, 0, 0)).payload

    assert_equal "7d", payload.fetch(:range)
    assert_equal [], payload.dig(:chart, :labels)
    assert_equal "Keine Solakon-Historie", payload.fetch(:message)
  end
end
