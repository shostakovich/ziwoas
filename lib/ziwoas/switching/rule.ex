defmodule Ziwoas.Switching.Rule do
  @moduledoc false
  use Ziwoas.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @iso_days 1..7
  @clock_time ~r/\A([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\z/

  @time_message "Uhrzeit im Format HH:MM angeben"
  @days_message "mindestens ein Wochentag muss gewählt sein"
  @action_message "Richtung muss an oder aus sein"

  schema "switch_rules" do
    field :action, Ecto.Enum, values: [:on, :off], default: :off
    field :at_minute, :integer
    field :at_minute_time, :string, virtual: true
    field :days, {:array, :integer}, default: []
    field :enabled, :boolean, default: true
    field :group_id, :string
    field :plug_id, :string
    timestamps()
  end

  def iso_days, do: Enum.to_list(@iso_days)

  @spec minutes_from(term) :: non_neg_integer | nil
  def minutes_from(value) when is_binary(value) do
    case Regex.run(@clock_time, value, capture: :all_but_first) do
      [hours, minutes] -> String.to_integer(hours) * 60 + String.to_integer(minutes)
      nil -> nil
    end
  end

  def minutes_from(_value), do: nil

  @spec at_minute_time(t | non_neg_integer | nil) :: String.t() | nil
  def at_minute_time(%__MODULE__{at_minute: at_minute}), do: at_minute_time(at_minute)
  def at_minute_time(nil), do: nil

  def at_minute_time(minute) when is_integer(minute),
    do: pad(div(minute, 60)) <> ":" <> pad(rem(minute, 60))

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  @spec for_form(t) :: t
  def for_form(rule), do: %{rule | at_minute_time: at_minute_time(rule)}

  @spec form_changeset(t, map) :: Ecto.Changeset.t()
  def form_changeset(rule, attrs) do
    rule
    |> cast(drop_blank_days(attrs), [:at_minute_time, :action, :days], message: &cast_message/2)
    |> validate_clock(:at_minute_time)
    |> validate_required([:action], message: @action_message)
    |> validate_days()
    |> put_at_minute()
  end

  defp cast_message(:action, _meta), do: @action_message
  defp cast_message(_field, _meta), do: nil

  defp put_at_minute(changeset) do
    case minutes_from(get_field(changeset, :at_minute_time)) do
      nil -> changeset
      minute -> put_change(changeset, :at_minute, minute)
    end
  end

  @spec changeset(t, map) :: Ecto.Changeset.t()
  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:plug_id, :action, :at_minute, :days, :group_id])
    |> validate_required([:plug_id])
    |> validate_required([:action])
    |> validate_required([:at_minute], message: "muss zwischen 00:00 und 23:59 liegen")
    |> validate_number(:at_minute,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1439,
      message: "muss zwischen 00:00 und 23:59 liegen"
    )
    |> validate_days()
  end

  @spec validate_clock(Ecto.Changeset.t(), atom) :: Ecto.Changeset.t()
  def validate_clock(changeset, field) do
    changeset
    |> validate_required([field], message: @time_message)
    |> validate_change(field, fn ^field, value ->
      if minutes_from(value), do: [], else: [{field, @time_message}]
    end)
  end

  @spec validate_days(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_days(changeset) do
    changeset = update_change(changeset, :days, &normalize_days/1)
    days = get_field(changeset, :days) || []

    cond do
      Keyword.has_key?(changeset.errors, :days) -> changeset
      days != [] and Enum.all?(days, &(&1 in @iso_days)) -> changeset
      true -> add_error(changeset, :days, @days_message)
    end
  end

  defp normalize_days(days) when is_list(days), do: days |> Enum.uniq() |> Enum.sort()
  defp normalize_days(days), do: days

  @spec drop_blank_days(map) :: map
  def drop_blank_days(attrs) do
    Enum.reduce([:days, "days"], attrs, fn key, attrs ->
      case attrs do
        %{^key => days} when is_list(days) -> Map.put(attrs, key, Enum.reject(days, &(&1 == "")))
        _ -> attrs
      end
    end)
  end
end
