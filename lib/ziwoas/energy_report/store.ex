defmodule Ziwoas.EnergyReport.Store do
  @moduledoc "All database reads behind the energy report. Dates are ISO strings in the tables."
  import Ecto.Query

  alias Ziwoas.EnergyReport.DailyEnergySummary
  alias Ziwoas.Plugs.{DailyTotal, Sample5min}
  alias Ziwoas.Repo

  @doc "The first and the last day with aggregates, or nil before the first."
  @spec aggregate_date_range() :: {Date.t(), Date.t()} | nil
  def aggregate_date_range do
    case Repo.one(from d in DailyTotal, select: {min(d.date), max(d.date)}) do
      {first, last} when first not in [nil, ""] and last not in [nil, ""] ->
        {Date.from_iso8601!(first), Date.from_iso8601!(last)}

      _ ->
        nil
    end
  end

  @spec daily_rows(Date.t(), Date.t()) :: [DailyTotal.t()]
  def daily_rows(start_date, end_date) do
    {first, last} = {Date.to_iso8601(start_date), Date.to_iso8601(end_date)}
    Repo.all(from d in DailyTotal, where: d.date >= ^first and d.date <= ^last)
  end

  @spec daily_summaries(Date.t(), Date.t()) :: %{String.t() => DailyEnergySummary.t()}
  def daily_summaries(start_date, end_date) do
    {first, last} = {Date.to_iso8601(start_date), Date.to_iso8601(end_date)}

    from(s in DailyEnergySummary, where: s.date >= ^first and s.date <= ^last)
    |> Repo.all()
    |> Map.new(&{&1.date, &1})
  end

  @spec sample_rows(integer, integer) :: [Sample5min.t()]
  def sample_rows(start_ts, end_ts) do
    Repo.all(
      from s in Sample5min,
        where: s.bucket_ts >= ^start_ts and s.bucket_ts < ^end_ts,
        order_by: s.bucket_ts
    )
  end

  @spec daily_totals_for_plug(String.t(), [String.t()]) :: %{String.t() => DailyTotal.t()}
  def daily_totals_for_plug(plug_id, dates) do
    from(d in DailyTotal, where: d.plug_id == ^plug_id and d.date in ^dates)
    |> Repo.all()
    |> Map.new(&{&1.date, &1})
  end
end
