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
      [ 39424, 1 ] => [ 55 ],               # soc 55 %
      [ 39134, 2 ] => [ 0x0000, 0x012C ],   # active 300 W
      [ 39118, 2 ] => [ 0x0000, 0x0064 ],   # pv 100 W
      [ 39230, 2 ] => [ 0xFFFF, 0xFF38 ],   # battery -200 W (laden)
    })
    state = client_for(slave).read_state
    assert_equal 55, state.battery_soc
    assert_equal 300, state.active_power_w
    assert_equal 100, state.pv_power_w
    assert_equal(-200, state.battery_power_w)
  end

  def test_write_output_power_encodes_i32_big_endian
    slave = FakeSlave.new
    client_for(slave).write_output_power!(300)
    assert_equal [ :multi, 46003, [ 0x0000, 0x012C ] ], slave.writes.first
  end

  def test_write_output_power_encodes_negative
    slave = FakeSlave.new
    client_for(slave).write_output_power!(-200)
    assert_equal [ :multi, 46003, [ 0xFFFF, 0xFF38 ] ], slave.writes.first
  end

  def test_ensure_helpers_write_single_registers
    slave = FakeSlave.new
    c = client_for(slave)
    c.ensure_remote_control!
    c.ensure_minimum_soc!(10)
    assert_includes slave.writes, [ :single, 46001, SolakonClient::REMOTE_CONTROL_ENABLE ]
    assert_includes slave.writes, [ :single, 46609, 10 ]
  end

  def test_errors_are_wrapped
    failing = Object.new
    def failing.read_input_registers(*) = raise("boom")
    client = SolakonClient.new(host: "h", open: ->(&blk) { blk.call(failing) })
    assert_raises(SolakonClient::Error) { client.read_state }
  end
end
