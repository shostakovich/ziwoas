require "test_helper"
require "solakon_client"

class SolakonClientTest < Minitest::Test
  class FakeSlave
    attr_reader :writes
    def initialize(holdings: {})
      @holdings = holdings
      @writes   = []
    end

    def read_holding_registers(addr, count) = @holdings.fetch([ addr, count ])
    def write_holding_register(addr, val) = (@writes << [ :single, addr, val ])
    def write_holding_registers(addr, vals) = (@writes << [ :multi, addr, vals ])
  end

  def client_for(slave)
    SolakonClient.new(host: "h", open: ->(&blk) { blk.call(slave) })
  end

  def test_read_state_decodes_signed_values_via_fc03
    slave = FakeSlave.new(holdings: {
      [ 39424, 1 ] => [ 55 ],                                   # soc 55 %
      [ 39248, 2 ] => [ 0x0000, 0x012C ],                       # active 300 W
      [ 39279, 8 ] => [ 0, 0x0064, 0, 0x0032, 0, 0, 0, 0 ],     # PV1 100W + PV2 50W (+0+0)
      [ 39230, 2 ] => [ 0xFFFF, 0xFF38 ],                       # battery -200 W
    })
    state = client_for(slave).read_state
    assert_equal 55, state.battery_soc
    assert_equal 300, state.active_power_w
    assert_equal 150, state.pv_power_w
    assert_equal(-200, state.battery_power_w)
  end

  def test_apply_control_enables_arms_watchdog_then_writes_setpoint
    slave = FakeSlave.new
    client_for(slave).apply_control!(power_w: 300)
    assert_equal [
      [ :single, 46001, SolakonClient::REMOTE_CONTROL_ENABLE ],
      [ :single, 46002, SolakonClient::REMOTE_TIMEOUT_S ],
      [ :multi, 46003, [ 0x0000, 0x012C ] ],
    ], slave.writes
  end

  def test_apply_control_encodes_negative_power
    slave = FakeSlave.new
    client_for(slave).apply_control!(power_w: -200)
    assert_includes slave.writes, [ :multi, 46003, [ 0xFFFF, 0xFF38 ] ]
  end

  def test_release_control_disables_remote_control
    slave = FakeSlave.new
    client_for(slave).release_control!
    assert_equal [ [ :single, 46001, SolakonClient::REMOTE_CONTROL_DISABLE ] ], slave.writes
  end

  def test_ensure_minimum_soc_writes_config_register
    slave = FakeSlave.new
    client_for(slave).ensure_minimum_soc!(10)
    assert_equal [ [ :single, 46609, 10 ] ], slave.writes
  end

  def test_errors_are_wrapped
    failing = Object.new
    def failing.read_holding_registers(*) = raise("boom")
    client = SolakonClient.new(host: "h", open: ->(&blk) { blk.call(failing) })
    assert_raises(SolakonClient::Error) { client.read_state }
  end
end
