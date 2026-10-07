defmodule Ziwoas.Solakon.Client do
  @moduledoc """
  Which holding registers make a reading (`read_state/1`, the 30 s monitor) and
  a snapshot (`read_snapshot/1`, every two minutes), how their words decode, and
  what the control writes (`apply_control/4`, `set_eps_output/2`,
  `release_control/1`) — `docs/solakon-modbus-protokoll.md` §2 and §9. Registers
  are read one field at a time.

  `read` is `fn address, count -> {:ok, words} | {:error, reason} end`, `write` is
  `fn {:single, address, word} | {:multiple, address, [word]} -> :ok | {:error,
  reason} end`; `Ziwoas.Solakon.Monitor` runs both over its connection. Unscaled
  values decode as integers, scaled ones as floats.
  """
  import Bitwise

  @pv_strings 4
  @eps_on 2
  @eps_off 0

  # Control registers (volatile, written every tick) and the persisted minimum SoC.
  @reg_remote_control 46001
  @reg_remote_timeout 46002
  @reg_remote_active_power 46003
  @reg_minimum_soc 46609
  @reg_eps_output 46613
  # 46001: bit0 enable, bit1 direction (0 = generation), bits 3:2 target (00 = AC).
  @remote_control_enable 0b0001
  @remote_control_disable 0
  @remote_timeout_s 150

  @doc "The inverter-side watchdog: without a command for this long it drops remote control."
  def remote_timeout_s, do: @remote_timeout_s

  # The reading's fields, in the order they are read.
  @fast [
    battery_soc: {39424, 1, :i16, nil},
    active_power_w: {39248, 2, :i32, nil},
    battery_power_w: {39230, 2, :i32, nil},
    battery_temperature_c: {37617, 1, :i16, 10.0},
    battery_voltage_v: {39227, 1, :i16, 10.0},
    battery_current_a: {39228, 2, :i32, 1000.0},
    inverter_temperature_c: {39141, 1, :i16, 10.0},
    status1: {39063, 1, :u16, nil},
    status3: {39065, 2, :u32, nil},
    alarm1: {39067, 1, :u16, nil},
    alarm2: {39068, 1, :u16, nil},
    alarm3: {39069, 1, :u16, nil},
    eps_mode: {46613, 1, :u16, nil},
    eps_voltage_v: {39201, 1, :u16, 10.0},
    eps_power_w: {39216, 2, :i32, nil}
  ]

  @snapshot_overrides [
    battery_voltage_v: {37609, 1, :u16, 10.0},
    battery_current_a: {37610, 1, :i16, 10.0},
    battery_temperature_c: {37611, 1, :i16, 10.0},
    battery_min_temperature_c: {37618, 1, :i16, 10.0},
    battery_health_pct: {37624, 1, :u16, nil},
    remaining_energy_wh: {37632, 1, :u16, 10.0},
    full_charge_capacity_ah: {37633, 1, :u16, 10.0},
    design_energy_wh: {37635, 1, :u16, 10.0},
    grid_power_w: {39168, 2, :i32, :negate}
  ]

  # An overridden key keeps its place, new keys follow.
  @snapshot Enum.map(@fast, fn {key, spec} ->
              {key, Keyword.get(@snapshot_overrides, key, spec)}
            end) ++
              Enum.reject(@snapshot_overrides, fn {key, _} -> Keyword.has_key?(@fast, key) end)

  @groups [
    pv_voltage_current: {39070, @pv_strings * 2},
    pv_power: {39279, @pv_strings * 2},
    bms_faults: {37626, 6},
    energy_counters: {39601, 20}
  ]

  @type read :: (non_neg_integer, pos_integer -> {:ok, [non_neg_integer]} | {:error, term})
  @type write_op ::
          {:single, non_neg_integer, non_neg_integer}
          | {:multiple, non_neg_integer, [non_neg_integer]}
  @type write :: (write_op -> :ok | {:error, term})

  @doc """
  The minimum SoC only when the device holds another value (a
  persisted register, so flash is spared), then remote control on, the watchdog
  re-armed and the active-power setpoint last.
  """
  @spec apply_control(read, write, integer, integer) :: :ok | {:error, term}
  def apply_control(read, write, power_w, min_soc) do
    with {:ok, [current | _]} <- read.(@reg_minimum_soc, 1),
         :ok <-
           if(current != min_soc, do: write.({:single, @reg_minimum_soc, min_soc}), else: :ok),
         :ok <- write.({:single, @reg_remote_control, @remote_control_enable}),
         :ok <- write.({:single, @reg_remote_timeout, @remote_timeout_s}) do
      write.({:multiple, @reg_remote_active_power, from_i32(power_w)})
    else
      {:ok, []} -> {:error, {:short_read, @reg_minimum_soc, 0}}
      {:error, _} = error -> error
    end
  end

  @doc "The outdoor socket (EPS output, 46613): 2 on, 0 off; nil is off."
  @spec set_eps_output(write, boolean | nil) :: :ok | {:error, term}
  def set_eps_output(write, enabled),
    do: write.({:single, @reg_eps_output, if(enabled, do: @eps_on, else: @eps_off)})

  @doc "Hands control back: 46001 = 0, the inverter returns to its own default."
  @spec release_control(write) :: :ok | {:error, term}
  def release_control(write), do: write.({:single, @reg_remote_control, @remote_control_disable})

  @doc "An i32 as two words, high word first."
  @spec from_i32(integer) :: [non_neg_integer]
  def from_i32(value) do
    raw = if value < 0, do: value + 0x1_0000_0000, else: value
    [raw >>> 16 &&& 0xFFFF, raw &&& 0xFFFF]
  end

  @doc "The fields of the monitor's reading."
  @spec read_state(read) :: {:ok, map} | {:error, term}
  def read_state(read) do
    with {:ok, fields} <- read_fields(read, @fast),
         {:ok, pv} <- group(read, :pv_power) do
      {eps_mode, fields} = Map.pop!(fields, :eps_mode)

      {:ok,
       Map.merge(fields, %{
         pv_power_w: Enum.sum(for i <- 0..(@pv_strings - 1), do: i32(Enum.slice(pv, i * 2, 2))),
         eps_enabled: eps_mode == @eps_on
       })}
    end
  end

  @doc "The fields of a snapshot, panels as `%{index:, voltage_v:, current_a:, power_w:}`."
  @spec read_snapshot(read) :: {:ok, map} | {:error, term}
  def read_snapshot(read) do
    with {:ok, fields} <- read_fields(read, @snapshot),
         {:ok, groups} <- read_groups(read) do
      {eps_mode, fields} = Map.pop!(fields, :eps_mode)
      fields = Map.delete(fields, :battery_soc)

      {:ok,
       fields
       |> Map.merge(energy_counters(groups.energy_counters))
       |> Map.merge(%{
         panels: panels(groups.pv_voltage_current, groups.pv_power),
         eps_enabled: eps_mode == @eps_on,
         bms_faults: groups.bms_faults
       })}
    end
  end

  defp read_fields(read, specs) do
    Enum.reduce_while(specs, {:ok, %{}}, fn {key, {address, count, type, scale}}, {:ok, acc} ->
      case read.(address, count) do
        {:ok, words} when length(words) == count ->
          {:cont, {:ok, Map.put(acc, key, value(words, type, scale))}}

        {:ok, words} ->
          {:halt, {:error, {:short_read, address, length(words)}}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp read_groups(read) do
    Enum.reduce_while(@groups, {:ok, %{}}, fn {key, _}, {:ok, acc} ->
      case group(read, key) do
        {:ok, words} -> {:cont, {:ok, Map.put(acc, key, words)}}
        error -> {:halt, error}
      end
    end)
  end

  defp group(read, key) do
    {address, count} = Keyword.fetch!(@groups, key)

    case read.(address, count) do
      {:ok, words} when length(words) == count -> {:ok, words}
      {:ok, words} -> {:error, {:short_read, address, length(words)}}
      error -> error
    end
  end

  defp value(words, type, nil), do: decode(words, type)
  defp value(words, type, :negate), do: -decode(words, type)
  defp value(words, type, scale), do: decode(words, type) / scale

  defp panels(vi, powers) do
    for i <- 0..(@pv_strings - 1) do
      %{
        index: i + 1,
        voltage_v: i16(Enum.at(vi, i * 2)) / 10,
        current_a: i16(Enum.at(vi, i * 2 + 1)) / 100,
        power_w: i32(Enum.slice(powers, i * 2, 2))
      }
    end
  end

  defp energy_counters(words) do
    kwh = fn offset -> u32(Enum.slice(words, offset, 2)) / 100 end

    %{
      pv_total_kwh: kwh.(0),
      battery_charge_total_kwh: kwh.(4),
      battery_discharge_total_kwh: kwh.(8),
      grid_export_total_kwh: kwh.(12),
      grid_import_total_kwh: kwh.(16)
    }
  end

  @doc "Decodes words as `:u16`, `:i16`, `:u32` or `:i32` (high word first)."
  def decode([word | _], :u16), do: word
  def decode([word | _], :i16), do: i16(word)
  def decode(words, :u32), do: u32(words)
  def decode(words, :i32), do: i32(words)

  defp i16(word) when word >= 0x8000, do: word - 0x10000
  defp i16(word), do: word

  defp u32([high, low]), do: (high &&& 0xFFFF) <<< 16 ||| (low &&& 0xFFFF)

  defp i32(words) do
    raw = u32(words)
    if raw >= 0x8000_0000, do: raw - 0x1_0000_0000, else: raw
  end
end
