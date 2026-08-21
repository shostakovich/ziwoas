class SwitchesController < ApplicationController
  def index
    # Verwaiste Schaltzeiten — those of a plug no longer in ziwoas.yml — stay in
    # the database unseen and switch nothing, so a typo in the YAML costs no
    # data. When the plug comes back, so does its schedule.
    plugs = app_config.plugs.select(&:switchable)
    @rows = Switching::Row.build_all(plugs)
    @light_snapshots = LightSnapshot.build_all(Light.order(:name))
  end
end
