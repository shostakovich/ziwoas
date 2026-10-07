defmodule Ziwoas.LocalDay do
  @moduledoc """
  A calendar day in a time zone, as Rails' `date.in_time_zone(zone)` up to
  `+ 1.day` sees it: local midnight to the next local midnight, so 23 or 25
  hours long on DST days.
  """

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

  @doc "`{start_ts, end_ts}` in Unix seconds, end exclusive."
  @spec window(Date.t(), String.t()) :: {integer, integer}
  def window(date, zone), do: {midnight_unix(date, zone), midnight_unix(Date.add(date, 1), zone)}

  @doc """
  The instant of a local wall-clock time, as ActiveSupport resolves it
  (`zone.local`, `TimeZone#local_to_utc` with `dst = true`): an ambiguous
  time takes the earlier (summer-time) instant; one in a gap moves forward
  an hour (`TimeWithZone` adds 1 h until valid: 02:30 → 03:30).
  """
  @spec to_instant(NaiveDateTime.t(), String.t()) :: DateTime.t()
  def to_instant(%NaiveDateTime{} = local, zone) do
    case DateTime.from_naive(local, zone) do
      {:ok, instant} -> instant
      {:ambiguous, earlier, _later} -> earlier
      {:gap, _before, _after} -> to_instant(NaiveDateTime.add(local, 3600), zone)
    end
  end

  @doc """
  `instant` moved by whole calendar days on the local clock, as
  `TimeWithZone#advance(days:)` (`now - 7.days`): the wall-clock time stays,
  so the span is 23 or 25 hours longer or shorter across a DST change. An
  ambiguous result keeps `instant`'s offset when it can, a gap moves forward
  an hour.
  """
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
