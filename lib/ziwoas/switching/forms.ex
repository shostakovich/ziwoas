defmodule Ziwoas.Switching.WindowForm do
  @moduledoc """
  What the Zeitfenster form renders from (`Switching::Rules::WindowForm`): new,
  a failed create, edit and a failed update all hand the form this one value.
  """
  alias Ziwoas.Switching.Rule

  defstruct group_id: nil, on_at_time: nil, off_at_time: nil, days: [], errors: []

  @type t :: %__MODULE__{}

  @doc "`days` comes from the on rule alone: not reading the off rule's undoes the shift past midnight."
  @spec for_group(String.t(), Rule.t(), Rule.t()) :: t
  def for_group(group_id, on, off) do
    %__MODULE__{
      group_id: group_id,
      on_at_time: Rule.at_minute_time(on),
      off_at_time: Rule.at_minute_time(off),
      days: on.days
    }
  end

  @doc """
  Whatever the contract could still coerce comes back, with its messages. A
  time that is not a string is left out: Rails crashes rendering one (500).
  """
  @spec from_changeset(Ecto.Changeset.t(), [String.t()], String.t() | nil) :: t
  def from_changeset(changeset, errors, group_id \\ nil) do
    given = renderable(changeset, [:on_at_time, :off_at_time, :days])
    struct(%__MODULE__{group_id: group_id, errors: errors}, given)
  end

  def persisted?(%__MODULE__{group_id: group_id}), do: not is_nil(group_id)

  @doc false
  def renderable(changeset, keys) do
    for {key, value} <- Map.take(changeset.changes, keys),
        if(key == :days, do: is_list(value), else: is_binary(value)),
        into: %{},
        do: {key, value}
  end
end

defmodule Ziwoas.Switching.SingleForm do
  @moduledoc """
  The Einzelschaltung counterpart of `WindowForm` (`Switching::Rules::SingleForm`):
  one time, one direction, and the rule id once it exists.
  """
  alias Ziwoas.Switching.{Rule, WindowForm}

  defstruct id: nil, at_minute_time: nil, action: "off", days: [], errors: []

  @type t :: %__MODULE__{}

  @spec for_rule(Rule.t()) :: t
  def for_rule(rule),
    do: %__MODULE__{
      id: rule.id,
      at_minute_time: Rule.at_minute_time(rule),
      action: rule.action,
      days: rule.days
    }

  @doc "As `WindowForm.from_changeset/3`: a time or direction that is not a string is left out."
  @spec from_changeset(Ecto.Changeset.t(), [String.t()], integer | nil) :: t
  def from_changeset(changeset, errors, id \\ nil) do
    given = WindowForm.renderable(changeset, [:at_minute_time, :action, :days])
    struct(%__MODULE__{id: id, errors: errors}, given)
  end

  def persisted?(%__MODULE__{id: id}), do: not is_nil(id)
end
