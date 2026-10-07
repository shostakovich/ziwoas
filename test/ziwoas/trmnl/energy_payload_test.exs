defmodule Ziwoas.Trmnl.EnergyPayloadTest do
  use Ziwoas.DataCase

  alias Ziwoas.Plugs.Sample
  alias Ziwoas.{Repo, TestConfigs}
  alias Ziwoas.Trmnl.{EnergyPayload, Push}

  @now ~U[2026-05-12 14:56:00Z]
  @end_ts DateTime.to_unix(~U[2026-05-12 15:00:00Z])
  @start_ts @end_ts - 86_400

  setup do
    %{config: TestConfigs.plugs(), midnight: berlin_midnight(~D[2026-05-12])}
  end

  defp json(config), do: config |> EnergyPayload.build(@now) |> JSON.encode!()

  defp merge_variables(config),
    do: config |> json() |> JSON.decode!() |> Map.fetch!("merge_variables")

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

  test "watts are whole and a consumer's negative glitch reads as 0", %{config: config} do
    insert_sample!("fridge", @start_ts + 60, -250.4, 0.0)
    insert_sample!("fridge", @start_ts + 660, 99.6, 0.0)

    mv = merge_variables(config)

    assert Enum.take(mv["cons_w"], 2) == [0, 100]
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

  describe "the window around daylight-saving changes" do
    test "both passes of the repeated hour end at the next boundary after now" do
      for now <- [~U[2026-10-25 00:35:00Z], ~U[2026-10-25 01:35:00Z]] do
        {start_ts, end_ts} = EnergyPayload.window(now, "Europe/Berlin")

        assert end_ts == DateTime.to_unix(now) + 300
        assert end_ts - start_ts == 86_400
      end
    end

    test "the skipped hour does not shift the boundary" do
      {_start_ts, end_ts} = EnergyPayload.window(~U[2026-03-29 01:05:00Z], "Europe/Berlin")
      assert end_ts == DateTime.to_unix(~U[2026-03-29 01:10:00Z])
    end
  end

  describe "the 2 kB limit" do
    test "holds for every plug at four-digit watts in every bucket and big totals" do
      producers =
        for i <- 1..2,
            do:
              "  - id: producer_#{i}\n    name: Balkonkraftwerk Süddach #{i}\n    role: producer\n"

      consumers =
        for i <- 1..11,
            do:
              "  - id: consumer_#{i}\n    name: Wärmepumpe Kellergeschoss #{i}\n    role: consumer\n"

      config = TestConfigs.plugs(Enum.join(producers ++ consumers))

      rows =
        for plug <- config.plugs, {ts, n} <- Enum.with_index(@start_ts..(@end_ts - 1)//600) do
          watts = if plug.role == :producer, do: -3_333.0, else: 833.25
          %{plug_id: plug.id, ts: ts, apower_w: watts, aenergy_wh: n * 3_000.0}
        end

      rows |> Enum.chunk_every(500) |> Enum.each(&Repo.insert_all(Sample, &1))

      mv = merge_variables(config)
      assert Enum.all?(mv["pv_w"] ++ mv["cons_w"], &(&1 == 9_999))
      assert mv["pv_kwh"] > 100 and mv["cons_kwh"] > 1000

      assert byte_size(json(config)) <= Push.max_payload_bytes()
    end
  end
end
