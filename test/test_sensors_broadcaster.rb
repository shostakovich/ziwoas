require "test_helper"
require "sensors_broadcaster"

class SensorsBroadcasterTest < ActiveSupport::TestCase
  test "broadcasts replace to sensors stream targeting the dashboard" do
    calls = []
    Turbo::StreamsChannel.stub(:broadcast_replace_to,
                               ->(stream, **opts) { calls << [ stream, opts[:target] ] }) do
      SensorsBroadcaster.refresh
    end
    assert_includes calls, [ "sensors", "sensors_dashboard" ]
  end
end
