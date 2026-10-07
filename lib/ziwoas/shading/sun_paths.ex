defmodule Ziwoas.Shading.SunPaths do
  @moduledoc false
  alias Ziwoas.Shading.{Dot, Path}
  alias Ziwoas.Sun

  # The equinox stands for both: March's path is September's.
  @dates [summer_solstice: {6, 21}, equinox: {9, 23}, winter_solstice: {12, 21}]
  @dot_hours [6, 9, 12, 15, 18]

  @spec build(Ziwoas.Location.t(), integer) :: [Path.t()]
  def build(location, year) do
    for {key, {month, day}} <- @dates,
        waypoints = Sun.path(location, Date.new!(year, month, day)),
        waypoints != [] do
      %Path{
        day: key,
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
