defmodule Ziwoas.Sun do
  @moduledoc """
  The sun as the house sees it. A location with coordinates computes it
  (`Ziwoas.Sun.Position`); one without answers nothing, and always day, so no
  reader has to ask whether coordinates were configured.
  """
  alias Ziwoas.{LocalDay, Location}
  alias Ziwoas.Sun.Position

  # How finely a sun path is sampled: fine enough that the curve reads as a
  # curve and that the full hours fall on a sample.
  @step_hours 0.25

  defmodule Waypoint do
    @moduledoc "One point of a sun path: where the sun stood, and how many hours after local midnight."
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

  @doc "Local time of sunrise, or nil on a polar day or night and without coordinates."
  @spec sunrise(Location.t(), Date.t()) :: DateTime.t() | nil
  def sunrise(location, date), do: event(location, date, &Position.sunrise/3)

  @spec sunset(Location.t(), Date.t()) :: DateTime.t() | nil
  def sunset(location, date), do: event(location, date, &Position.sunset/3)

  @doc "Without coordinates it is day: a weather icon has to pick one, and day is what an unplaced house showed."
  @spec daytime?(Location.t(), DateTime.t()) :: boolean
  def daytime?(%Location{} = location, time) do
    not known?(location) or Position.daytime?(time, location.lat, location.lon, location.timezone)
  end

  @doc """
  Where the sun stands above the horizon through a local day, every quarter
  hour. Hours count elapsed time from local midnight (96 steps even on
  23- and 25-hour days), not wall-clock time.
  """
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
