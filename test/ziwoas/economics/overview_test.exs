defmodule Ziwoas.Economics.OverviewTest do
  use Ziwoas.DataCase

  alias Ziwoas.Repo
  alias Ziwoas.Economics.{CostItem, Overview}
  alias Ziwoas.EnergyReport.DailyEnergySummary

  @today ~D[2026-10-06]

  defp cost!(amount),
    do:
      Repo.insert!(%CostItem{
        label: "Anlage",
        amount_eur: Decimal.new(amount),
        spent_on: ~D[2026-01-01]
      })

  defp day!(date, self_consumed_wh),
    do:
      Repo.insert!(%DailyEnergySummary{
        date: Date.to_iso8601(date),
        produced_wh: 10_000.0,
        consumed_wh: 8_000.0,
        self_consumed_wh: self_consumed_wh * 1.0
      })

  test "without anything recorded, every money figure is unknown" do
    assert %Overview{
             saved_eur: nil,
             acquisition_cost_eur: +0.0,
             covered_ratio: nil,
             data_start: nil,
             projected_payback_date: nil,
             reached_on: nil,
             projection_days: 0,
             priced: false,
             costed: false
           } = Overview.build(@today)
  end

  test "without a price the savings stay unknown, even with days and costs on record" do
    cost!("1000")
    day!(~D[2026-10-01], 2_000)

    overview = Overview.build(@today)

    assert {overview.priced, overview.costed} == {false, true}
    assert {overview.saved_eur, overview.covered_ratio, overview.reached_on} == {nil, nil, nil}
    assert overview.data_start == ~D[2026-10-01]
    assert overview.acquisition_cost_eur == 1000.0
    refute Overview.reached?(overview)
  end

  test "prices each day at the price in force on it" do
    cost!("1000")
    insert_price!("2026-01-01", "0.30")
    insert_price!("2026-10-02", "0.20")
    day!(~D[2026-10-01], 2_000)
    day!(~D[2026-10-02], 2_000)

    overview = Overview.build(@today)

    assert_in_delta overview.saved_eur, 1.0, 1.0e-9
    assert_in_delta overview.covered_ratio, 0.001, 1.0e-12
    assert overview.data_start == ~D[2026-10-01]
    assert overview.projection_days == 2
    assert overview.projected_payback_date == nil
  end

  test "projects the payback from 90 days on record" do
    cost!("1000")
    insert_price!("2026-01-01", "0.25")
    for offset <- 0..99, do: day!(Date.add(@today, -offset), 4_000)

    overview = Overview.build(@today)

    assert_in_delta overview.saved_eur, 100.0, 1.0e-9
    assert overview.projection_days == 100
    assert overview.projected_payback_date == Date.add(@today, 900)
  end

  test "names the day the plant paid for itself" do
    cost!("1.50")
    insert_price!("2026-01-01", "0.50")
    day!(~D[2026-09-01], 2_000)
    day!(~D[2026-09-02], 2_000)

    overview = Overview.build(@today)

    assert Overview.reached?(overview)
    assert overview.reached_on == ~D[2026-09-02]
    assert overview.covered_ratio == 1.0
    assert overview.projected_payback_date == nil
  end

  test "subsidies beyond the spending leave nothing to earn back" do
    cost!("-100")
    insert_price!("2026-01-01", "0.30")
    day!(~D[2026-10-01], 2_000)

    overview = Overview.build(@today)

    refute overview.costed
    assert overview.covered_ratio == nil
    assert_in_delta overview.saved_eur, 0.6, 1.0e-9
  end
end
