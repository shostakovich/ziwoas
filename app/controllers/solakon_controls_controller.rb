class SolakonControlsController < ApplicationController
  def eps
    solakon = app_config.solakon
    return render json: { error: "Solakon nicht konfiguriert" }, status: :service_unavailable if solakon.nil?

    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    client = Solakon::Client.from_config(solakon)
    client.set_eps_output!(enabled: enabled)

    render json: { enabled: enabled }
  rescue Solakon::Client::Error => e
    Rails.logger.warn("solakon_controls: EPS switch failed: #{e.message}")
    render json: { error: "Schalten fehlgeschlagen" }, status: :service_unavailable
  end

  def auto_regulation
    solakon = app_config.solakon
    return render json: { error: "Solakon nicht konfiguriert" }, status: :service_unavailable if solakon.nil?
    return render json: { error: "in Konfiguration deaktiviert" }, status: :forbidden unless solakon.control_enabled

    active = ActiveModel::Type::Boolean.new.cast(params[:active])
    state = SolakonControlState.current
    active ? state.resume_auto_regulation! : state.pause_auto_regulation!

    render json: { active: state.auto_regulation_active? }
  end
end
