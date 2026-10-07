defmodule Ziwoas.Switching.Schedule do
  @moduledoc """
  The way back from flat switch rules to the rows a plug card shows: a
  `Window` (Zeitfenster, the two rules of one group) or a `Single`
  (Einzelschaltung, one rule on its own).
  """
  alias Ziwoas.Switching.Rule

  defmodule Window do
    @moduledoc """
    A Zeitfenster. Its weekdays are the on rule's: the off rule of a window past
    midnight carries them shifted one day forward.
    """
    @enforce_keys [:on, :off]
    defstruct @enforce_keys
    @type t :: %__MODULE__{on: Rule.t(), off: Rule.t()}
  end

  defmodule Single do
    @moduledoc "An Einzelschaltung."
    @enforce_keys [:rule]
    defstruct @enforce_keys
    @type t :: %__MODULE__{rule: Rule.t()}
  end

  @type entry :: Window.t() | Single.t()

  @doc "Earliest first; a tie goes to the smallest rule id, so the order never wobbles."
  @spec fold([Rule.t()]) :: [entry]
  def fold(rules) do
    rules
    |> group_by_first_appearance(& &1.group_id)
    |> Enum.flat_map(fn
      {nil, group} -> singles(group)
      {_group_id, group} -> entries_for_group(group)
    end)
    |> Enum.sort_by(
      &{at_minute(&1), &1 |> rules() |> Enum.map(fn rule -> rule.id end) |> Enum.min()}
    )
  end

  # A group that is not a pair becomes singles: visible and deletable rather than a blank row.
  defp entries_for_group(group) do
    on = Enum.find(group, &(&1.action == "on"))
    off = Enum.find(group, &(&1.action == "off"))
    if on && off, do: [%Window{on: on, off: off}], else: singles(group)
  end

  defp singles(rules), do: Enum.map(rules, &%Single{rule: &1})

  # Groups in the order of their first appearance.
  defp group_by_first_appearance(items, key_fun) do
    {keys, groups} =
      Enum.reduce(items, {[], %{}}, fn item, {keys, groups} ->
        key = key_fun.(item)
        keys = if Map.has_key?(groups, key), do: keys, else: [key | keys]
        {keys, Map.update(groups, key, [item], &[item | &1])}
      end)

    keys |> Enum.reverse() |> Enum.map(&{&1, Enum.reverse(Map.fetch!(groups, &1))})
  end

  @doc "A Zeitfenster's group id, an Einzelschaltung's rule id."
  def id(%Window{on: on}), do: on.group_id
  def id(%Single{rule: rule}), do: rule.id

  def days(%Window{on: on}), do: on.days
  def days(%Single{rule: rule}), do: rule.days

  def at_minute(%Window{on: on}), do: on.at_minute
  def at_minute(%Single{rule: rule}), do: rule.at_minute

  def enabled?(%Window{on: on}), do: on.enabled
  def enabled?(%Single{rule: rule}), do: rule.enabled

  def rules(%Window{on: on, off: off}), do: [on, off]
  def rules(%Single{rule: rule}), do: [rule]

  def window?(entry), do: match?(%Window{}, entry)
end
