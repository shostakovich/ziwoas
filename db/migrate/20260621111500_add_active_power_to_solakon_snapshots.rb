class AddActivePowerToSolakonSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :solakon_snapshots, :active_power_w, :float
  end
end
