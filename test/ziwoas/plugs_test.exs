defmodule Ziwoas.PlugsTest do
  use Ziwoas.DataCase

  alias Ziwoas.Plugs
  alias Ziwoas.Plugs.Measurement

  @now ~U[2026-10-05 10:00:00.500000Z]
  @now_s 1_791_194_400

  describe "latest_measurements" do
    test "the newest sample per plug, online within the offline window" do
      insert_sample!("bkw", @now_s - 200, 10, 1)
      insert_sample!("bkw", @now_s - 5, 300, 2)
      insert_sample!("fridge", @now_s - 121, 80, 1)

      assert Plugs.latest_measurements(["bkw", "fridge", "lamp"], @now) == %{
               "bkw" => %Measurement{
                 plug_id: "bkw",
                 watt: 300.0,
                 last_seen_ts: @now_s - 5,
                 offline: false
               },
               "fridge" => %Measurement{
                 plug_id: "fridge",
                 watt: 80.0,
                 last_seen_ts: @now_s - 121,
                 offline: true
               },
               "lamp" => %Measurement{
                 plug_id: "lamp",
                 watt: nil,
                 last_seen_ts: nil,
                 offline: true
               }
             }
    end

    test "the age keeps its fraction of a second against a custom window" do
      insert_sample!("fridge", @now_s - 10, 80, 1)

      assert %{"fridge" => %Measurement{offline: true}} =
               Plugs.latest_measurements(["fridge"], @now, 10)

      assert %{"fridge" => %Measurement{offline: false}} =
               Plugs.latest_measurements(["fridge"], @now, 10.5)
    end

    test "no plugs, no query" do
      assert Plugs.latest_measurements([], @now) == %{}
    end
  end
end
