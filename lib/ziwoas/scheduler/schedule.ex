defmodule Ziwoas.Scheduler.Schedule do
  @moduledoc """
  A job's schedule in a small natural language, on the wall clock of a zone:

    * `every 30 seconds`, `every minute`, `every 2 minutes`, `every hour`,
      `every hour at minute 12` — instants aligned to the local clock
      (`*/N`); DST shifts by whole hours keep the spacing, so the repeated
      autumn hour runs twice and the skipped spring hour not at all;
    * `every 3 hours` — local hours 0, 3, …, 21;
    * `at 3:15am every day`, `every day at 15:45` — once per local day.

  A daily time in the spring gap runs an hour later, an ambiguous one at its
  first occurrence.
  """
  alias Ziwoas.LocalDay

  @enforce_keys [:text, :kind]
  defstruct [:text, :kind, :period, :phase, times: []]

  @type t :: %__MODULE__{
          text: String.t(),
          kind: :interval | :daily,
          period: pos_integer | nil,
          phase: non_neg_integer | nil,
          times: [Time.t()]
        }

  @units %{"second" => 1, "minute" => 60, "hour" => 3600}

  @doc "Parses a schedule; raises `ArgumentError` on anything else."
  @spec parse!(String.t()) :: t
  def parse!(text) do
    words = text |> String.downcase() |> String.split()

    case parse(words) do
      {:interval, period, phase} ->
        %__MODULE__{text: text, kind: :interval, period: period, phase: phase}

      {:daily, times} ->
        %__MODULE__{text: text, kind: :daily, times: times}

      :error ->
        raise ArgumentError, "unsupported schedule #{inspect(text)}"
    end
  end

  defp parse(["every", "hour", "at", "minute", minute]) do
    case Integer.parse(minute) do
      {m, ""} when m in 0..59 -> {:interval, 3600, m * 60}
      _ -> :error
    end
  end

  defp parse(["every", unit]), do: parse(["every", "1", unit <> "s"])

  defp parse(["every", count, unit]) do
    with {n, ""} when n > 0 <- Integer.parse(count),
         {:ok, size} <- Map.fetch(@units, String.trim_trailing(unit, "s")) do
      every(n, size)
    else
      _ -> :error
    end
  end

  defp parse(["at", time, "every", "day"]), do: daily(time)
  defp parse(["every", "day", "at", time]), do: daily(time)
  defp parse(_words), do: :error

  # As in cron's */N: N must divide the unit above, else the cron would not be even.
  defp every(n, 1) when rem(60, n) == 0, do: {:interval, n, 0}
  defp every(n, 60) when rem(60, n) == 0, do: {:interval, n * 60, 0}
  defp every(1, 3600), do: {:interval, 3600, 0}

  defp every(n, 3600) when rem(24, n) == 0,
    do: {:daily, for(hour <- 0..23//n, do: Time.new!(hour, 0, 0))}

  defp every(_n, _size), do: :error

  defp daily(text) do
    case Regex.run(~r/\A(\d{1,2}):(\d{2})(am|pm)?\z/, text) do
      [_, hour, minute | meridiem] ->
        hour = String.to_integer(hour)
        minute = String.to_integer(minute)

        with {:ok, hour} <- hour_24(hour, meridiem),
             {:ok, time} <- Time.new(hour, minute, 0),
             do: {:daily, [time]},
             else: (_ -> :error)

      nil ->
        :error
    end
  end

  defp hour_24(hour, []) when hour in 0..23, do: {:ok, hour}
  defp hour_24(12, ["am"]), do: {:ok, 0}
  defp hour_24(hour, ["am"]) when hour in 1..11, do: {:ok, hour}
  defp hour_24(12, ["pm"]), do: {:ok, 12}
  defp hour_24(hour, ["pm"]) when hour in 1..11, do: {:ok, hour + 12}
  defp hour_24(_hour, _meridiem), do: :error

  @doc "The first instant strictly after `instant` at which the schedule falls due."
  @spec next_after(t, DateTime.t(), String.t()) :: DateTime.t()
  def next_after(%__MODULE__{kind: :interval, period: period, phase: phase}, instant, zone) do
    from = DateTime.to_unix(instant)
    offset = offset(from, zone)
    due = from + period - Integer.mod(from + offset - phase, period)
    DateTime.from_unix!(due)
  end

  # Tomorrow's first time always lies ahead; yesterday's can, pushed out of a gap.
  def next_after(%__MODULE__{kind: :daily, times: times}, instant, zone) do
    today = instant |> DateTime.shift_zone!(zone) |> DateTime.to_date()

    for day <- -1..1,
        time <- times,
        due = today |> Date.add(day) |> NaiveDateTime.new!(time) |> LocalDay.to_instant(zone),
        DateTime.after?(due, instant) do
      DateTime.shift_zone!(due, "Etc/UTC")
    end
    |> Enum.min(DateTime)
  end

  defp offset(unix, zone) do
    local = unix |> DateTime.from_unix!() |> DateTime.shift_zone!(zone)
    local.utc_offset + local.std_offset
  end
end
