require "test_helper"
require "solakon_client"

class SolakonClientTest < Minitest::Test
  class FakeSlave
    attr_reader :writes
    def initialize(inputs: {})
      @inputs = inputs
      @writes = []
    end

    def read_input_registers(addr, count) = @inputs.fetch([ addr, count ])
    def write_holding_register(addr, val) = (@writes << [ :single, addr, val ])
    def write_holding_registers(addr, vals) = (@writes << [ :multi, addr, vals ])
  end

  def client_for(slave)
    SolakonClient.new(host: "h", open: ->(&blk) { blk.call(slave) })
  end

  def test_read_state_decodes_signed_values
    slave = FakeSlave.new(inputs: {
      [ 39424, 1 ] => [ 55 ],
      [ 39134, 2 ] => [ 0x0000, 0x012C ],
      [ 39118, 2 ] => [ 0x0000, 0x0064 ],
      [ 39230, 2 ] => [ 0xFFFF, 0xFF38 ],
    })
    state = client_for(slave).read_state
    assert_equal 55, state.battery_soc
    assert_equal 300, state.active_power_w
    assert_equal 100, state.pv_power_w
    assert_equal(-200, state.battery_power_w)
  end

  def test_apply_control_writes_mode_min_soc_and_power_in_one_pass
    slave = FakeSlave.new
    client_for(slave).apply_control!(power_w: 300, min_soc: 10)
    assert_equal [
      [ :single, 46001, SolakonClient::REMOTE_CONTROL_ENABLE ],
      [ :single, 46609, 10 ],
      [ :multi, 46003, [ 0x0000, 0x012C ] ],
    ], slave.writes
  end

  def test_apply_control_encodes_negative_power
    slave = FakeSlave.new
    client_for(slave).apply_control!(power_w: -200, min_soc: 10)
    assert_includes slave.writes, [ :multi, 46003, [ 0xFFFF, 0xFF38 ] ]
  end

  def test_release_control_disables_remote_control
    slave = FakeSlave.new
    client_for(slave).release_control!
    assert_equal [ [ :single, 46001, SolakonClient::REMOTE_CONTROL_DISABLE ] ], slave.writes
  end

  def test_errors_are_wrapped
    failing = Object.new
    def failing.read_input_registers(*) = raise("boom")
    client = SolakonClient.new(host: "h", open: ->(&blk) { blk.call(failing) })
    assert_raises(SolakonClient::Error) { client.read_state }
  end
end
