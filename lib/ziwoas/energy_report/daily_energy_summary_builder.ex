defmodule Ziwoas.EnergyReport.DailyEnergySummaryBuilder do
  @moduledoc """
  Produced, consumed and self-consumed energy of one local day, from its
  `samples_5min` rows. Metered energy is the counters' delta; self-consumption
  comes from the power overlap (`Ziwoas.PowerSeries`), clamped to the meters.
  """
  import Ecto.Query

  alias Ziwoas.{LocalDay, PowerSeries, Repo}
  alias Ziwoas.Plugs.{Roster, Sample5min}

  @type summary :: %{produced_wh: float, consumed_wh: float, self_consumed_wh: number}

  @spec build(Roster.t() | list, String.t(), Date.t()) :: summary
  def build(plugs, timezone, %Date{} = date) do
    roster = Roster.new(plugs)
    {start_ts, end_ts} = LocalDay.window(date, timezone)

    # Unordered like Rails' query: the naive sums below follow SQLite's row order.
    rows =
      Repo.all(from s in Sample5min, where: s.bucket_ts >= ^start_ts and s.bucket_ts < ^end_ts)

    {produced_wh, consumed_wh} = metered_energy_wh(rows, roster)

    %{
      produced_wh: produced_wh,
      consumed_wh: consumed_wh,
      self_consumed_wh:
        rows
        |> PowerSeries.from_5min(roster)
        |> PowerSeries.self_consumed_wh(produced_wh, consumed_wh)
    }
  end

  defp metered_energy_wh(rows, roster) do
    Enum.reduce(rows, {0.0, 0.0}, fn row, {produced, consumed} ->
      case Roster.role_of(roster, row.plug_id) do
        :producer -> {produced + row.energy_delta_wh, consumed}
        :consumer -> {produced, consumed + row.energy_delta_wh}
        _ -> {produced, consumed}
      end
    end)
  end
end
