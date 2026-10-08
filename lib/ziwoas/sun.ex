defmodule Ziwoas.Sun do
  @moduledoc false
  alias Ziwoas.{LocalDay, Location}
  alias Ziwoas.Sun.Position

  @step_hours 0.25

  defmodule Waypoint do
    @moduledoc false
    @enforce_keys [:hour, :azimuth, :elevation]
    defstruct @enforce_keys

    @type t :: %__MODULE__{hour: float, azimuth: float, elevation: float}
  end

  @spec known?(Location.t()) :: boolean
  def known?(location), do: Location.located?(location)

  @spec position(Location.t(), DateTime.t()) :: Position.t() | nil
  def position(%Location{} = location, time) do
    if known?(location), do: Position.at(time, location.lat, location.lon)
  end

  @spec sunrise(Location.t(), Date.t()) :: DateTime.t() | nil
  def sunrise(location, date), do: event(location, date, &Position.sunrise/3)

  @spec sunset(Location.t(), Date.t()) :: DateTime.t() | nil
  def sunset(location, date), do: event(location, date, &Position.sunset/3)

  @doc "Without coordinates it is day."
  @spec daytime?(Location.t(), DateTime.t()) :: boolean
  def daytime?(%Location{} = location, time) do
    not known?(location) or Position.daytime?(time, location.lat, location.lon, location.timezone)
  end

  @spec path(Location.t(), Date.t()) :: [Waypoint.t()]
  def path(%Location{} = location, date) do
    if known?(location) do
      midnight = LocalDay.midnight(date, location.timezone)

      for step <- 0..round(24 / @step_hours - 1),
          hour = step * @step_hours,
          at =
            Position.at(
              DateTime.add(midnight, round(hour * 3600)),
              location.lat,
              location.lon
            ),
          at.elevation > 0,
          do: %Waypoint{hour: hour, azimuth: at.azimuth, elevation: at.elevation}
    else
      []
    end
  end

  defp event(%Location{} = location, date, calc) do
    if known?(location) do
      case calc.(date, location.lat, location.lon) do
        nil -> nil
        utc -> DateTime.shift_zone!(utc, location.timezone)
      end
    end
  end
end
