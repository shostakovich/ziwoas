defmodule Ziwoas.Economics.Forms do
  @moduledoc """
  The dry boundary for the two lists (Rails' `Economics::Forms`): what a human
  typed becomes a checked amount and a checked date before it reaches a record.
  """
  alias Ziwoas.{RubyDate, RubyNumeric}

  @messages %{
    label: "Bezeichnung angeben",
    amount: "Betrag als Zahl angeben",
    date: "Datum angeben",
    price: "Preis muss größer als 0 sein"
  }

  def message(key), do: Map.fetch!(@messages, key)

  @doc """
  An amount as typed (`Forms::CostItem.amount`): German keyboards type a
  comma, Ruby's `Float()` decides the rest. Infinity is not an amount; nil
  where there is none.
  """
  @spec amount(term) :: float | nil
  def amount(value) do
    case RubyNumeric.float(to_s(value)) do
      {:ok, number} when is_float(number) -> number
      _ -> nil
    end
  end

  @doc "The date `Date.iso8601` reads from `value` (`Forms.date?`), nil where it raises."
  @spec date(term, Date.t()) :: Date.t() | nil
  def date(value, today), do: RubyDate.iso8601(to_s(value), today)

  defp to_s(nil), do: ""
  defp to_s(value) when is_binary(value), do: String.replace(value, ",", ".")
  defp to_s(_value), do: :not_a_string

  defmodule CostItem do
    @moduledoc "One Kostenposten as typed: a label, an amount that may be negative (a subsidy), a date, a note."
    use Ecto.Schema

    alias Ziwoas.Economics.Forms
    alias Ziwoas.Form

    @primary_key false
    embedded_schema do
      field :label, :string
      field :amount_eur, :string
      field :spent_on, :string
      field :note, :string
    end

    @spec changeset(map, Date.t()) :: Ecto.Changeset.t()
    def changeset(params, today) do
      %__MODULE__{}
      |> Form.cast(params,
        label: {:required, :maybe_string},
        amount_eur: {:required, :maybe_string},
        spent_on: {:required, :maybe_string},
        note: {:optional, :maybe_string}
      )
      |> Form.rule(:label, &Form.blank?/1, Forms.message(:label))
      |> Form.rule(:amount_eur, &is_nil(Forms.amount(&1)), Forms.message(:amount))
      |> Form.rule(:spent_on, &is_nil(Forms.date(&1, today)), Forms.message(:date))
    end
  end

  defmodule ElectricityPrice do
    @moduledoc "One Strompreis as typed: what a kilowatt-hour costs from a date on."
    use Ecto.Schema

    alias Ziwoas.Economics.Forms
    alias Ziwoas.Form

    @primary_key false
    embedded_schema do
      field :eur_per_kwh, :string
      field :valid_from, :string
    end

    @spec changeset(map, Date.t()) :: Ecto.Changeset.t()
    def changeset(params, today) do
      %__MODULE__{}
      |> Form.cast(params,
        eur_per_kwh: {:required, :maybe_string},
        valid_from: {:required, :maybe_string}
      )
      |> Form.rule(:eur_per_kwh, &not_positive?/1, Forms.message(:price))
      |> Form.rule(:valid_from, &is_nil(Forms.date(&1, today)), Forms.message(:date))
    end

    defp not_positive?(value) do
      price = Forms.amount(value)
      is_nil(price) or price <= 0
    end
  end
end
