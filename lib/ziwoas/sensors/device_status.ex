defmodule Ziwoas.Sensors.DeviceStatus do
  @moduledoc """
  The SEN66's device status register; `fan_speed_warning` is its only warning, every other
  flag an error.
  """

  import Bitwise

  @flags [
    fan_error: 4,
    rht_error: 6,
    gas_error: 7,
    co2_2_error: 9,
    hcho_error: 10,
    pm_error: 11,
    co2_1_error: 12,
    fan_speed_warning: 21
  ]

  @type flag ::
          :fan_error
          | :rht_error
          | :gas_error
          | :co2_2_error
          | :hcho_error
          | :pm_error
          | :co2_1_error
          | :fan_speed_warning

  @spec flags(non_neg_integer | nil) :: [flag]
  def flags(nil), do: []

  def flags(status) when is_integer(status),
    do: for({flag, bit} <- @flags, (status &&& 1 <<< bit) != 0, do: flag)
end
