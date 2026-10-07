defmodule Ziwoas.Switching.Row do
  @moduledoc """
  One switchable plug on the Schalten page: its schedule
  folded into entries, its relay state, the latest command, the next edge
  within a week and its latest measurement.
  """
  import Ecto.Query

  alias Ziwoas.Repo
  alias Ziwoas.Plugs.{Plug, State}
  alias Ziwoas.Switching.{Command, EdgeCalculator, Rule, Schedule}

  @lookahead_s 7 * 24 * 3600
  @offline_after_s 120

  @enforce_keys [:plug, :entries, :state, :last_command, :next_edge, :watt, :last_seen_ts, :now]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          plug: Plug.t(),
          entries: [Schedule.entry()],
          state: State.t() | nil,
          last_command: Command.t() | nil,
          next_edge: EdgeCalculator.Edge.t() | nil,
          watt: float | nil,
          last_seen_ts: integer | nil,
          now: DateTime.t()
        }

  @spec build_all([Plug.t()], DateTime.t(), String.t()) :: [t]
  def build_all(plugs, now, zone) do
    ids = Enum.map(plugs, & &1.id)

    rules =
      Repo.all(from r in Rule, where: r.plug_id in ^ids, order_by: [r.at_minute, r.id])
      |> Enum.group_by(& &1.plug_id)

    states = Map.new(Repo.all(from s in State, where: s.plug_id in ^ids), &{&1.plug_id, &1})
    commands = latest_commands(ids)
    samples = latest_samples(ids)
    until = DateTime.add(now, @lookahead_s)

    for plug <- plugs do
      plug_rules = Map.get(rules, plug.id, [])
      {last_seen_ts, watt} = Map.get(samples, plug.id, {nil, nil})

      %__MODULE__{
        plug: plug,
        entries: Schedule.fold(plug_rules),
        state: states[plug.id],
        last_command: commands[plug.id],
        next_edge:
          plug_rules
          |> Enum.filter(& &1.enabled)
          |> EdgeCalculator.next_edge_per_plug(now, until, zone)
          |> List.first(),
        watt: watt,
        last_seen_ts: last_seen_ts,
        now: now
      }
    end
  end

  @spec build(Plug.t(), DateTime.t(), String.t()) :: t
  def build(plug, now, zone), do: hd(build_all([plug], now, zone))

  @doc "Seconds since the latest sample, nil without one."
  @spec age(t) :: float | nil
  def age(%__MODULE__{last_seen_ts: nil}), do: nil

  def age(%__MODULE__{last_seen_ts: ts, now: now}),
    do: DateTime.diff(now, DateTime.from_unix!(ts), :microsecond) / 1_000_000

  @spec offline?(t) :: boolean
  def offline?(row) do
    age = age(row)
    is_nil(age) or age > @offline_after_s
  end

  @doc """
  The fresher signal wins: a command newer than the last confirmed device state
  shows optimistically until the Shelly status message catches up.
  """
  @spec on?(t) :: boolean
  def on?(%__MODULE__{last_command: command, state: state}) do
    cond do
      command && fresher?(command, state) -> command.action == "on"
      state -> state.output
      true -> false
    end
  end

  defp fresher?(_command, nil), do: true
  defp fresher?(_command, %State{updated_at: nil}), do: true

  defp fresher?(command, state),
    do: DateTime.compare(command.inserted_at, state.updated_at) != :lt

  @doc "Schaltzeiten, not rows: a Zeitfenster is one row and two of them."
  @spec rule_count(t) :: non_neg_integer
  def rule_count(%__MODULE__{entries: entries}),
    do: entries |> Enum.map(&length(Schedule.rules(&1))) |> Enum.sum()

  # Each plug's newest command: of the commands at its newest inserted_at, the last
  # by id wins.
  defp latest_commands([]), do: %{}

  defp latest_commands(ids) do
    newest =
      from c in Command,
        where: c.plug_id in ^ids,
        group_by: c.plug_id,
        select: %{plug_id: c.plug_id, inserted_at: max(c.inserted_at)}

    from(c in Command,
      join: n in subquery(newest),
      on: n.plug_id == c.plug_id and n.inserted_at == c.inserted_at,
      order_by: [c.inserted_at, c.id]
    )
    |> Repo.all()
    |> Map.new(&{&1.plug_id, &1})
  end

  # The newest sample's ts and watts per plug.
  defp latest_samples([]), do: %{}

  defp latest_samples(ids) do
    marks = Enum.map_join(ids, ", ", fn _ -> "?" end)

    %{rows: rows} =
      Repo.query!(
        "SELECT plug_id, ts, apower_w FROM samples WHERE plug_id IN (#{marks}) " <>
          "AND (plug_id, ts) IN (SELECT plug_id, MAX(ts) FROM samples " <>
          "WHERE plug_id IN (#{marks}) GROUP BY plug_id)",
        ids ++ ids
      )

    Map.new(rows, fn [plug_id, ts, apower_w] -> {plug_id, {ts, to_float(apower_w)}} end)
  end

  defp to_float(nil), do: nil
  defp to_float(value), do: value * 1.0
end
