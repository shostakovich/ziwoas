defmodule Ziwoas.EnergySummary do
  @moduledoc """
  Today's energy balance from the raw samples: what
  the producers made and the consumers drew since local midnight, the share
  of it consumed at the same time, and what that saved at today's price.
  """
  alias Ziwoas.{Clock, Config, Economics, Energy, LocalDay, PowerSeries, Repo}
  alias Ziwoas.Economics.SavingsCalculator
  alias Ziwoas.Plugs.{EnergyDeltas, Roster}

  @enforce_keys [:produced, :consumed, :self_consumed, :savings_eur, :date]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          produced: Energy.t(),
          consumed: Energy.t(),
          self_consumed: Energy.t(),
          savings_eur: float | nil,
          date: String.t()
        }

  @doc "Today in the configured zone, as of `now` (default: `Ziwoas.Clock.now/0`)."
  @spec compute_today(Config.t(), DateTime.t()) :: t
  def compute_today(%Config{} = config, now \\ Clock.now()) do
    zone = config.location.timezone
    today = now |> DateTime.shift_zone!(zone) |> DateTime.to_date()
    {start_ts, end_ts} = LocalDay.window(today, zone)
    roster = Config.plug_roster(config)

    produced = Energy.wh(energy_delta_wh(Roster.producer_ids(roster), start_ts, end_ts))
    consumed = Energy.wh(energy_delta_wh(Roster.consumer_ids(roster), start_ts, end_ts))

    self_consumed =
      roster
      |> PowerSeries.from_samples(start_ts, end_ts, PowerSeries.sample_5min_bucket_seconds())
      |> PowerSeries.self_consumed_wh(produced.wh, consumed.wh)
      |> Energy.wh()

    calculator = SavingsCalculator.new(Economics.price_book())

    %__MODULE__{
      produced: produced,
      consumed: consumed,
      self_consumed: self_consumed,
      savings_eur: SavingsCalculator.savings_eur(calculator, self_consumed, today),
      date: Date.to_iso8601(today)
    }
  end

  @spec autarky_ratio(t) :: float
  def autarky_ratio(%__MODULE__{} = summary),
    do: Energy.ratio_to(summary.self_consumed, summary.consumed)

  @spec self_consumption_ratio(t) :: float
  def self_consumption_ratio(%__MODULE__{} = summary),
    do: Energy.ratio_to(summary.self_consumed, summary.produced)

  defp energy_delta_wh([], _start_ts, _end_ts), do: 0.0

  defp energy_delta_wh(plug_ids, start_ts, end_ts) do
    sql =
      EnergyDeltas.cte(plug_ids) <>
        "SELECT plug_id, SUM(delta_wh) AS delta FROM deltas GROUP BY plug_id"

    %{rows: rows} = Repo.query!(sql, EnergyDeltas.params(plug_ids, start_ts, end_ts))

    rows
    |> Enum.map(fn [_plug_id, delta] -> delta || 0 end)
    |> Enum.sum()
    |> Kernel.*(1.0)
  end
end
