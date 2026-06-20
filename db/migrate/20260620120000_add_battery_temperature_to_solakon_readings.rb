class AddBatteryTemperatureToSolakonReadings < ActiveRecord::Migration[8.1]
  def change
    add_column :solakon_readings, :battery_temperature_c, :float
  end
end
