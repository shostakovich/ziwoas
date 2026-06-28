class AddColorTempRangeToLights < ActiveRecord::Migration[8.1]
  def change
    add_column :lights, :color_temp_min_k, :integer
    add_column :lights, :color_temp_max_k, :integer
  end
end
