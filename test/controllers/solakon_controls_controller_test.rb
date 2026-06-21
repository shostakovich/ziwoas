require "test_helper"

class SolakonControlsControllerTest < ActionDispatch::IntegrationTest
  class FakeClient
    class << self
      attr_accessor :instance
    end

    attr_reader :calls

    def initialize(host:, port:, unit_id:)
      @calls = [ [ :initialize, host, port, unit_id ] ]
      self.class.instance = self
    end

    def set_eps_output!(enabled:)
      @calls << [ :set_eps_output, enabled ]
    end
  end

  Sol = Struct.new(:host, :port, :unit_id, :monitoring_enabled, :control_enabled, :stale_after_s, keyword_init: true)
  Cfg = Struct.new(:solakon, keyword_init: true)

  setup { SolakonControlState.delete_all }

  def config(control_enabled: true, solakon: true)
    Cfg.new(solakon: (Sol.new(host: "h", port: 502, unit_id: 1, monitoring_enabled: true, control_enabled: control_enabled, stale_after_s: 120) if solakon))
  end

  test "eps endpoint writes directly through SolakonClient" do
    ConfigLoader.stub(:app_config, config) do
      SolakonClient.stub(:new, ->(host:, port:, unit_id:) { FakeClient.new(host: host, port: port, unit_id: unit_id) }) do
        patch "/solakon/eps", params: { enabled: "true" }, as: :json
      end
    end

    assert_response :success
    assert_equal true, response.parsed_body["enabled"]
    assert_equal [ [ :initialize, "h", 502, 1 ], [ :set_eps_output, true ] ], FakeClient.instance.calls
  end

  test "eps endpoint returns service unavailable on Modbus failure" do
    failing = Object.new
    def failing.set_eps_output!(enabled:) = raise SolakonClient::Error, "down"

    ConfigLoader.stub(:app_config, config) do
      SolakonClient.stub(:new, ->(**) { failing }) do
        patch "/solakon/eps", params: { enabled: "true" }, as: :json
      end
    end

    assert_response :service_unavailable
    assert_equal "Schalten fehlgeschlagen", response.parsed_body["error"]
  end

  test "auto regulation resumes and pauses when config permits control" do
    ConfigLoader.stub(:app_config, config(control_enabled: true)) do
      patch "/solakon/auto_regulation", params: { active: "false" }, as: :json
    end

    assert_response :success
    assert_equal false, response.parsed_body["active"]
    assert_not SolakonControlState.current.auto_regulation_active?

    ConfigLoader.stub(:app_config, config(control_enabled: true)) do
      patch "/solakon/auto_regulation", params: { active: "true" }, as: :json
    end

    assert_response :success
    assert_equal true, response.parsed_body["active"]
    assert SolakonControlState.current.auto_regulation_active?
  end

  test "auto regulation cannot enable when config disables control" do
    SolakonControlState.current.pause_auto_regulation!

    ConfigLoader.stub(:app_config, config(control_enabled: false)) do
      patch "/solakon/auto_regulation", params: { active: "true" }, as: :json
    end

    assert_response :forbidden
    assert_equal "in Konfiguration deaktiviert", response.parsed_body["error"]
    assert_not SolakonControlState.current.auto_regulation_active?
  end
end
