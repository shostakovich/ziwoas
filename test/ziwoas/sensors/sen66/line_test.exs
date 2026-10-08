defmodule Ziwoas.Sensors.Sen66.LineTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Sensors.Sen66.Line

  @hello ~s({"type":"hello","device_id":"19B8E27966467D7A","product":"SEN66","sensor_fw":"4.0","firmware":"dev"})
  @measurement ~s({"type":"measurement","device_id":"19B8E27966467D7A","pm1_0":0.6,"pm2_5":1.3,"pm4_0":1.9,"pm10":2.2,"temperature":26.2,"humidity":51.0,"voc_index":99,"nox_index":1,"co2":1027,"device_status":0})

  defp measurement(changes) do
    @measurement |> JSON.decode!() |> Map.merge(changes) |> JSON.encode!()
  end

  defp without(key), do: @measurement |> JSON.decode!() |> Map.delete(key) |> JSON.encode!()

  test "a hello names the device, its sensor and its firmware" do
    assert Line.parse(@hello) ==
             {:ok,
              {:hello, "19B8E27966467D7A", %{product: "SEN66", sensor_fw: "4.0", firmware: "dev"}}}
  end

  test "a measurement carries every quantity" do
    assert Line.parse(@measurement) ==
             {:ok,
              {:measurement, "19B8E27966467D7A",
               %{
                 pm1_0: 0.6,
                 pm2_5: 1.3,
                 pm4_0: 1.9,
                 pm10: 2.2,
                 temperature: 26.2,
                 humidity: 51.0,
                 voc_index: 99,
                 nox_index: 1,
                 co2: 1027,
                 device_status: 0
               }}}
  end

  test "a carriage return before the newline is tolerated" do
    assert {:ok, {:hello, "19B8E27966467D7A", _}} = Line.parse(@hello <> "\r")
    assert {:ok, {:measurement, _, _}} = Line.parse(@measurement <> "\r")
  end

  test "an unknown quantity is null, whole numbers are fine for decimal quantities" do
    line = measurement(%{"pm10" => nil, "co2" => nil, "voc_index" => nil, "temperature" => 21})

    assert {:ok, {:measurement, _, values}} = Line.parse(line)
    assert %{pm10: nil, co2: nil, voc_index: nil} = values
    assert values.temperature === 21.0
  end

  test "an error report names the device, or nobody while the serial is unknown" do
    assert Line.parse(~s({"type":"error","device_id":null,"message":"SEN66 not found"})) ==
             {:ok, {:device_error, nil, "SEN66 not found"}}

    assert Line.parse(~s({"type":"error","device_id":"ABC","message":"pmError"})) ==
             {:ok, {:device_error, "ABC", "pmError"}}
  end

  test "garbage is no line" do
    for line <- ["", "\r", "garbage", ~s({"type":"measurement"), "\xFF\xFE"] do
      assert Line.parse(line) == {:error, :invalid_json}, inspect(line)
    end
  end

  test "JSON of the wrong shape is no line" do
    assert Line.parse("[1,2]") == {:error, :not_an_object}
    assert Line.parse("42") == {:error, :not_an_object}
    assert Line.parse(~s({"device_id":"A"})) == {:error, {:unknown_type, nil}}
    assert Line.parse(~s({"type":"bye","device_id":"A"})) == {:error, {:unknown_type, "bye"}}
  end

  test "a measurement must carry every field with its type" do
    assert Line.parse(without("pm4_0")) == {:error, {:invalid, :pm4_0}}
    assert Line.parse(without("device_status")) == {:error, {:invalid, :device_status}}
    assert Line.parse(measurement(%{"co2" => 612.5})) == {:error, {:invalid, :co2}}
    assert Line.parse(measurement(%{"humidity" => "48"})) == {:error, {:invalid, :humidity}}

    assert Line.parse(measurement(%{"device_status" => nil})) ==
             {:error, {:invalid, :device_status}}

    assert Line.parse(measurement(%{"device_status" => -1})) ==
             {:error, {:invalid, :device_status}}

    assert Line.parse(measurement(%{"device_id" => nil})) == {:error, {:invalid, :device_id}}
    assert Line.parse(measurement(%{"device_id" => ""})) == {:error, {:invalid, :device_id}}
  end

  test "a hello must name device, product, sensor firmware and firmware" do
    hello = JSON.decode!(@hello)

    for key <- ~w(device_id product sensor_fw firmware) do
      line = hello |> Map.put(key, 4) |> JSON.encode!()
      assert Line.parse(line) == {:error, {:invalid, String.to_existing_atom(key)}}
    end
  end

  test "an error report must carry a message" do
    assert Line.parse(~s({"type":"error","device_id":null})) == {:error, {:invalid, :message}}

    assert Line.parse(~s({"type":"error","device_id":7,"message":"x"})) ==
             {:error, {:invalid, :device_id}}
  end
end
