defmodule ZiwoasWeb.ReportRangeTest do
  use ExUnit.Case, async: true

  alias ZiwoasWeb.ReportRange

  test "no range asked for is the last 7 days" do
    assert ReportRange.resolve(%{}) == %{range: {:last_days, 7}, preset: :last_7, invalid: false}
  end

  test "a preset names its days; an unknown one is the last 7, quietly" do
    assert %{range: {:last_days, 30}, preset: :last_30, invalid: false} =
             ReportRange.resolve(%{"preset" => "last_30"})

    assert %{range: {:last_days, 7}, preset: :last_7, invalid: false} =
             ReportRange.resolve(%{"preset" => "last_9000"})
  end

  test "two ISO dates in order are a custom range" do
    assert ReportRange.resolve(%{"start_date" => "2026-04-01", "end_date" => "2026-04-03"}) ==
             %{
               range: Date.range(~D[2026-04-01], ~D[2026-04-03]),
               preset: :custom,
               invalid: false
             }
  end

  test "blank dates ask for no custom range" do
    assert %{preset: :last_30, invalid: false} =
             ReportRange.resolve(%{"preset" => "last_30", "start_date" => " ", "end_date" => ""})
  end

  test "a missing, malformed or reversed date is invalid and falls back to the preset" do
    for params <- [
          %{"start_date" => "2026-04-01"},
          %{"start_date" => "2026-04-01", "end_date" => "2026-W15-2"},
          %{"start_date" => "2026-04-07", "end_date" => "2026-04-01"},
          %{"start_date" => "2026-04-07", "end_date" => "2026-04-01", "preset" => "last_30"}
        ] do
      assert %{range: {:last_days, _}, invalid: true} = ReportRange.resolve(params)
    end

    assert %{range: {:last_days, 30}, preset: :last_30} =
             ReportRange.resolve(%{"preset" => "last_30", "end_date" => "x"})
  end
end
