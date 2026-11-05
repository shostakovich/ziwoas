defmodule Ziwoas.Fritz.HeatersTest do
  use Ziwoas.DataCase

  import ExUnit.CaptureLog

  alias Ziwoas.{FakeFritzBox, Heating, Repo, TestClock}
  alias Ziwoas.Fritz.{Heaters, Thermostat}
  alias Ziwoas.Heating.Heater

  @moduletag :shared_sandbox

  @ain "11960 0123456"
  @key "119600123456"

  defp thursday(time), do: "2026-11-05T#{time}+01:00"

  defp box(tsoll \\ 253, extra \\ %{}),
    do: FakeFritzBox.start(%{@ain => Map.merge(%{name: "Wohnzimmer", tsoll: tsoll}, extra)})

  # The first poll waits for the timer, which the test fires by hand.
  defp start(client) do
    test = self()

    pid =
      start_supervised!(
        {Heaters,
         client: client,
         zone: "Europe/Berlin",
         timer: fn _pid, message, delay -> send(test, {:armed, message, delay}) end}
      )

    poll(pid)
  end

  defp poll(pid) do
    send(pid, :poll)
    :sys.get_state(pid)
    pid
  end

  defp weekday_window,
    do:
      Heating.save_window(@key, %{
        on_at_time: "07:00",
        off_at_time: "19:00",
        days: [1, 2, 3, 4, 5]
      })

  defp heater, do: Heating.get_heater(@key)
  defp pressed, do: Heater.press(heater())
  defp written, do: Heater.written(heater())

  setup do
    TestClock.freeze(thursday("12:00:00"))
    :ok
  end

  test "the first poll waits a few seconds after the start, the next ones a minute" do
    {_box, client} = box()
    start(client)

    assert_received {:armed, :poll, 5_000}
    assert_received {:armed, :poll, 60_000}
  end

  test "a poll registers the thermostat, keeps its readings and tells subscribers" do
    Heating.subscribe()
    {_box, client} = box()
    start(client)

    assert_received {:heaters, %{@key => %Thermostat{name: "Wohnzimmer", measured_c: 20.5}}}
    assert [%Heater{key: @key, ain: @ain, name: "Wohnzimmer", heat_c: 21.0}] = Heating.heaters()
    assert %{@key => %Thermostat{target: :off}} = Heating.readings()
  end

  test "readings are there before the first poll only as unknown" do
    {_box, client} = box()

    start_supervised!(
      {Heaters, client: client, zone: "Europe/Berlin", timer: fn _, _, _ -> :ok end}
    )

    assert Heating.readings() == nil
  end

  describe "a newly found thermostat" do
    test "that is off is taken as it is" do
      {_box, client} = box(253)
      start(client)

      refute_received {:sethkrtsoll, _, _}
      assert written() == :off
      assert pressed() == nil
    end

    test "that heats keeps heating as a press from the device, for at most four hours" do
      {_box, client} = box(42)
      pid = start(client)

      refute_received {:sethkrtsoll, _, _}
      assert written() == {:heat, 21.0}
      assert {:heat, _at} = pressed()

      TestClock.freeze(thursday("16:00:00"))
      poll(pid)
      assert_received {:sethkrtsoll, @ain, "253"}
    end
  end

  test "a window heats at the Heiztemperatur and writes only when the state changes" do
    {_box, client} = box()
    pid = start(client)

    weekday_window()
    :sys.get_state(pid)
    assert_received {:sethkrtsoll, @ain, "42"}

    poll(pid)
    refute_received {:sethkrtsoll, _, _}

    TestClock.freeze(thursday("19:00:00"))
    poll(pid)
    assert_received {:sethkrtsoll, @ain, "253"}
  end

  test "pausing and deleting a window decide again at once" do
    {_box, client} = box()
    pid = start(client)
    {:ok, window} = weekday_window()
    :sys.get_state(pid)
    assert_received {:sethkrtsoll, @ain, "42"}

    window = Heating.set_window_enabled(window, false)
    :sys.get_state(pid)
    assert_received {:sethkrtsoll, @ain, "253"}

    Heating.set_window_enabled(window, true)
    :sys.get_state(pid)
    assert_received {:sethkrtsoll, @ain, "42"}

    Heating.delete_window(Heating.window(@key, to_string(window.id)))
    :sys.get_state(pid)
    assert_received {:sethkrtsoll, @ain, "253"}
  end

  test "a temperature set on the thermostat is a press from the device and stays as set" do
    {box, client} = box()
    pid = start(client)

    TestClock.freeze(thursday("14:01:00"))
    FakeFritzBox.turn(box, @ain, 46)
    poll(pid)

    assert {:heat, at} = pressed()
    assert DateTime.compare(at, usec(Ziwoas.Clock.parse!(thursday("14:01:00")))) == :eq
    refute_received {:sethkrtsoll, _, _}
    assert written() == {:heat, 23.0}

    TestClock.freeze(thursday("18:00:00"))
    poll(pid)
    refute_received {:sethkrtsoll, _, _}
    assert FakeFritzBox.tsoll(box, @ain) == 46

    TestClock.freeze(thursday("18:01:00"))
    poll(pid)
    assert_received {:sethkrtsoll, @ain, "253"}
    assert {:heat, ^at} = pressed()
  end

  test "a window starting while a temperature set by hand heats keeps that temperature" do
    {box, client} = box()
    pid = start(client)
    TestClock.freeze(thursday("06:00:00"))
    FakeFritzBox.turn(box, @ain, 46)
    poll(pid)
    weekday_window()

    TestClock.freeze(thursday("07:00:00"))
    poll(pid)

    refute_received {:sethkrtsoll, _, _}
    assert FakeFritzBox.tsoll(box, @ain) == 46
  end

  test "a window start after frost protection heats at the Heiztemperatur" do
    {box, client} = box()
    pid = start(client)
    TestClock.freeze("2026-11-05T05:00:00+01:00")
    FakeFritzBox.turn(box, @ain, 46)
    poll(pid)

    TestClock.freeze("2026-11-05T22:00:00+01:00")
    poll(pid)
    assert_received {:sethkrtsoll, @ain, "253"}

    {:ok, _} =
      Heating.save_window(@key, %{on_at_time: "06:00", off_at_time: "08:00", days: [5]})

    TestClock.freeze("2026-11-06T06:00:00+01:00")
    poll(pid)
    assert_received {:sethkrtsoll, @ain, "42"}
  end

  test "turning the thermostat off by hand is a press for frost protection" do
    weekday_window()
    {box, client} = box(42)
    pid = start(client)

    FakeFritzBox.turn(box, @ain, 253)
    poll(pid)

    assert {:frost, _at} = pressed()
    refute_received {:sethkrtsoll, _, _}
  end

  test "a target in flux is no press: a command in transit, an open window or a boost" do
    {box, client} = box()
    pid = start(client)

    for flag <- [:txbusy, :window_open, :boost] do
      FakeFritzBox.put(box, @ain, flag, true)
      FakeFritzBox.turn(box, @ain, 46)
      poll(pid)

      assert pressed() == nil
      assert written() == :off
      FakeFritzBox.put(box, @ain, flag, false)
      FakeFritzBox.turn(box, @ain, 253)
    end
  end

  test "after downtime the latest due edge applies at the first poll" do
    weekday_window()

    %Heater{key: @key, ain: @ain, name: "Wohnzimmer"}
    |> Repo.insert!()
    |> Heating.put_written!({:heat, 21.0})

    TestClock.freeze(thursday("19:30:00"))
    {_box, client} = box(42)
    start(client)

    assert_received {:sethkrtsoll, @ain, "253"}
    assert pressed() == nil
  end

  test "a write the box refuses is logged, changes nothing and is tried again" do
    {box, client} = box()
    pid = start(client)
    FakeFritzBox.set(box, :refuse, true)

    log =
      capture_log(fn ->
        weekday_window()
        :sys.get_state(pid)
      end)

    assert log =~ "FritzHeaters #{@key}: {:http_status, 500}"
    assert written() == :off

    FakeFritzBox.set(box, :refuse, false)
    poll(pid)
    assert_received {:sethkrtsoll, @ain, "42"}
    assert written() == {:heat, 21.0}
  end

  test "an unreachable box makes the readings unknown and writes nothing" do
    {box, client} = box()
    pid = start(client)

    FakeFritzBox.set(box, :down, true)
    log = capture_log(fn -> poll(pid) end)

    assert log =~ "FritzHeaters"
    assert Heating.readings() == nil
  end

  test "an absent thermostat gets no writes, also when one was written before" do
    weekday_window()

    %Heater{key: @key, ain: @ain, name: "Wohnzimmer"}
    |> Repo.insert!()
    |> Heating.put_written!(:off)

    {_box, client} = box(253, %{present: false})
    start(client)

    refute_received {:sethkrtsoll, _, _}
    assert %{@key => %Thermostat{present: false}} = Heating.readings()
    assert Heating.switch(@key, :heat) == {:error, :offline}
    assert Heating.step_heat_c(@key, :up) == {:error, :offline}
  end

  describe "commands" do
    setup do
      {box, client} = box()
      pid = start(client)
      %{box: box, pid: pid}
    end

    test "a press heats at once and is recorded as a press" do
      assert {:ok, %{state: :heat, cause: :manual}} = Heating.switch(@key, :heat)

      assert_received {:sethkrtsoll, @ain, "42"}
      assert {:heat, _at} = pressed()
      assert written() == {:heat, 21.0}
      assert %{@key => %Thermostat{target: {:heat, 21.0}}} = Heating.readings()
    end

    test "a press the box refuses is an error and changes nothing", %{box: box} do
      FakeFritzBox.set(box, :refuse, true)

      assert {:error, {:http_status, 500}} = Heating.switch(@key, :heat)
      assert pressed() == nil
      assert written() == :off
    end

    test "a press the box does not confirm is an error, not taken as written", %{
      box: box,
      pid: pid
    } do
      FakeFritzBox.set(box, :inval, true)

      assert {:error, {:unexpected_response, "inval"}} = Heating.switch(@key, :heat)
      assert pressed() == nil
      assert written() == :off
      assert %{@key => %Thermostat{target: :off}} = Heating.readings()

      FakeFritzBox.set(box, :inval, false)
      poll(pid)

      assert pressed() == nil
      assert written() == :off
      refute_received {:sethkrtsoll, _, _}
    end

    test "a command whose caller has given up is dropped", %{pid: pid} do
      assert GenServer.call(pid, {{:switch, @key, :heat}, System.monotonic_time(:millisecond)}) ==
               {:error, :deadline_exceeded}

      refute_received {:sethkrtsoll, _, _}
      assert pressed() == nil
    end

    test "a command without time left for the request is dropped", %{pid: pid} do
      deadline = System.monotonic_time(:millisecond) + 1_000

      assert GenServer.call(pid, {{:switch, @key, :heat}, deadline}) ==
               {:error, :deadline_exceeded}

      refute_received {:sethkrtsoll, _, _}
      assert pressed() == nil
      assert written() == :off
    end

    test "a warmer Heiztemperatur applies at once while the heater heats" do
      Heating.switch(@key, :heat)
      assert_received {:sethkrtsoll, @ain, "42"}

      assert {:ok, %Heater{heat_c: 21.5}} = Heating.step_heat_c(@key, :up)
      assert_received {:sethkrtsoll, @ain, "43"}
      assert written() == {:heat, 21.5}
    end

    test "a new Heiztemperatur in frost protection is only kept" do
      assert {:ok, %Heater{heat_c: 20.5}} = Heating.step_heat_c(@key, :down)
      refute_received {:sethkrtsoll, _, _}

      Heating.switch(@key, :heat)
      assert_received {:sethkrtsoll, @ain, "41"}
    end

    test "a Heiztemperatur the box refuses is kept as it was", %{box: box} do
      Heating.switch(@key, :heat)
      FakeFritzBox.set(box, :refuse, true)

      assert {:error, {:http_status, 500}} = Heating.step_heat_c(@key, :up)
      assert heater().heat_c == 21.0
    end

    test "the Heiztemperatur stops at 19 and 22 °C" do
      Heating.put_heat_c!(heater(), 22.0)
      assert Heating.step_heat_c(@key, :up) == {:error, :limit}

      Heating.put_heat_c!(heater(), 19.0)
      assert Heating.step_heat_c(@key, :down) == {:error, :limit}
      assert heater().heat_c == 19.0
    end

    test "an unknown heater is not found" do
      assert Heating.switch("nope", :heat) == {:error, :not_found}
      assert Heating.step_heat_c("nope", :up) == {:error, :not_found}
    end
  end

  test "without the process commands are unavailable and the readings unknown" do
    assert Heating.switch(@key, :heat) == {:error, :unavailable}
    assert Heating.readings() == nil
  end
end
