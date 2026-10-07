defmodule Ziwoas.Shading.ClearSky do
  @moduledoc "Clear-sky global radiation after Haurwitz (1945)."
  @peak_w_per_m2 1098.0
  @extinction 0.059

  @spec w_per_m2(number) :: float
  def w_per_m2(elevation_deg) do
    cos_zenith = :math.sin(elevation_deg * :math.pi() / 180.0)

    if cos_zenith <= 0,
      do: 0.0,
      else: @peak_w_per_m2 * cos_zenith * :math.exp(-@extinction / cos_zenith)
  end
end
