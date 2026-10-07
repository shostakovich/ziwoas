defmodule Ziwoas.Switching.Rules do
  @moduledoc """
  Writing the schedule (`Switching::Rules::SaveWindow`, `SaveSingle`,
  `SetEnabled` and the controllers' lookups). Every write runs inside
  `Ziwoas.Repo.write(:switch_schedule, …)`.
  """
  import Ecto.Query

  alias Ziwoas.{Clock, Repo, RubyNumeric}
  alias Ziwoas.Switching.Rule

  @task :switch_schedule
  @days_per_week 7

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

  @doc """
  The Einzelschaltung `id` names on this plug — nil for a rule that is one
  half of an intact Zeitfenster, which only moves together with its partner.
  """
  @spec single(String.t(), term) :: Rule.t() | nil
  def single(plug_id, id) do
    with {:ok, id} <- RubyNumeric.integer(id),
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

  @doc """
  Writes a Zeitfenster: two rules, one group, one transaction. An off time
  before the on time shifts the off rule's weekdays one day forward. Returns
  the group id.
  """
  @spec save_window(String.t(), map, String.t() | nil) :: String.t()
  def save_window(plug_id, attrs, group_id \\ nil) do
    on_minute = Rule.minutes_from(attrs.on_at_time)
    off_minute = Rule.minutes_from(attrs.off_at_time)
    group_id = group_id || Ecto.UUID.generate()

    Repo.write(@task, fn ->
      Repo.transaction(fn ->
        write_half(plug_id, group_id, "on", on_minute, attrs.days)

        write_half(
          plug_id,
          group_id,
          "off",
          off_minute,
          off_days(attrs.days, on_minute, off_minute)
        )
      end)
    end)

    group_id
  end

  # `to_i` only keeps an unparseable time from raising here: the validation has the last word.
  defp off_days(days, on_minute, off_minute) do
    if (off_minute || 0) < (on_minute || 0),
      do: days |> Enum.map(&(rem(&1, @days_per_week) + 1)) |> Enum.sort(),
      else: days
  end

  defp write_half(plug_id, group_id, action, at_minute, days) do
    rule = Repo.one(from r in Rule, where: r.group_id == ^group_id and r.action == ^action)

    (rule || %Rule{group_id: group_id, action: action})
    |> Rule.changeset(%{plug_id: plug_id, at_minute: at_minute, days: days})
    |> Repo.insert_or_update!()
  end

  @doc "Writes an Einzelschaltung: one rule, no group (`SaveSingle`)."
  @spec save_single(String.t(), map, Rule.t() | nil) :: Rule.t()
  def save_single(plug_id, attrs, rule \\ nil) do
    Repo.write(@task, fn ->
      (rule || %Rule{})
      |> Rule.changeset(%{
        plug_id: plug_id,
        action: attrs.action,
        at_minute: Rule.minutes_from(attrs.at_minute_time),
        days: attrs.days
      })
      |> Repo.insert_or_update!()
    end)
  end

  @doc """
  Pauses or resumes `rules` together — both halves of a Zeitfenster always
  move as one. `enabled` is `ActiveModel::Type::Boolean`'s cast; nil (a blank
  parameter) fails the NOT NULL column as in Rails.
  """
  @spec set_enabled([Rule.t()], boolean | nil) :: :ok
  def set_enabled(rules, enabled) do
    ids = Enum.map(rules, & &1.id)

    Repo.write(@task, fn ->
      Repo.update_all(from(r in Rule, where: r.id in ^ids),
        set: [enabled: enabled, updated_at: Clock.now()]
      )
    end)

    :ok
  end

  @doc "Deletes `rules`."
  @spec delete([Rule.t()]) :: :ok
  def delete(rules) do
    Repo.write(@task, fn -> Enum.each(rules, &Repo.delete!/1) end)
    :ok
  end

  @false_values ["0", "f", "F", "false", "FALSE", "off", "OFF"]

  @doc "`ActiveModel::Type::Boolean.new.cast` for a request parameter."
  @spec cast_boolean(term) :: boolean | nil
  def cast_boolean(value) when value in [nil, ""], do: nil
  def cast_boolean(value) when value in @false_values, do: false
  def cast_boolean(_value), do: true
end
