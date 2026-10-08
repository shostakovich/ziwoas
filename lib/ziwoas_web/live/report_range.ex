defmodule ZiwoasWeb.ReportRange do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :preset, Ecto.Enum, values: [:last_7, :last_30]
    field :start_date, :date
    field :end_date, :date
  end

  @days %{last_7: 7, last_30: 30}

  @type resolved :: %{
          range: Ziwoas.Energy.Report.range(),
          preset: :last_7 | :last_30 | :custom,
          invalid: boolean
        }

  @spec changeset(map) :: Ecto.Changeset.t()
  def changeset(params) do
    changeset = cast(%__MODULE__{}, params, [:preset, :start_date, :end_date])

    if custom?(changeset),
      do: changeset |> validate_required([:start_date, :end_date]) |> validate_order(),
      else: changeset
  end

  @spec resolve(map) :: resolved
  def resolve(params) do
    changeset = changeset(params)
    preset = get_change(changeset, :preset) || :last_7
    date_errors? = Enum.any?(changeset.errors, fn {field, _} -> field != :preset end)

    if custom?(changeset) and not date_errors? do
      range = Date.range(get_change(changeset, :start_date), get_change(changeset, :end_date))
      %{range: range, preset: :custom, invalid: false}
    else
      %{range: {:last_days, @days[preset]}, preset: preset, invalid: date_errors?}
    end
  end

  defp custom?(changeset) do
    Enum.any?([:start_date, :end_date], fn field ->
      Map.has_key?(changeset.changes, field) or Keyword.has_key?(changeset.errors, field)
    end)
  end

  defp validate_order(changeset) do
    with %Date{} = first <- get_change(changeset, :start_date),
         %Date{} = last <- get_change(changeset, :end_date),
         :gt <- Date.compare(first, last) do
      add_error(changeset, :end_date, "liegt vor dem Startdatum")
    else
      _ -> changeset
    end
  end
end
