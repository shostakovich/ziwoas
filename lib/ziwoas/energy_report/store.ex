defmodule Ziwoas.EnergyReport.Store do
  @moduledoc "All database reads behind the energy report. Dates are ISO strings in the tables."
  import Ecto.Query

  alias Ziwoas.EnergyReport.DailyEnergySummary
  alias Ziwoas.Plugs.{DailyTotal, Sample5min}
  alias Ziwoas.Repo

  @spec latest_aggregate_date() :: Date.t() | nil
  def latest_aggregate_date do
    case Repo.one(from d in DailyTotal, select: max(d.date)) do
      blank when blank in [nil, ""] -> nil
      date -> Date.from_iso8601!(date)
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
