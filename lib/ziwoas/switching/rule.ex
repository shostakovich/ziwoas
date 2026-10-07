defmodule Ziwoas.Switching.Rule do
  @moduledoc """
  A switch time (`switch_rules`): switch one plug on or off at `at_minute` past midnight
  on the ISO weekdays in `days`. A `group_id` pairs two rules into a time window.
  """
  use Ziwoas.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @actions ~w[on off]
  @iso_days 1..7
  @clock_time ~r/\A([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\z/

  schema "switch_rules" do
    field :action, :string
    field :at_minute, :integer
    field :days, {:array, :integer}
    field :enabled, :boolean, default: true
    field :group_id, :string
    field :plug_id, :string
    timestamps()
  end

  def actions, do: @actions

  def iso_days, do: Enum.to_list(@iso_days)

  @doc "`\"18:00\"` → 1080, anything else nil (`Switching::Rule.minutes_from`)."
  @spec minutes_from(term) :: non_neg_integer | nil
  def minutes_from(value) when is_binary(value) do
    case Regex.run(@clock_time, value, capture: :all_but_first) do
      [hours, minutes] -> String.to_integer(hours) * 60 + String.to_integer(minutes)
      nil -> nil
    end
  end

  def minutes_from(_value), do: nil

  @doc "`at_minute` as `HH:MM`, nil without one."
  @spec at_minute_time(t | non_neg_integer | nil) :: String.t() | nil
  def at_minute_time(%__MODULE__{at_minute: at_minute}), do: at_minute_time(at_minute)
  def at_minute_time(nil), do: nil

  def at_minute_time(minute) when is_integer(minute),
    do: pad(div(minute, 60)) <> ":" <> pad(rem(minute, 60))

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  @doc """
  The Active Record validations, the last line of defence behind the form
  contracts: a plug, a direction, a minute of the day, weekdays (sorted, unique).
  """
  @spec changeset(t, map) :: Ecto.Changeset.t()
  def changeset(rule, attrs) do
    # Normalised before the comparison, like Rails' before_validation: [2, 1] over
    # a stored [1, 2] is no change.
    attrs =
      if Map.has_key?(attrs, :days), do: Map.update!(attrs, :days, &normalize_days/1), else: attrs

    rule
    |> cast(attrs, [:plug_id, :action, :at_minute, :days])
    |> validate_required([:plug_id], message: "can't be blank")
    |> validate_inclusion(:action, @actions, message: "is not included in the list")
    |> validate_required([:action], message: "is not included in the list")
    |> validate_required([:at_minute], message: "muss zwischen 00:00 und 23:59 liegen")
    |> validate_number(:at_minute,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1439,
      message: "muss zwischen 00:00 und 23:59 liegen"
    )
    |> validate_change(:days, fn :days, days ->
      if days != [] and Enum.all?(days, &(&1 in @iso_days)),
        do: [],
        else: [days: "mindestens ein Wochentag muss gewählt sein"]
    end)
    |> validate_required([:days], message: "mindestens ein Wochentag muss gewählt sein")
  end

  defp normalize_days(days) when is_list(days), do: days |> Enum.uniq() |> Enum.sort()
  defp normalize_days(days), do: days
end
