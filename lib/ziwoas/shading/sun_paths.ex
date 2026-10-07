defmodule Ziwoas.Shading.SunPaths do
  @moduledoc "The sun's way across the sky on the solstices and the equinox, with dots every three hours."
  alias Ziwoas.Shading.{Dot, Path}
  alias Ziwoas.Sun

  @dates [{"21.6.", {6, 21}}, {"21.3. / 23.9.", {9, 23}}, {"21.12.", {12, 21}}]
  @dot_hours [6, 9, 12, 15, 18]

  @spec build(Ziwoas.Location.t(), integer) :: [Path.t()]
  def build(location, year) do
    for {label, {month, day}} <- @dates,
        waypoints = Sun.path(location, Date.new!(year, month, day)),
        waypoints != [] do
      %Path{
        label: label,
        points: Enum.map(waypoints, &{&1.azimuth, &1.elevation}),
        dots:
          for(
            waypoint <- waypoints,
            hour = trunc(waypoint.hour),
            waypoint.hour == hour and hour in @dot_hours,
            do: %Dot{hour: hour, azimuth: waypoint.azimuth, elevation: waypoint.elevation}
          )
      }
    end
  end
end
