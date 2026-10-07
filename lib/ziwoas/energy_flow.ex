defmodule Ziwoas.EnergyFlow do
  @moduledoc """
  Where the power goes right now: the house's draw from
  the consumer plugs, the inverter's fresh reading, and the six flows between
  PV, grid, battery and house. Without a fresh reading the inverter is
  offline and everything derived from it is unknown (nil), not zero.
  """
  alias Ziwoas.Solakon.Reading

  defmodule Flows do
    @moduledoc false
    @keys [
      :solar_to_home_w,
      :solar_to_grid_w,
      :solar_to_battery_w,
      :grid_to_home_w,
      :grid_to_battery_w,
      :battery_to_home_w
    ]
    defstruct @keys

    def keys, do: @keys

    @doc "One missing input makes every flow unknown: a partial split would read as measured zeroes."
    def split(home_w, solar_w, battery_w, grid_w) do
      if Enum.any?([home_w, solar_w, battery_w, grid_w], &is_nil/1) do
        %__MODULE__{}
      else
        do_split(
          max(home_w * 1.0, 0.0),
          max(solar_w * 1.0, 0.0),
          battery_w * 1.0,
          grid_w * 1.0
        )
      end
    end

    defp do_split(home, solar, battery, grid) do
      grid_import = max(grid, 0.0)
      solar_to_grid = max(-grid, 0.0)
      grid_to_home = min(grid_import, home)
      home_remaining = max(home - grid_to_home, 0.0)
      solar_remaining = max(solar - solar_to_grid, 0.0)

      solar_to_home = min(solar_remaining, home_remaining)
      solar_remaining = solar_remaining - solar_to_home
      home_remaining = home_remaining - solar_to_home

      {solar_to_battery, grid_to_battery, battery_to_home} =
        if battery > 0 do
          {solar_remaining, min(grid_import - grid_to_home, max(battery - solar_remaining, 0.0)),
           0.0}
        else
          {0.0, 0.0, min(-battery, home_remaining)}
        end

      %__MODULE__{
        solar_to_home_w: watts(solar_to_home),
        solar_to_grid_w: watts(solar_to_grid),
        solar_to_battery_w: watts(solar_to_battery),
        grid_to_home_w: watts(grid_to_home),
        grid_to_battery_w: watts(grid_to_battery),
        battery_to_home_w: watts(battery_to_home)
      }
    end

    # Adding 0.0 turns a negative zero (an idle battery's -0.0) into 0.0.
    defp watts(value), do: Float.round(value, 1) + 0.0
  end

  @keys [
    :solakon_online,
    :home_w,
    :solakon_ac_w,
    :solar_w,
    :battery_soc_pct,
    :battery_w,
    :battery_state,
    :grid_w,
    :flows
  ]
  @enforce_keys @keys
  defstruct @keys

  @type t :: %__MODULE__{}

  @spec build(float | nil, Reading.t() | nil) :: t
  def build(home_w, reading) do
    solar_w = reading && reading.pv_power_w
    battery_w = reading && Reading.battery_display_power_w(reading)
    grid_w = if home_w && reading, do: home_w - reading.active_power_w

    %__MODULE__{
      solakon_online: not is_nil(reading),
      home_w: float(home_w),
      solakon_ac_w: float(reading && reading.active_power_w),
      solar_w: float(solar_w),
      battery_soc_pct: reading && reading.battery_soc_pct,
      battery_w: float(battery_w),
      battery_state: reading && Reading.battery_state(reading),
      grid_w: float(grid_w),
      flows: Flows.split(home_w, solar_w, battery_w, grid_w)
    }
  end

  @doc "The state as JSON, for the `EnergyFlow` hook's `data-state`."
  @spec to_json(t) :: String.t()
  def to_json(%__MODULE__{} = flow) do
    flow
    |> Map.from_struct()
    |> Map.update!(:flows, &Map.from_struct/1)
    |> JSON.encode!()
  end

  defp float(nil), do: nil
  defp float(value), do: value * 1.0
end
