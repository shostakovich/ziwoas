class AddLastDecisionAtToSolakonControlStates < ActiveRecord::Migration[8.1]
  def change
    add_column :solakon_control_states, :last_decision_at, :datetime
  end
end
