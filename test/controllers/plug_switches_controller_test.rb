require "test_helper"

class PlugSwitchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Switching::Command.delete_all
    @calls = []
    @recorder = ->(plug, action, source:, mqtt_config:) { @calls << [ plug.id, action, source ] }
  end

  test "unknown plug returns 404" do
    post "/plugs/nope/switch", params: { state: "on" }
    assert_response :not_found
  end

  test "non-switchable plug returns 422" do
    post "/plugs/bkw/switch", params: { state: "on" }
    assert_response :unprocessable_entity
  end

  test "invalid state returns 422" do
    post "/plugs/fridge/switch", params: { state: "toggle" }
    assert_response :unprocessable_entity
  end

  test "valid switch calls Switching::Commander and responds with a turbo stream" do
    Switching::Commander.stub :switch, @recorder do
      post "/plugs/fridge/switch", params: { state: "on" }, as: :turbo_stream
    end
    assert_response :success
    assert_equal [ [ "fridge", :on, :manual ] ], @calls
    assert_match "sw_head_fridge", @response.body
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
  end

  test "broker failure responds 503 with an error stream and writes no command" do
    failing = ->(*, **) { raise Switching::Commander::Error, "broker down" }
    Switching::Commander.stub :switch, failing do
      post "/plugs/fridge/switch", params: { state: "on" }, as: :turbo_stream
    end
    assert_response :service_unavailable
    assert_match "sw_error_fridge", @response.body
    assert_match "nicht erreichbar", @response.body
    assert_equal 0, Switching::Command.count
  end
end
