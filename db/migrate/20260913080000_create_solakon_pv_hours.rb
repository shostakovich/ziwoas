class CreateSolakonPvHours < ActiveRecord::Migration[8.1]
  def change
    create_table :solakon_pv_hours do |t|
      t.datetime :started_at,    null: false
      t.float    :pv_power_w,    null: false
      t.float    :pv1_power_w
      t.float    :pv2_power_w
      t.float    :pv3_power_w
      t.float    :pv4_power_w
      t.integer  :reading_count, null: false
    end
    add_index :solakon_pv_hours, :started_at, unique: true
  end
end
