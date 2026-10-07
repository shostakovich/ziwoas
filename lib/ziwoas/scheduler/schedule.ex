defmodule Ziwoas.Scheduler.Schedule do
  @moduledoc """
  When a job falls due, on the wall clock of a zone:

    * `{:every, n, :second | :minute}` — instants aligned to the local clock
      (`*/n`, so `n` divides 60); DST shifts by whole hours keep the spacing,
      so the repeated autumn hour runs twice and the skipped spring hour not
      at all;
    * `{:every, 1, :hour}` — every full hour, likewise;
    * `{:every, n, :hour}` — local hours 0, n, 2n, … (`n` divides 24);
    * `{:daily, ~T[03:15:00]}` — once per local day.

  A daily time in the spring gap runs an hour later, an ambiguous one at its
  first occurrence.
  """
  alias Ziwoas.LocalDay

  @type unit :: :second | :minute | :hour
  @type t :: {:every, pos_integer, unit} | {:daily, Time.t()}

  @doc "Whether `next_after/3` takes `schedule`."
  @spec valid?(term) :: boolean
  def valid?(schedule), do: rule(schedule) != :error

  @doc "The first instant strictly after `instant` at which `schedule` falls due."
  @spec next_after(t, DateTime.t(), String.t()) :: DateTime.t()
  def next_after(schedule, instant, zone) do
    case rule(schedule) do
      {:interval, period} -> next_interval(period, instant, zone)
      {:daily, times} -> next_daily(times, instant, zone)
      :error -> raise ArgumentError, "unsupported schedule #{inspect(schedule)}"
    end
  end

  # As in cron's */n: n must divide the unit above, else the cron would not be even.
  defp rule({:every, n, :second}) when is_integer(n) and n > 0 and rem(60, n) == 0,
    do: {:interval, n}

  defp rule({:every, n, :minute}) when is_integer(n) and n > 0 and rem(60, n) == 0,
    do: {:interval, n * 60}

  defp rule({:every, 1, :hour}), do: {:interval, 3600}

  defp rule({:every, n, :hour}) when is_integer(n) and n > 0 and rem(24, n) == 0,
    do: {:daily, for(hour <- 0..23//n, do: Time.new!(hour, 0, 0))}

  defp rule({:daily, %Time{} = time}), do: {:daily, [time]}
  defp rule(_schedule), do: :error

  defp next_interval(period, instant, zone) do
    from = DateTime.to_unix(instant)
    due = from + period - Integer.mod(from + offset(from, zone), period)
    DateTime.from_unix!(due)
  end

  # Tomorrow's first time always lies ahead; yesterday's can, pushed out of a gap.
  defp next_daily(times, instant, zone) do
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
