defmodule Ziwoas.Shelly.StatusTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Shelly.Status

  @full %{
    "id" => 0,
    "output" => true,
    "apower" => 50.5,
    "aenergy" => %{"total" => 1234.5, "by_minute" => [1, 2, 3], "minute_ts" => 1}
  }

  test "a full status replaces whatever was kept" do
    assert Status.replace(@full) == @full
  end

  test "a delta changes only its keys, nested maps key by key" do
    status = Status.merge(@full, %{"apower" => 7, "aenergy" => %{"total" => 1240.0}})

    assert status["apower"] == 7
    assert status["output"] == true
    assert status["aenergy"] == %{"total" => 1240.0, "by_minute" => [1, 2, 3], "minute_ts" => 1}
  end

  test "null removes a key" do
    refute Map.has_key?(Status.merge(@full, %{"output" => nil}), "output")
  end

  test "a delta onto nothing starts the status" do
    assert Status.merge(%{}, %{"aenergy" => %{"total" => 1.0}}) == %{
             "aenergy" => %{"total" => 1.0}
           }
  end

  test "a delta that is not a map changes nothing" do
    assert Status.merge(@full, "nope") == @full
  end

  test "the reading: watts and counter as floats, the relay as a boolean" do
    assert Status.reading(@full) == {:ok, %{apower_w: 50.5, aenergy_wh: 1234.5, output: true}}

    assert Status.reading(%{@full | "output" => "on"}) ==
             {:ok, %{apower_w: 50.5, aenergy_wh: 1234.5, output: nil}}
  end

  test "a status without numeric apower and aenergy.total has no reading" do
    for status <- [
          %{},
          %{"aenergy" => %{"total" => 1.0}},
          %{"apower" => 5.0},
          %{"apower" => 5.0, "aenergy" => 12.0},
          %{"apower" => 5.0, "aenergy" => %{}},
          %{"apower" => "5", "aenergy" => %{"total" => 1.0}},
          %{"apower" => 5.0, "aenergy" => %{"total" => nil}}
        ] do
      assert Status.reading(status) == {:error, :incomplete_status}
    end
  end
end
