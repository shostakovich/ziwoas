defmodule Ziwoas.Switching.Contracts do
  @moduledoc """
  The form contracts of the schedule (`Switching::Rules::Contracts`). The
  boundary sits at the form, not at the record: the interesting checks span
  fields ("bis" must differ from "von", at least one weekday), and a single
  rule knows nothing about "bis". `Ziwoas.Switching.Rule.changeset/2` stays
  the last line of defence.
  """
  alias Ziwoas.Switching.Rule

  @messages %{
    time: "Uhrzeit im Format HH:MM angeben",
    days: "mindestens ein Wochentag muss gewählt sein",
    same: "An- und Aus-Zeit müssen sich unterscheiden",
    action: "Richtung muss an oder aus sein"
  }

  def message(key), do: Map.fetch!(@messages, key)

  @spec weekdays?(term) :: boolean
  def weekdays?(days),
    do: is_list(days) and days != [] and Enum.all?(days, &(&1 in Rule.iso_days()))

  def no_time?(value), do: is_nil(Rule.minutes_from(value))

  defmodule Window do
    @moduledoc """
    The Zeitfenster form: two times and one set of weekdays. The day shift past
    midnight stays with `Ziwoas.Switching.Rules.save_window/3`.
    """
    use Ecto.Schema

    alias Ziwoas.Form
    alias Ziwoas.Switching.{Contracts, Rule}

    @primary_key false
    embedded_schema do
      field :on_at_time, :string
      field :off_at_time, :string
      field :days, {:array, :integer}
    end

    @spec changeset(map) :: Ecto.Changeset.t()
    def changeset(params) do
      changeset =
        Form.cast(%__MODULE__{}, params,
          on_at_time: {:required, :maybe_string},
          off_at_time: {:required, :maybe_string},
          days: {:required, :integer_list}
        )

      on = Rule.minutes_from(Map.get(changeset.changes, :on_at_time))

      changeset
      |> Form.rule(:on_at_time, &Contracts.no_time?/1, Contracts.message(:time))
      |> Form.rule(:off_at_time, &Contracts.no_time?/1, Contracts.message(:time))
      |> Form.rule(:off_at_time, &same_time?(on, &1), Contracts.message(:same))
      |> Form.rule(:days, &(not Contracts.weekdays?(&1)), Contracts.message(:days))
    end

    defp same_time?(on, off_value) do
      off = Rule.minutes_from(off_value)
      not is_nil(on) and on == off
    end
  end

  defmodule Single do
    @moduledoc "The Einzelschaltung form: one time, one direction, one set of weekdays."
    use Ecto.Schema

    alias Ziwoas.Form
    alias Ziwoas.Switching.{Contracts, Rule}

    @primary_key false
    embedded_schema do
      field :at_minute_time, :string
      field :action, :string
      field :days, {:array, :integer}
    end

    @spec changeset(map) :: Ecto.Changeset.t()
    def changeset(params) do
      %__MODULE__{}
      |> Form.cast(params,
        at_minute_time: {:required, :maybe_string},
        action: {:required, :maybe_string},
        days: {:required, :integer_list}
      )
      |> Form.rule(:at_minute_time, &Contracts.no_time?/1, Contracts.message(:time))
      |> Form.rule(:action, &(&1 not in Rule.actions()), Contracts.message(:action))
      |> Form.rule(:days, &(not Contracts.weekdays?(&1)), Contracts.message(:days))
    end
  end
end
