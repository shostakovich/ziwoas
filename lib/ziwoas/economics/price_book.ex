defmodule Ziwoas.Economics.PriceBook do
  @moduledoc """
  The electricity prices in force over time. A price applies from its date
  until the next one begins; the earliest one also covers every day before it,
  because a plant that ran before the first price was recorded still saved money.
  """

  defmodule Entry do
    @moduledoc "A price per kWh from a date on."
    @enforce_keys [:valid_from, :eur_per_kwh]
    defstruct @enforce_keys

    @type t :: %__MODULE__{valid_from: Date.t(), eur_per_kwh: float}
  end

  defstruct entries: []

  @type t :: %__MODULE__{entries: [Entry.t()]}

  @spec new([Entry.t()]) :: t
  def new(entries), do: %__MODULE__{entries: Enum.sort_by(entries, & &1.valid_from, Date)}

  @spec empty?(t) :: boolean
  def empty?(%__MODULE__{entries: entries}), do: entries == []

  @doc "The price per kWh in force on `date`; nil for an empty book."
  @spec on(t, Date.t()) :: float | nil
  def on(%__MODULE__{entries: []}, _date), do: nil

  def on(%__MODULE__{entries: [earliest | _] = entries}, date) do
    entries
    |> Enum.reverse()
    |> Enum.find(earliest, &(Date.compare(&1.valid_from, date) != :gt))
    |> Map.fetch!(:eur_per_kwh)
  end
end
