defmodule Ziwoas.Switching.Edges do
  @moduledoc """
  Pure edge computation: no I/O, no clock. One
  rule, one edge — a rule carries its weekdays absolutely, so nothing here
  knows about midnight.
  """
  alias Ziwoas.Switching.Rule

  defmodule Edge do
    @moduledoc "A switch time falling due: rule plus local instant."
    @enforce_keys [:plug_id, :rule_id, :action, :at]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            plug_id: String.t(),
            rule_id: integer,
            action: :on | :off,
            at: DateTime.t()
          }
  end

  # :off sorts before :on, so "last edge wins" resolves a tie towards on.
  @action_order %{off: 0, on: 1}

  @doc "All edges with `from < at <= to`, ascending by time, in `zone`."
  @spec edges_between([Rule.t()], DateTime.t(), DateTime.t(), String.t()) :: [Edge.t()]
  def edges_between(rules, from, to, zone) do
    if DateTime.compare(to, from) != :gt do
      []
    else
      first = from |> DateTime.shift_zone!(zone) |> DateTime.to_date()
      last = to |> DateTime.shift_zone!(zone) |> DateTime.to_date()

      Date.range(first, last)
      |> Enum.flat_map(&edges_for_date(rules, &1, zone))
      |> Enum.filter(
        &(DateTime.compare(&1.at, from) == :gt and DateTime.compare(&1.at, to) != :gt)
      )
      |> Enum.sort_by(&{DateTime.to_unix(&1.at, :microsecond), @action_order[&1.action]})
    end
  end

  @doc "At most one edge per plug: the latest within the interval (the tick's edge)."
  @spec latest_edge_per_plug([Rule.t()], DateTime.t(), DateTime.t(), String.t()) :: [Edge.t()]
  def latest_edge_per_plug(rules, from, to, zone) do
    rules
    |> edges_between(from, to, zone)
    |> Enum.chunk_by(& &1.plug_id)
    |> group_in_order()
    |> Enum.map(&List.last/1)
  end

  @doc """
  At most one edge per plug, the earliest within the interval; among edges
  sharing that instant the one "last edge wins" would pick.
  """
  @spec next_edge_per_plug([Rule.t()], DateTime.t(), DateTime.t(), String.t()) :: [Edge.t()]
  def next_edge_per_plug(rules, from, to, zone) do
    rules
    |> edges_between(from, to, zone)
    |> Enum.chunk_by(& &1.plug_id)
    |> group_in_order()
    |> Enum.map(&tie_winner/1)
  end

  # Enumerable#group_by over the sorted edges.
  defp group_in_order(chunks) do
    chunks
    |> Enum.reduce({[], %{}}, fn [%{plug_id: id} | _] = chunk, {ids, groups} ->
      ids = if Map.has_key?(groups, id), do: ids, else: [id | ids]
      {ids, Map.update(groups, id, chunk, &(&1 ++ chunk))}
    end)
    |> then(fn {ids, groups} -> ids |> Enum.reverse() |> Enum.map(&Map.fetch!(groups, &1)) end)
  end

  defp tie_winner([first | _] = edges),
    do: edges |> Enum.take_while(&(DateTime.compare(&1.at, first.at) == :eq)) |> List.last()

  defp edges_for_date(rules, date, zone) do
    cwday = Date.day_of_week(date)

    for rule <- rules, cwday in rule.days do
      %Edge{
        plug_id: rule.plug_id,
        rule_id: rule.id,
        action: rule.action,
        at: local_time(date, rule.at_minute, zone)
      }
    end
  end

  # An ambiguous time takes the earlier (summer) offset, a time inside a
  # spring-forward gap is read with the offset before it.
  defp local_time(date, minutes, zone) do
    naive = NaiveDateTime.new!(date, Time.new!(div(minutes, 60), rem(minutes, 60), 0))

    case DateTime.from_naive(naive, zone) do
      {:ok, datetime} ->
        datetime

      {:ambiguous, earlier, _later} ->
        earlier

      {:gap, just_before, _just_after} ->
        naive
        |> NaiveDateTime.add(-(just_before.utc_offset + just_before.std_offset))
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.shift_zone!(zone)
    end
  end
end
