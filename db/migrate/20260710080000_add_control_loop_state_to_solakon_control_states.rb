class AddControlLoopStateToSolakonControlStates < ActiveRecord::Migration[8.1]
  def change
    add_column :solakon_control_states, :control_state, :string
    add_column :solakon_control_states, :trim, :boolean, default: false, null: false
    add_column :solakon_control_states, :last_target_w, :integer
    add_column :solakon_control_states, :consecutive_failures, :integer, default: 0, null: false
  end
end
