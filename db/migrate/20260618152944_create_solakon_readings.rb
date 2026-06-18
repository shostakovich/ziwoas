class CreateSolakonReadings < ActiveRecord::Migration[8.1]
  def change
    create_table :solakon_readings do |t|
      t.datetime :taken_at, null: false
      t.float :active_power_w, null: false
      t.float :pv_power_w, null: false
      t.float :battery_power_w, null: false
      t.integer :battery_soc_pct, null: false

      t.timestamps
    end

    add_index :solakon_readings, :taken_at
  end
end
