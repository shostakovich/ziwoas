defmodule Ziwoas.Solakon.Reading do
  @moduledoc """
  One polled reading of the Solakon inverter (`solakon_readings`): the control's
  thresholds and the battery character. `Ziwoas.Solakon` stores and reads them.
  """
  use Ziwoas.Schema

  @min_soc_pct 10
  @resume_soc_pct 11
  @low_soc_pct 20
  # Thermal de-rating starts here (full output ceiling) and protection ends below it.
  @hot_temp_c 45.0
  @cold_temp_c 5.0
  # De-rating reaches zero: 1 °C below the inverter's own 50 °C curtailment.
  @cutoff_temp_c 49.0
  @charge_deadband_w 10
  @pv_present_w 50
  @stale_after_s 120

  @type t :: %__MODULE__{}

  def min_soc_pct, do: @min_soc_pct
  def low_soc_pct, do: @low_soc_pct
  def hot_temp_c, do: @hot_temp_c
  def cutoff_temp_c, do: @cutoff_temp_c
  def cold_temp_c, do: @cold_temp_c
  def charge_deadband_w, do: @charge_deadband_w
  def stale_after_s, do: @stale_after_s

  schema "solakon_readings" do
    field :active_power_w, :float
    field :alarm1, :integer
    field :alarm2, :integer
    field :alarm3, :integer
    field :battery_current_a, :float
    field :battery_power_w, :float
    field :battery_soc_pct, :integer
    field :battery_temperature_c, :float
    field :battery_voltage_v, :float
    field :eps_enabled, :boolean
    field :eps_power_w, :float
    field :eps_voltage_v, :float
    field :inverter_temperature_c, :float
    field :pv_power_w, :float
    field :status1, :integer
    field :status3, :integer
    field :taken_at, :utc_datetime_usec
    timestamps()
  end

  @state_columns [
    :active_power_w,
    :pv_power_w,
    :battery_power_w,
    :battery_temperature_c,
    :battery_voltage_v,
    :battery_current_a,
    :inverter_temperature_c,
    :status1,
    :status3,
    :alarm1,
    :alarm2,
    :alarm3,
    :eps_enabled,
    :eps_voltage_v,
    :eps_power_w
  ]

  @doc """
  A changeset for a decoded
  `Ziwoas.Solakon.Client.read_state/1` taken at `taken_at`.
  """
  @spec from_state(map, DateTime.t()) :: Ecto.Changeset.t()
  def from_state(state, taken_at) do
    attrs =
      state
      |> Map.take(@state_columns)
      |> Map.merge(%{battery_soc_pct: state.battery_soc, taken_at: taken_at})

    %__MODULE__{}
    |> Ecto.Changeset.cast(attrs, [:battery_soc_pct, :taken_at | @state_columns])
    |> Ecto.Changeset.validate_required([
      :taken_at,
      :active_power_w,
      :pv_power_w,
      :battery_power_w,
      :battery_soc_pct
    ])
    |> Ecto.Changeset.validate_number(:battery_soc_pct,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
  end

  # The control's thresholds.
  def soc_below_minimum?(%__MODULE__{battery_soc_pct: soc}), do: soc <= @min_soc_pct
  def soc_at_resume?(%__MODULE__{battery_soc_pct: soc}), do: soc >= @resume_soc_pct

  def battery_hot?(%__MODULE__{battery_temperature_c: temp}),
    do: not is_nil(temp) and temp >= @hot_temp_c

  def battery_cooled?(%__MODULE__{battery_temperature_c: temp}),
    do: is_nil(temp) or temp < @hot_temp_c

  def pv_present?(%__MODULE__{pv_power_w: pv}), do: (pv || 0) >= @pv_present_w

  @doc "Charging positive, discharging negative, as the inverter reports it."
  @spec battery_display_power_w(t) :: float
  def battery_display_power_w(%__MODULE__{battery_power_w: watts}), do: (watts || 0) * 1.0

  @doc "The battery character the UI shows; a fault wins, then thermal, then charge level and flow."
  @spec battery_state(t) :: String.t()
  def battery_state(%__MODULE__{} = reading) do
    cond do
      alarmed?(reading) -> "fault"
      battery_hot?(reading) -> "hot"
      battery_cold?(reading) -> "cold"
      battery_low?(reading) -> "low"
      true -> flow_state(battery_display_power_w(reading))
    end
  end

  defp alarmed?(reading),
    do: Enum.any?([reading.alarm1, reading.alarm2, reading.alarm3], &((&1 || 0) > 0))

  defp battery_cold?(%__MODULE__{battery_temperature_c: temp}),
    do: not is_nil(temp) and temp <= @cold_temp_c

  defp battery_low?(%__MODULE__{battery_soc_pct: soc}),
    do: not is_nil(soc) and soc <= @low_soc_pct

  defp flow_state(power) when power > @charge_deadband_w, do: "charging"
  defp flow_state(power) when power < -@charge_deadband_w, do: "discharging"
  defp flow_state(_power), do: "normal"
end
