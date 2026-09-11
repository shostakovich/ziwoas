# The row stores what the last tick decided and whether the loop is paused.
# "control_state" said nothing about which state it held, and
# "auto_regulation_paused" named the switch instead of the thing it stops.
class RenameControlStateColumns < ActiveRecord::Migration[8.1]
  def change
    rename_column :solakon_control_states, :control_state, :decision_state
    rename_column :solakon_control_states, :auto_regulation_paused, :paused
  end
end
