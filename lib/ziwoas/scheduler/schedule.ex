defmodule Ziwoas.Scheduler.Schedule do
  @moduledoc "Aligned to the local clock: the repeated autumn hour runs twice, the skipped spring hour not at all."
  alias Ziwoas.LocalDay

  @type unit :: :second | :minute | :hour
  @type t :: {:every, pos_integer, unit} | {:daily, Time.t()}

  @spec valid?(term) :: boolean
  def valid?(schedule), do: rule(schedule) != :error

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
