defmodule Ziwoas.Sensors.ReadingPresenterTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Sensors.{Reading, ReadingPresenter}

  @now ~U[2026-05-12 14:00:00.000000Z]

  defp reading(opts \\ []) do
    %Reading{
      device_id: "X",
      taken_at: Keyword.get(opts, :taken_at, @now),
      co2: opts[:co2],
      battery_pct: opts[:battery_pct]
    }
  end

  test "co2 level: good below 1000, warn up to 1400, bad above, nil without a value" do
    assert ReadingPresenter.co2_level(reading(co2: 800)) == :good
    assert ReadingPresenter.co2_level(reading(co2: 1000)) == :warn
    assert ReadingPresenter.co2_level(reading(co2: 1399)) == :warn
    assert ReadingPresenter.co2_level(reading(co2: 1400)) == :warn
    assert ReadingPresenter.co2_level(reading(co2: 1401)) == :bad
    assert ReadingPresenter.co2_level(reading()) == nil
    assert ReadingPresenter.co2_level(nil) == nil
  end

  test "battery is low at or below 20 %" do
    assert ReadingPresenter.battery_low?(reading(battery_pct: 20))
    assert ReadingPresenter.battery_low?(reading(battery_pct: 5))
    refute ReadingPresenter.battery_low?(reading(battery_pct: 21))
    refute ReadingPresenter.battery_low?(reading())
    refute ReadingPresenter.battery_low?(nil)
  end

  test "age in seconds, minutes, hours; a dash without reading" do
    ago = fn seconds -> reading(taken_at: DateTime.add(@now, -seconds, :second)) end
    assert ReadingPresenter.age_label(ago.(30), @now) == "vor 30 s"
    assert ReadingPresenter.age_label(ago.(4 * 60), @now) == "vor 4 Min"
    assert ReadingPresenter.age_label(ago.(2 * 3600), @now) == "vor 2 h"
    assert ReadingPresenter.age_label(nil, @now) == "—"
  end

  test "offline after 30 minutes or without reading" do
    refute ReadingPresenter.offline?(
             reading(taken_at: DateTime.add(@now, -10 * 60, :second)),
             @now
           )

    refute ReadingPresenter.offline?(
             reading(taken_at: DateTime.add(@now, -30 * 60, :second)),
             @now
           )

    assert ReadingPresenter.offline?(
             reading(taken_at: DateTime.add(@now, -31 * 60, :second)),
             @now
           )

    assert ReadingPresenter.offline?(nil, @now)
  end
end
