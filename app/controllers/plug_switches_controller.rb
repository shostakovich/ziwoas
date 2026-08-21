class PlugSwitchesController < ApplicationController
  def create
    plug = app_config.plugs.find { |p| p.id == params[:plug_id] }
    return head :not_found unless plug
    return head :unprocessable_entity unless plug.switchable
    return head :unprocessable_entity unless %w[on off].include?(params[:state])

    Switching::Commander.switch(plug, params[:state].to_sym, source: :manual, mqtt_config: app_config.mqtt)
    render turbo_stream: turbo_stream.replace(
      "sw_head_#{plug.id}",
      partial: "switches/head", locals: { row: Switching::Row.build(plug) }
    )
  rescue Switching::Commander::Error
    render turbo_stream: turbo_stream.update(
      "sw_error_#{plug.id}",
      "Schalten fehlgeschlagen — MQTT-Broker nicht erreichbar"
    ), status: :service_unavailable
  end
end
