class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  stale_when_importmap_changes

  helper_method :current_look

  private

  def current_look
    Look.named(cookies[Look::COOKIE])
  end

  def app_config
    ConfigLoader.app_config
  end
end
