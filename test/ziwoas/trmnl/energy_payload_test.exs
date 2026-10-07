defmodule Ziwoas.Trmnl.EnergyPayloadTest do
  # Mirrors test/models/trmnl_payload_builder_test.rb.
  use Ziwoas.DataCase, async: true

  alias Ziwoas.{RubyJSON, TestConfigs}
  alias Ziwoas.Trmnl.EnergyPayload

  # 16:56 Europe/Berlin: the window ends at the 17:00 boundary.
  @now ~U[2026-05-12 14:56:00Z]
  @end_ts DateTime.to_unix(~U[2026-05-12 15:00:00Z])
  @start_ts @end_ts - 86_400

  setup do
    %{config: TestConfigs.plugs(), midnight: berlin_midnight(~D[2026-05-12])}
  end

  defp merge_variables(config),
    do:
      config
      |> EnergyPayload.build(@now)
      |> Map.new()
      |> Map.fetch!("merge_variables")
      |> Map.new()

  test "today's aggregate fields", %{config: config, midnight: midnight} do
    insert_sample!("bkw", midnight + 60, 0, 0.0)
    insert_sample!("bkw", midnight + 3600, 0, 1000.0)
    insert_sample!("fridge", midnight + 60, 0, 500.0)
    insert_sample!("fridge", midnight + 3600, 0, 1100.0)

    mv = merge_variables(config)

    assert mv["pv_kwh"] == 1.0
    assert mv["cons_kwh"] == 0.6
    assert mv["bilanz_kwh"] == 0.4
    assert is_integer(mv["autarky"]) and is_integer(mv["self_use"])
  end

  test "zeros without samples", %{config: config} do
    mv = merge_variables(config)

    assert {mv["pv_kwh"], mv["cons_kwh"], mv["bilanz_kwh"]} == {0.0, 0.0, 0.0}
    assert {mv["autarky"], mv["self_use"]} == {0, 0}
    assert mv["pv_w"] == List.duplicate(0, 144)
    assert mv["cons_w"] == List.duplicate(0, 144)
  end

  test "144 ten-minute buckets aligned to local time", %{config: config} do
    assert EnergyPayload.window(@now, "Europe/Berlin") == {@start_ts, @end_ts}
    bucket_start = @start_ts + 10 * 600

    for dt <- 0..599//60 do
      insert_sample!("bkw", bucket_start + dt, 600.0, 0.0)
      insert_sample!("fridge", bucket_start + dt, 200.0, 0.0)
    end

    mv = merge_variables(config)

    assert length(mv["pv_w"]) == 144 and length(mv["cons_w"]) == 144
    assert Enum.at(mv["pv_w"], 10) == 600
    assert Enum.at(mv["cons_w"], 10) == 200
    assert mv["pv_w"] |> List.delete_at(10) |> Enum.all?(&(&1 === 0))
  end

  test "ts is the newest sample in the window, stand its local time", %{config: config} do
    insert_sample!("bkw", @end_ts - 60, 0, 0.0)
    insert_sample!("bkw", @end_ts - 3660, 0, 0.0)

    mv = merge_variables(config)

    assert mv["ts"] == @end_ts - 60
    assert mv["stand"] == "16:59"
  end

  test "ts and stand fall back to now without samples", %{config: config} do
    mv = merge_variables(config)

    assert mv["ts"] == DateTime.to_unix(@now)
    assert mv["stand"] == "16:56"
  end

  test "an ambiguous local slot takes the summer-time instant, as TZInfo's dst default" do
    # 2026-10-25 02:30 CET (the second 02:30) floors to the slot 02:30, read as CEST.
    second_half = ~U[2026-10-25 01:35:00Z]
    {_start, end_ts} = EnergyPayload.window(second_half, "Europe/Berlin")
    assert end_ts == DateTime.to_unix(~U[2026-10-25 00:40:00Z])
  end

  test "the serialised payload stays under TRMNL's 2 kB limit", %{config: config} do
    for t <- @start_ts..(@end_ts - 1)//300 do
      insert_sample!("bkw", t, 999.0, 0.0)
      insert_sample!("fridge", t, 999.0, 0.0)
    end

    assert byte_size(RubyJSON.encode!(EnergyPayload.build(config, @now))) <= 2048
  end
end
