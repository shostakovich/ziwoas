defmodule Ziwoas.Switching.Rules do
  @moduledoc """
  The schedule of the switchable plugs: Zeitfenster (two rules in a group) and
  Einzelschaltungen (one rule), their forms, lookups and writes.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Ziwoas.{Clock, Repo}
  alias Ziwoas.Switching.{Rule, Window}

  @doc "The rules of one group on one plug."
  @spec group(String.t(), String.t()) :: [Rule.t()]
  def group(plug_id, group_id),
    do: Repo.all(from r in Rule, where: r.plug_id == ^plug_id and r.group_id == ^group_id)

  @doc """
  Both halves or nothing: a group that lost one is shown and edited as an
  Einzelschaltung instead.
  """
  @spec halves([Rule.t()]) :: {Rule.t(), Rule.t()} | nil
  def halves(rules) do
    on = Enum.find(rules, &(&1.action == "on"))
    off = Enum.find(rules, &(&1.action == "off"))
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

  @doc "The Zeitfenster form's changeset."
  @spec change_window(Window.t(), map) :: Changeset.t()
  def change_window(window \\ %Window{}, attrs \\ %{}), do: Window.changeset(window, attrs)

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
        write_half(plug_id, group_id, "on", on_minute, window.days)
        write_half(plug_id, group_id, "off", off_minute, Window.off_days(window))
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

  @doc "The Einzelschaltung form's changeset."
  @spec change_single(Rule.t(), map) :: Changeset.t()
  def change_single(rule \\ %Rule{}, attrs \\ %{}),
    do: rule |> Rule.for_form() |> Rule.form_changeset(attrs)

  @doc "Writes an Einzelschaltung: one rule, no group."
  @spec save_single(String.t(), map, Rule.t() | nil) :: {:ok, Rule.t()} | {:error, Changeset.t()}
  def save_single(plug_id, attrs, rule \\ nil) do
    (rule || %Rule{})
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
  @spec delete([Rule.t()]) :: :ok
  def delete(rules) do
    ids = Enum.map(rules, & &1.id)
    Repo.delete_all(from r in Rule, where: r.id in ^ids)
    :ok
  end
end
