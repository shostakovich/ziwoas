require "rmodbus"

# Thin Modbus-TCP wrapper for the Solakon One inverter.
# Register addresses come from solakon-de/solakon-one-homeassistant
# (custom_components/solakon_one/const.py) — verified in Task 1.
class SolakonClient
  class Error < StandardError; end

  # Holding registers (read/write)
  REG_REMOTE_CONTROL      = 46001 # u16 – control-mode enable
  REG_REMOTE_ACTIVE_POWER = 46003 # i32 – setpoint W (2 regs)
  REG_MINIMUM_SOC         = 46609 # u16 – %

  # Input registers (read-only)
  REG_BATTERY_SOC   = 39424 # i16 – %
  REG_ACTIVE_POWER  = 39134 # i32 – W (2 regs)
  REG_PV_POWER      = 39118 # i32 – W (2 regs)
  REG_BATTERY_POWER = 39230 # i32 – W (2 regs)

  # Value written to REG_REMOTE_CONTROL to enable remote active-power control.
  REMOTE_CONTROL_ENABLE = 1

  State = Struct.new(:battery_soc, :active_power_w, :pv_power_w, :battery_power_w,
                     keyword_init: true)

  def initialize(host:, port: 502, unit_id: 1, open: nil)
    @host    = host
    @port    = port
    @unit_id = unit_id
    @open    = open || method(:default_open)
  end

  def read_state
    with_slave do |slave|
      State.new(
        battery_soc:     to_i16(slave.read_input_registers(REG_BATTERY_SOC, 1).first),
        active_power_w:  to_i32(slave.read_input_registers(REG_ACTIVE_POWER, 2)),
        pv_power_w:      to_i32(slave.read_input_registers(REG_PV_POWER, 2)),
        battery_power_w: to_i32(slave.read_input_registers(REG_BATTERY_POWER, 2)),
      )
    end
  end

  def write_output_power!(watts)
    with_slave { |slave| slave.write_holding_registers(REG_REMOTE_ACTIVE_POWER, from_i32(watts.to_i)) }
  end

  def ensure_remote_control!
    with_slave { |slave| slave.write_holding_register(REG_REMOTE_CONTROL, REMOTE_CONTROL_ENABLE) }
  end

  def ensure_minimum_soc!(pct)
    with_slave { |slave| slave.write_holding_register(REG_MINIMUM_SOC, pct.to_i) }
  end

  private

  def default_open(&blk)
    ModBus::TCPClient.connect(@host, @port) do |client|
      client.with_slave(@unit_id) { |slave| blk.call(slave) }
    end
  end

  def with_slave(&blk)
    @open.call(&blk)
  rescue Error
    raise
  rescue StandardError => e
    raise Error, "#{e.class}: #{e.message}"
  end

  # Big-endian word order: [high, low]
  def to_i32(regs)
    raw = ((regs[0] & 0xFFFF) << 16) | (regs[1] & 0xFFFF)
    raw >= 0x8000_0000 ? raw - 0x1_0000_0000 : raw
  end

  def from_i32(value)
    raw = value.negative? ? value + 0x1_0000_0000 : value
    [ (raw >> 16) & 0xFFFF, raw & 0xFFFF ]
  end

  def to_i16(reg)
    reg >= 0x8000 ? reg - 0x1_0000 : reg
  end
end
