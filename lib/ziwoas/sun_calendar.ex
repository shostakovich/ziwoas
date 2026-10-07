defmodule Ziwoas.SunCalendar do
  @moduledoc """
  A year of the PV plant hour by hour: PV power, irradiance and cloud cover as
  strips of day × local hour, the daily energy, and the lines of sunrise,
  sunset and solar noon.
  """
  @base_hours {3, 22}

  def base_hours, do: @base_hours

  defmodule Strip do
    @moduledoc "`values` is keyed by `{day of year, local clock hour}`."
    defstruct [:key, :title, :unit, :ramp, :max, :values]
  end

  defmodule Day do
    @moduledoc false
    defstruct [:doy, :date, :pv_kwh, :irradiance_kwh_per_m2, :cloud_avg]
  end

  defmodule Lines do
    @moduledoc "Points are `{day of year, local hour}`."
    defstruct [:rise, :set, :noon]

    def empty?(%__MODULE__{rise: rise}), do: rise == []
  end

  defmodule Year do
    @moduledoc "`strips` in drawing order: PV, irradiance, cloud cover."
    defstruct [:year, :days, :hours, :strips, :max_kwh, :lines, :seam]

    def empty?(%__MODULE__{strips: [pv | _]}), do: pv.values == %{}
  end
end
