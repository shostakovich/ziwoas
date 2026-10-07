defmodule Ziwoas.Switching do
  @moduledoc """
  Switching the switchable plugs: their schedule — Zeitfenster (two rules in a
  group) and Einzelschaltungen (one rule) — with its forms and writes, the rows
  of the Schalten page, the switch commands and the schedule tick's watermarks.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Ziwoas.{Clock, Plugs, Repo}
  alias Ziwoas.Plugs.Plug
  alias Ziwoas.Switching.{Command, Commander, EdgeCalculator, Row, Rule, SchedulerState}
  alias Ziwoas.Switching.{Schedule, Window}

  @lookahead_s 7 * 24 * 3600

  # --- Rows ---------------------------------------------------------------------------

  @doc """
  One row per plug as of `now`: its schedule folded into entries, its relay state,
  the latest command, the next edge within a week and its latest measurement.
  """
  @spec rows([Plug.t()], DateTime.t(), String.t()) :: [Row.t()]
  def rows(plugs, now, zone) do
    ids = Enum.map(plugs, & &1.id)

    rules =
      Repo.all(from r in Rule, where: r.plug_id in ^ids, order_by: [r.at_minute, r.id])
      |> Enum.group_by(& &1.plug_id)

    states =
      Map.new(Repo.all(from s in Plugs.State, where: s.plug_id in ^ids), &{&1.plug_id, &1})

    commands = latest_commands(ids)
    measurements = Plugs.latest_measurements(ids, now)
    until = DateTime.add(now, @lookahead_s)

    for plug <- plugs do
      plug_rules = Map.get(rules, plug.id, [])
      measurement = measurements[plug.id]

      %Row{
        plug: plug,
        entries: Schedule.fold(plug_rules),
        state: states[plug.id],
        last_command: commands[plug.id],
        next_edge:
          plug_rules
          |> Enum.filter(& &1.enabled)
          |> EdgeCalculator.next_edge_per_plug(now, until, zone)
          |> List.first(),
        watt: measurement.watt,
        last_seen_ts: measurement.last_seen_ts,
        offline: measurement.offline,
        now: now
      }
    end
  end

  @spec row(Plug.t(), DateTime.t(), String.t()) :: Row.t()
  def row(plug, now, zone), do: hd(rows([plug], now, zone))

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

  # --- Commands -----------------------------------------------------------------------

  @doc "Switches the plug and logs the command once it went out (`Commander.switch/4`)."
  @spec switch(Plug.t(), Command.action(), Command.source(), Ziwoas.Config.Mqtt.t()) ::
          {:ok, Command.t()} | {:error, Commander.error()}
  defdelegate switch(plug, action, source, mqtt), to: Commander

  @doc "Whether a manual command for the plug came after `time`."
  @spec manual_after?(String.t(), DateTime.t()) :: boolean
  def manual_after?(plug_id, time) do
    Repo.exists?(
      from c in Command,
        where: c.plug_id == ^plug_id and c.source == :manual and c.inserted_at > ^time
    )
  end

  # --- Schedule tick ------------------------------------------------------------------

  @doc "The enabled rules of these plugs, by plug id."
  @spec enabled_rules([String.t()]) :: %{String.t() => [Rule.t()]}
  def enabled_rules(plug_ids) do
    Repo.all(from r in Rule, where: r.enabled == true and r.plug_id in ^plug_ids)
    |> Enum.group_by(& &1.plug_id)
  end

  @doc "When the scheduler last worked through the plug's edges, nil before the first tick."
  @spec last_tick_at(String.t()) :: DateTime.t() | nil
  def last_tick_at(plug_id),
    do: Repo.one(from s in SchedulerState, where: s.plug_id == ^plug_id, select: s.last_tick_at)

  @doc "Moves the plug's watermark to `time`, creating the row; no write when nothing changes."
  @spec advance_tick!(String.t(), DateTime.t()) :: SchedulerState.t()
  def advance_tick!(plug_id, time) do
    (Repo.get_by(SchedulerState, plug_id: plug_id) || %SchedulerState{plug_id: plug_id})
    |> Changeset.change(last_tick_at: time)
    |> Repo.insert_or_update!()
  end

  # --- Schedule -----------------------------------------------------------------------

  @doc "The rules of one group on one plug."
  @spec group(String.t(), String.t()) :: [Rule.t()]
  def group(plug_id, group_id),
    do: Repo.all(from r in Rule, where: r.plug_id == ^plug_id and r.group_id == ^group_id)

  # Both halves or nothing: a group that lost one is shown and edited as an
  # Einzelschaltung instead.
  defp halves(rules) do
    on = Enum.find(rules, &(&1.action == :on))
    off = Enum.find(rules, &(&1.action == :off))
    if on && off, do: {on, off}
  end

  @doc "The Zeitfenster `group_id` names on this plug as its form, nil without both halves."
  @spec window(String.t(), String.t()) :: Window.t() | nil
  def window(plug_id, group_id) do
    with {on, off} <- halves(group(plug_id, group_id)),
         do: Window.from_rules(group_id, on, off)
  end

  @doc """
  The Einzelschaltung `id` names on this plug — nil for a rule that is one
  half of an intact Zeitfenster, which only moves together with its partner.
  """
  @spec single(String.t(), term) :: Rule.t() | nil
  def single(plug_id, id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %Rule{} = rule <- Repo.one(from r in Rule, where: r.plug_id == ^plug_id and r.id == ^id),
         false <- half_of_a_window?(rule) do
      rule
    else
      _ -> nil
    end
  end

  defp half_of_a_window?(%Rule{group_id: nil}), do: false

  defp half_of_a_window?(%Rule{group_id: group_id}),
    do: Repo.aggregate(from(r in Rule, where: r.group_id == ^group_id), :count) == 2

  @doc "The Zeitfenster form's changeset; nil is a new one."
  @spec change_window(Window.t() | nil, map) :: Changeset.t()
  def change_window(window \\ nil, attrs \\ %{}),
    do: Window.changeset(window || %Window{}, attrs)

  @doc """
  Writes a Zeitfenster: two rules, one group, one transaction. An off time
  before the on time shifts the off rule's weekdays one day forward. With
  `group_id` the existing halves are updated in place.
  """
  @spec save_window(String.t(), map, String.t() | nil) ::
          {:ok, String.t()} | {:error, Changeset.t()}
  def save_window(plug_id, attrs, group_id \\ nil) do
    changeset = change_window(%Window{group_id: group_id}, attrs)

    with {:ok, window} <- Changeset.apply_action(changeset, :insert) do
      group_id = group_id || Ecto.UUID.generate()
      on_minute = Rule.minutes_from(window.on_at_time)
      off_minute = Rule.minutes_from(window.off_at_time)

      Repo.transaction(fn ->
        write_half(plug_id, group_id, :on, on_minute, window.days)
        write_half(plug_id, group_id, :off, off_minute, Window.off_days(window))
      end)

      {:ok, group_id}
    end
  end

  defp write_half(plug_id, group_id, action, at_minute, days) do
    rule = Repo.one(from r in Rule, where: r.group_id == ^group_id and r.action == ^action)

    (rule || %Rule{group_id: group_id, action: action})
    |> Rule.changeset(%{plug_id: plug_id, at_minute: at_minute, days: days})
    |> Repo.insert_or_update!()
  end

  @doc "The Einzelschaltung form's changeset; nil is a new one."
  @spec change_single(Rule.t() | nil, map) :: Changeset.t()
  def change_single(rule \\ nil, attrs \\ %{}),
    do: (rule || %Rule{}) |> Rule.for_form() |> Rule.form_changeset(attrs)

  @doc "Writes an Einzelschaltung: one rule, no group."
  @spec save_single(String.t(), map, Rule.t() | nil) :: {:ok, Rule.t()} | {:error, Changeset.t()}
  def save_single(plug_id, attrs, rule \\ nil) do
    rule
    |> change_single(attrs)
    |> Changeset.put_change(:plug_id, plug_id)
    |> Changeset.validate_required([:plug_id])
    |> Repo.insert_or_update()
  end

  @doc "Pauses or resumes `rules` together — both halves of a Zeitfenster always move as one."
  @spec set_enabled([Rule.t()], boolean) :: :ok
  def set_enabled(rules, enabled) when is_boolean(enabled) do
    ids = Enum.map(rules, & &1.id)

    Repo.update_all(from(r in Rule, where: r.id in ^ids),
      set: [enabled: enabled, updated_at: Clock.now()]
    )

    :ok
  end

  @doc "Deletes `rules`."
  @spec delete_rules([Rule.t()]) :: :ok
  def delete_rules(rules) do
    ids = Enum.map(rules, & &1.id)
    Repo.delete_all(from r in Rule, where: r.id in ^ids)
    :ok
  end
end
