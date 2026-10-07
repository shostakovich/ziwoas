defmodule Ziwoas.SunCalendar.SunLines do
  @moduledoc """
  Sunrise, sunset and solar noon over a whole year, in local clock hours.
  On a daylight saving change the previous offset's value comes first, so the
  line steps by one hour where the clock does instead of ramping across it.
  """
  alias Ziwoas.{LocalDay, Location, Sun}
  alias Ziwoas.SunCalendar.Lines

  @seconds_per_hour 3600
  @seconds_per_day 86_400

  @spec build(Location.t(), integer) :: Lines.t()
  def build(location, year) do
    {rise, set, noon, _previous} =
      Date.range(Date.new!(year, 1, 1), Date.new!(year, 12, 31))
      |> Enum.reduce({[], [], [], nil}, &add_day(location, &1, &2))

    %Lines{rise: Enum.reverse(rise), set: Enum.reverse(set), noon: Enum.reverse(noon)}
  end

  defp add_day(location, date, {rise, set, noon, previous_offset}) do
    offset = utc_offset(location, date)
    seam = if previous_offset && previous_offset != offset, do: previous_offset

    case events(location, date) do
      nil ->
        {rise, set, noon, offset}

      events ->
        doy = Date.day_of_year(date)

        [seam, offset]
        |> Enum.reject(&is_nil/1)
        |> Enum.reduce({rise, set, noon, offset}, &add_events(events, doy, &1, &2))
    end
  end

  defp add_events(events, doy, with_offset, {rise, set, noon, offset}) do
    [first, last] = Enum.map(events, &local_hour(&1, with_offset))
    {[{doy, first} | rise], [{doy, last} | set], [{doy, (first + last) / 2} | noon], offset}
  end

  defp events(location, date) do
    with %DateTime{} = sunrise <- Sun.sunrise(location, date),
         %DateTime{} = sunset <- Sun.sunset(location, date),
         do: [sunrise, sunset]
  end

  defp local_hour(time, offset),
    do: Integer.mod(DateTime.to_unix(time) + offset, @seconds_per_day) / @seconds_per_hour

  # Read at local noon: a change happens at night, so both events of the day
  # already sit on the new offset.
  defp utc_offset(location, date) do
    noon = LocalDay.to_instant(NaiveDateTime.new!(date, ~T[12:00:00]), location.timezone)
    noon.utc_offset + noon.std_offset
  end
end
