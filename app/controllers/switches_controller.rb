class SwitchesController < ApplicationController
  def index
    # Rules whose plug is no longer in ziwoas.yml stay in the database unseen:
    # nothing deletes them, the tick never reaches them (it walks the configured
    # plugs), and a typo in the YAML costs no data. When the plug comes back, so
    # does its schedule.
    plugs = app_config.plugs.select(&:switchable)
    @rows = SwitchRow.build_all(plugs)
    @light_snapshots = LightSnapshot.build_all(Light.order(:name))
  end
end
