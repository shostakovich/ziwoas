defmodule Ziwoas.Heating.Decision do
  @moduledoc """
  What a heater should do now: every change of state is an edge and the latest edge wins
  (ADR-0001, without its grace). Window starts heat and window ends switch to frost
  protection; a press sets its state; four hours after manual heating began and every evening
  at 22:00 it switches to frost protection. Each of the frost edges but a press is skipped while
  a window is active, so overlapping windows heat as one.
  """
  alias Ziwoas.Heating.Window
  alias Ziwoas.LocalDay

  @enforce_keys [:state, :cause, :until]
  defstruct @enforce_keys

  @type state :: :heat | :frost
  @type cause :: :window | :manual | :cap | :evening | nil

  @typedoc "`until` is the next edge that changes the state, within a week."
  @type t :: %__MODULE__{state: state, cause: cause, until: DateTime.t() | nil}

  @type press :: {state, DateTime.t()}

  @evening_minute 22 * 60
  @manual_cap_s 4 * 3600
  @lookback_days 8
  @lookahead_s 7 * 24 * 3600

  @spec decide([Window.t()], press | nil, DateTime.t(), String.t()) :: t
  def decide(windows, press, now, zone) do
    horizon = DateTime.add(now, @lookahead_s)
    first = now |> DateTime.add(-@lookback_days * 86_400) |> LocalDay.date(zone)
    days = Date.range(first, LocalDay.date(horizon, zone))
    intervals = intervals(Enum.filter(windows, & &1.enabled), days, zone)

    edges =
      (window_edges(intervals) ++ evening_edges(days, zone) ++ manual_edges(press))
      |> Enum.reject(fn {_kind, _state, at} -> DateTime.compare(at, horizon) == :gt end)
      |> Enum.sort_by(fn {kind, state, at} ->
        {DateTime.to_unix(at, :microsecond), rank(kind, state)}
      end)

    {past, future} =
      Enum.split_with(edges, fn {_kind, _state, at} -> DateTime.compare(at, now) != :gt end)

    current = Enum.reduce(past, %{state: :frost, cause: nil}, &apply_edge(&1, &2, intervals))

    %__MODULE__{
      state: current.state,
      cause: current.cause,
      until: next_change(future, current, intervals)
    }
  end

  # Per instant, frost edges first, so a window starting as another ends keeps heating.
  defp rank(:manual, _state), do: 2
  defp rank(_kind, :heat), do: 1
  defp rank(_kind, :frost), do: 0

  defp next_change(future, current, intervals) do
    future
    |> Enum.reduce_while(current, fn {_kind, _state, at} = edge, acc ->
      next = apply_edge(edge, acc, intervals)
      if next.state != current.state, do: {:halt, {:changed, at}}, else: {:cont, next}
    end)
    |> case do
      {:changed, at} -> DateTime.shift_zone!(at, "Etc/UTC")
      _unchanged -> nil
    end
  end

  defp apply_edge({kind, :frost, at}, acc, intervals) when kind != :manual do
    if active?(intervals, at), do: acc, else: %{state: :frost, cause: kind}
  end

  defp apply_edge({kind, state, _at}, _acc, _intervals), do: %{state: state, cause: kind}

  defp active?(intervals, at),
    do:
      Enum.any?(intervals, fn {start, stop} ->
        DateTime.compare(start, at) != :gt and DateTime.compare(at, stop) == :lt
      end)

  # A window starting the day before the first day can still be running on it; one the spring
  # gap leaves without time is skipped.
  defp intervals(windows, days, zone) do
    for date <- Date.range(Date.add(days.first, -1), days.last),
        window <- windows,
        Date.day_of_week(date) in window.days,
        stop_date = if(window.off_minute > window.on_minute, do: date, else: Date.add(date, 1)),
        start = local(date, window.on_minute, zone),
        stop = local(stop_date, window.off_minute, zone),
        DateTime.compare(start, stop) == :lt,
        do: {start, stop}
  end

  defp window_edges(intervals),
    do:
      Enum.flat_map(intervals, fn {start, stop} ->
        [{:window, :heat, start}, {:window, :frost, stop}]
      end)

  defp evening_edges(days, zone),
    do: for(date <- days, do: {:evening, :frost, local(date, @evening_minute, zone)})

  defp manual_edges(nil), do: []

  defp manual_edges({:heat, at}),
    do: [{:manual, :heat, at}, {:cap, :frost, DateTime.add(at, @manual_cap_s)}]

  defp manual_edges({:frost, at}), do: [{:manual, :frost, at}]

  defp local(date, minute, zone),
    do:
      date
      |> NaiveDateTime.new!(Time.new!(div(minute, 60), rem(minute, 60), 0))
      |> LocalDay.to_instant(zone)
end
