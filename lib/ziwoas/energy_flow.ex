defmodule Ziwoas.EnergyFlow do
  @moduledoc """
  Where the power goes right now (Rails' `EnergyFlow`): the house's draw from
  the consumer plugs, the inverter's fresh reading, and the six flows between
  PV, grid, battery and house. Without a fresh reading the inverter is
  offline and everything derived from it is unknown (nil), not zero.
  """
  alias Ziwoas.{RubyJSON, RubyNumeric}
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
          RubyNumeric.max([RubyNumeric.to_f(home_w), 0.0]),
          RubyNumeric.max([RubyNumeric.to_f(solar_w), 0.0]),
          RubyNumeric.to_f(battery_w),
          RubyNumeric.to_f(grid_w)
        )
      end
    end

    defp do_split(home, solar, battery, grid) do
      grid_import = max_of(grid, 0.0)
      solar_to_grid = max_of(-grid, 0.0)
      grid_to_home = min_of(grid_import, home)
      home_remaining = max_of(home - grid_to_home, 0.0)
      solar_remaining = max_of(solar - solar_to_grid, 0.0)

      solar_to_home = min_of(solar_remaining, home_remaining)
      solar_remaining = solar_remaining - solar_to_home
      home_remaining = home_remaining - solar_to_home

      {solar_to_battery, grid_to_battery, battery_to_home} =
        if battery > 0 do
          {solar_remaining,
           min_of(grid_import - grid_to_home, max_of(battery - solar_remaining, 0.0)), 0.0}
        else
          {0.0, 0.0, min_of(-battery, home_remaining)}
        end

      %__MODULE__{
        solar_to_home_w: RubyNumeric.round(solar_to_home, 1),
        solar_to_grid_w: RubyNumeric.round(solar_to_grid, 1),
        solar_to_battery_w: RubyNumeric.round(solar_to_battery, 1),
        grid_to_home_w: RubyNumeric.round(grid_to_home, 1),
        grid_to_battery_w: RubyNumeric.round(grid_to_battery, 1),
        battery_to_home_w: RubyNumeric.round(battery_to_home, 1)
      }
    end

    # Ruby's `[a, b].max` / `.min`: the first of equal values wins (-0.0 vs 0.0).
    defp max_of(a, b), do: RubyNumeric.max([a, b])
    defp min_of(a, b), do: RubyNumeric.min([a, b])
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

  @doc "The state as Rails serialises the struct (`to_json`), keys in attribute order."
  @spec to_json(t) :: String.t()
  def to_json(%__MODULE__{} = flow) do
    flows = for key <- Flows.keys(), do: {key, Map.fetch!(flow.flows, key)}
    pairs = for key <- @keys, do: {key, if(key == :flows, do: flows, else: Map.fetch!(flow, key))}
    RubyJSON.encode!(pairs)
  end

  # dry-types' coercible.float: Integers become Floats, nil stays.
  defp float(nil), do: nil
  defp float(value), do: RubyNumeric.to_f(value)
end
