defmodule Ziwoas.EnergySummaryTest do
  use Ziwoas.DataCase

  alias Ziwoas.{EnergySummary, TestConfigs}

  @now ~U[2026-10-05 10:00:00Z]

  setup do
    insert_price!("2020-01-01", "0.32")
    %{config: TestConfigs.plugs(), midnight: berlin_midnight(~D[2026-10-05])}
  end

  test "saves nothing from energy no consumer took at the time", %{
    config: config,
    midnight: midnight
  } do
    insert_sample!("bkw", midnight + 60, 0, 0.0)
    insert_sample!("bkw", midnight + 3600, 0, 1000.0)
    insert_sample!("fridge", midnight + 60, 0, 500.0)
    insert_sample!("fridge", midnight + 3600, 0, 600.0)

    summary = EnergySummary.compute_today(config, @now)

    assert summary.produced.wh == 1000.0
    assert summary.consumed.wh == 100.0
    # Counters without simultaneous power: nothing was demonstrably self-consumed.
    assert summary.savings_eur == 0.0
    assert summary.date == "2026-10-05"
  end

  test "is zero without samples, ratios included", %{config: config} do
    summary = EnergySummary.compute_today(config, @now)

    assert summary.produced.wh == 0.0
    assert summary.consumed.wh == 0.0
    assert summary.savings_eur == 0.0
    assert EnergySummary.autarky_ratio(summary) == 0.0
    assert EnergySummary.self_consumption_ratio(summary) == 0.0
  end

  test "survives a meter reset", %{config: config, midnight: midnight} do
    insert_sample!("fridge", midnight + 60, 0, 424_440.0)
    insert_sample!("fridge", midnight + 120, 0, 0.0)
    insert_sample!("fridge", midnight + 180, 0, 50.0)

    assert EnergySummary.compute_today(config, @now).consumed.wh == 50.0
  end

  test "ignores a glitch to zero and the jump back", %{config: config, midnight: midnight} do
    insert_sample!("fridge", midnight + 60, 145, 425_000.0)
    insert_sample!("fridge", midnight + 65, 145, 0.0)
    insert_sample!("fridge", midnight + 70, 145, 425_005.0)
    insert_sample!("fridge", midnight + 75, 145, 425_010.0)

    assert EnergySummary.compute_today(config, @now).consumed.wh == 5.0
  end

  test "self-consumption is the simultaneous overlap", %{config: config, midnight: midnight} do
    for dt <- 0..3600//60 do
      insert_sample!("bkw", midnight + dt, 200.0, 200.0 * dt / 3600.0)
      insert_sample!("fridge", midnight + dt, 100.0, 100.0 * dt / 3600.0)
    end

    summary = EnergySummary.compute_today(config, @now)

    assert_in_delta summary.produced.wh, 200.0, 2.0
    assert_in_delta summary.consumed.wh, 100.0, 2.0
    assert_in_delta summary.self_consumed.wh, 100.0, 2.0
    assert_in_delta EnergySummary.autarky_ratio(summary), 1.0, 0.05
    assert_in_delta EnergySummary.self_consumption_ratio(summary), 0.5, 0.05
    # 100 Wh self-consumed at 0.32 €/kWh.
    assert_in_delta summary.savings_eur, 0.032, 0.001
  end

  test "no price on record means no savings at all", %{config: config} do
    Ziwoas.Repo.query!("DELETE FROM electricity_prices")
    assert EnergySummary.compute_today(config, @now).savings_eur == nil
  end

  test "excludes samples beyond today's window", %{config: config, midnight: midnight} do
    insert_sample!("bkw", midnight + 60, 0, 0.0)
    insert_sample!("bkw", midnight + 3600, 0, 100.0)
    insert_sample!("bkw", midnight + 90_000, 0, 99_999.0)

    assert EnergySummary.compute_today(config, @now).produced.wh == 100.0
  end

  # Europe/Berlin 2026-10-25 is 25 hours long.
  test "covers all 25 hours of a long DST day", %{config: config} do
    midnight = 1_792_879_200
    insert_sample!("bkw", midnight + 24 * 3600, 0, 1000.0)
    insert_sample!("bkw", midnight + 24 * 3600 + 1800, 0, 1250.0)

    summary =
      EnergySummary.compute_today(config, DateTime.from_unix!(midnight + 24 * 3600 + 3000))

    assert summary.date == "2026-10-25"
    assert summary.produced.wh == 250.0
  end

  test "reads now from the clock by default", %{config: config} do
    Ziwoas.TestClock.freeze(@now)
    assert EnergySummary.compute_today(config).date == "2026-10-05"
  end
end
