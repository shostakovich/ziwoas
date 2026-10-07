defmodule Ziwoas.LocalDay do
  @moduledoc false

  @doc "The instant of local midnight. An ambiguous midnight takes the earlier instant, one in a gap the first after it."
  @spec midnight(Date.t(), String.t()) :: DateTime.t()
  def midnight(%Date{} = date, zone) do
    case DateTime.new(date, ~T[00:00:00], zone) do
      {:ok, midnight} -> midnight
      {:ambiguous, earlier, _later} -> earlier
      {:gap, _before, just_after} -> just_after
    end
  end

  @spec midnight_unix(Date.t(), String.t()) :: integer
  def midnight_unix(date, zone), do: date |> midnight(zone) |> DateTime.to_unix()

  @spec window(Date.t(), String.t()) :: {integer, integer}
  def window(date, zone), do: {midnight_unix(date, zone), midnight_unix(Date.add(date, 1), zone)}

  @doc "An ambiguous wall-clock time takes the earlier instant; one in a gap moves forward an hour."
  @spec to_instant(NaiveDateTime.t(), String.t()) :: DateTime.t()
  def to_instant(%NaiveDateTime{} = local, zone) do
    case DateTime.from_naive(local, zone) do
      {:ok, instant} -> instant
      {:ambiguous, earlier, _later} -> earlier
      {:gap, _before, _after} -> to_instant(NaiveDateTime.add(local, 3600), zone)
    end
  end

  @doc "Keeps the wall-clock time, so the span is an hour longer or shorter across a DST change."
  @spec advance_days(DateTime.t(), integer, String.t()) :: DateTime.t()
  def advance_days(%DateTime{} = instant, days, zone) do
    local = DateTime.shift_zone!(instant, zone)
    naive = local |> DateTime.to_naive() |> NaiveDateTime.add(days, :day)

    case DateTime.from_naive(naive, zone) do
      {:ambiguous, earlier, later} ->
        Enum.find([earlier, later], earlier, &(&1.std_offset == local.std_offset))

      _ ->
        to_instant(naive, zone)
    end
    |> DateTime.shift_zone!(instant.time_zone)
  end

  @spec local_time(integer, String.t()) :: DateTime.t()
  def local_time(unix_ts, zone),
    do: unix_ts |> DateTime.from_unix!() |> DateTime.shift_zone!(zone)
end
