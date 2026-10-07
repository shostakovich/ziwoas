defmodule Ziwoas.Solakon.Alarms do
  @moduledoc """
  The status and alarm registers (39063–39069, `docs/solakon-modbus-protocol.md`
  §7) and the battery management's faults, decoded into conditions: atoms in
  register and bit order, `:battery_warning` last. No condition means all is quiet.
  """
  import Bitwise

  @status [
    inverter_ready: {:status1, 0},
    inverter_running: {:status1, 2},
    inverter_fault: {:status1, 6},
    island_mode: {:status3, 0}
  ]

  @alarm_bits [
    alarm1: [
      {0, :pv_overvoltage},
      {1, :dc_arc_fault},
      {2, :pv_string_reversed},
      {8, :grid_loss},
      {9, :grid_voltage},
      {11, :grid_frequency},
      {14, :output_overcurrent},
      {15, :output_dc_component}
    ],
    alarm2: [
      {0, :residual_current},
      {1, :grounding},
      {2, :low_insulation},
      {3, :overtemperature},
      {9, :storage_fault},
      {10, :islanding_detected},
      {14, :outlet_overload}
    ],
    alarm3: [
      {3, :fan_fault},
      {4, :storage_reversed},
      {9, :meter_lost},
      {10, :bms_unreachable}
    ]
  ]

  @type condition :: atom

  @doc "Every condition the decoder can answer, in its order."
  @spec all() :: [condition]
  def all,
    do:
      Keyword.keys(@status) ++
        for({_, bits} <- @alarm_bits, {_, condition} <- bits, do: condition) ++
        [:battery_warning]

  @doc """
  The conditions of a reading's or snapshot's registers (`status1`, `status3`,
  `alarm1`..`alarm3`, nil read as 0) and the battery management's faults.
  """
  @spec conditions(map, [integer | nil]) :: [condition]
  def conditions(registers, bms_faults \\ []) do
    status =
      for {condition, {key, bit}} <- @status,
          set?(Map.fetch!(registers, key), bit),
          do: condition

    alarms =
      for {key, bits} <- @alarm_bits,
          {bit, condition} <- bits,
          set?(Map.fetch!(registers, key), bit),
          do: condition

    faults = if Enum.any?(bms_faults, &((&1 || 0) > 0)), do: [:battery_warning], else: []

    status ++ alarms ++ faults
  end

  defp set?(value, bit), do: ((value || 0) &&& 1 <<< bit) > 0
end
