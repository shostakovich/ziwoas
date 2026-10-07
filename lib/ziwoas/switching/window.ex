defmodule Ziwoas.Switching.Window do
  @moduledoc """
  The Zeitfenster form: an on and an off time and one set of weekdays, stored as
  two rules sharing a `group_id` (`Ziwoas.Switching.Rules.save_window/3`). The
  days are the ones typed; the shift past midnight belongs to the off rule alone.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ziwoas.Switching.Rule

  @primary_key false
  embedded_schema do
    field :group_id, :string
    field :on_at_time, :string
    field :off_at_time, :string
    field :days, {:array, :integer}, default: []
  end

  @type t :: %__MODULE__{}

  @doc "The form of a stored Zeitfenster; its days come from the on rule."
  @spec from_rules(String.t(), Rule.t(), Rule.t()) :: t
  def from_rules(group_id, on, off) do
    %__MODULE__{
      group_id: group_id,
      on_at_time: Rule.at_minute_time(on),
      off_at_time: Rule.at_minute_time(off),
      days: on.days
    }
  end

  @spec changeset(t, map) :: Ecto.Changeset.t()
  def changeset(window, attrs) do
    window
    |> cast(Rule.drop_blank_days(attrs), [:on_at_time, :off_at_time, :days])
    |> Rule.validate_clock(:on_at_time)
    |> Rule.validate_clock(:off_at_time)
    |> validate_distinct_times()
    |> Rule.validate_days()
  end

  defp validate_distinct_times(changeset) do
    on = Rule.minutes_from(get_field(changeset, :on_at_time))
    off = Rule.minutes_from(get_field(changeset, :off_at_time))

    if on && on == off,
      do: add_error(changeset, :off_at_time, "An- und Aus-Zeit müssen sich unterscheiden"),
      else: changeset
  end

  @days_per_week 7

  @doc "An off time before the on time falls on the next day."
  @spec off_days(t) :: [integer]
  def off_days(%__MODULE__{days: days} = window) do
    if minutes(window.off_at_time) < minutes(window.on_at_time),
      do: days |> Enum.map(&(rem(&1, @days_per_week) + 1)) |> Enum.sort(),
      else: days
  end

  defp minutes(time), do: Rule.minutes_from(time) || 0
end
