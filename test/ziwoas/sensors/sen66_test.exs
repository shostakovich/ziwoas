defmodule Ziwoas.Sensors.Sen66Test do
  use Ziwoas.DataCase

  import ExUnit.CaptureLog

  alias Ziwoas.Config.Sensor
  alias Ziwoas.{Repo, Sensors, TestClock}
  alias Ziwoas.Sensors.{Reading, Sen66}

  @moduletag :shared_sandbox
  @moduletag :tmp_dir

  @id "19B8E27966467D7A"
  @sensor %Sensor{id: @id, name: "Raumluft", type: :sen66, room: "Wohnzimmer", port: "/dev/x"}

  @hello ~s({"type":"hello","device_id":"#{@id}","product":"SEN66","sensor_fw":"4.0","firmware":"dev"})
  @measurement ~s({"type":"measurement","device_id":"#{@id}","pm1_0":0.6,"pm2_5":1.3,"pm4_0":1.9,"pm10":2.2,"temperature":26.2,"humidity":51.0,"voc_index":99,"nox_index":1,"co2":1027,"device_status":0})

  setup do
    TestClock.freeze("2026-10-08T12:00:00.250000Z")
    Sensors.subscribe()
    :ok
  end

  # A program that prints `lines`, then runs `finally` (by default it waits for the port to close).
  defp fake!(dir, lines, finally \\ "exec cat >/dev/null") do
    path = Path.join(dir, "fake_sen66.sh")
    printed = Enum.map_join(lines, "\n", &"printf '%s\\n' '#{&1}'")
    File.write!(path, printed <> "\n" <> finally <> "\n")
    {"/bin/sh", [path]}
  end

  defp start!(command, opts \\ []),
    do: start_supervised!({Sen66, [sensor: @sensor, command: command] ++ opts})

  test "stores the device's measurements at the whole second, with the hello's firmware",
       %{tmp_dir: dir} do
    start!(fake!(dir, [@hello, @measurement <> "\r"]))

    assert_receive {:reading, %Reading{} = reading}, 2_000

    assert %{
             device_id: @id,
             taken_at: ~U[2026-10-08 12:00:00.000000Z],
             firmware_version: "dev (SEN66 4.0)",
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
           } = reading

    assert Sensors.latest(@id).id == reading.id
  end

  test "a measurement before any hello is stored without a firmware", %{tmp_dir: dir} do
    start!(fake!(dir, [@measurement]))

    assert_receive {:reading, %Reading{firmware_version: nil, co2: 1027}}, 2_000
  end

  test "foreign devices, garbage, error reports and overlong lines are logged and dropped",
       %{tmp_dir: dir} do
    foreign = String.replace(@measurement, @id, "0000000000000000")
    overlong = String.duplicate("x", 5_000)
    error = ~s({"type":"error","device_id":null,"message":"SEN66 not found"})
    last = String.replace(@measurement, ~s("co2":1027), ~s("co2":700))

    log =
      capture_log(fn ->
        start!(fake!(dir, [foreign, "garbage", error, overlong, ~s({"type":"bye"}), last]))
        assert_receive {:reading, %Reading{co2: 700}}, 2_000
      end)

    refute_received {:reading, _}
    assert [%Reading{co2: 700}] = Repo.all(Reading)

    assert log =~ ~s(SEN66 #{@id}: line from device "0000000000000000" dropped)
    assert log =~ ~s(SEN66 #{@id}: unreadable line "garbage" (:invalid_json\))
    assert log =~ ~s(SEN66 #{@id}: device reports "SEN66 not found")
    assert log =~ "SEN66 #{@id}: line longer than 4096 bytes dropped"
    assert log =~ "{:unknown_type, \"bye\"}"
  end

  test "a device's message is quoted and cut short, so it stays on one line", %{tmp_dir: dir} do
    message = "I2C failure\\nretrying" <> String.duplicate("x", 300)
    error = ~s({"type":"error","device_id":null,"message":"#{message}"})

    log =
      capture_log(fn ->
        start!(fake!(dir, [error, @measurement]))
        assert_receive {:reading, _}, 2_000
      end)

    assert log =~ ~s(SEN66 #{@id}: device reports "I2C failure\\nretrying)
    refute log =~ String.duplicate("x", 200)
  end

  test "a warning repeated within a minute is logged once", %{tmp_dir: dir} do
    log =
      capture_log(fn ->
        start!(fake!(dir, ["garbage", "garbage", "garbage", @measurement]))
        assert_receive {:reading, _}, 2_000
      end)

    assert length(String.split(log, "unreadable line")) == 2
  end

  test "reopens the port after the program ends, backing off until a line arrives",
       %{tmp_dir: dir} do
    runs = Path.join(dir, "runs")

    # Fails twice, then delivers a measurement and ends again.
    command =
      fake!(dir, [], """
      echo run >> "#{runs}"
      [ $(wc -l < "#{runs}") -le 2 ] && exit 1
      printf '%s\\n' '#{@measurement}'
      exit 0
      """)

    log =
      capture_log(fn ->
        start!(command, min_backoff_ms: 10)
        assert_receive {:reading, _}, 2_000
        assert_receive {:reading, _}, 2_000
      end)

    assert log =~ "serial reader ended with status 1, reopening in 10 ms"
    assert log =~ "serial reader ended with status 1, reopening in 20 ms"
    assert log =~ "serial reader ended with status 0, reopening in 10 ms"
  end

  describe "the port's own program" do
    setup %{tmp_dir: dir} do
      stty = Path.join(dir, "stty")
      File.write!(stty, "#!/bin/sh\nexit 0\n")
      File.chmod!(stty, 0o755)
      :ok
    end

    defp real_command(dir, device) do
      {shell, args} = Sen66.port_command(device)
      {"/usr/bin/env", ["PATH=#{dir}:/usr/bin:/bin", shell | args]}
    end

    test "reads the device's lines and ends with the device", %{tmp_dir: dir} do
      device = Path.join(dir, "tty")
      File.write!(device, @hello <> "\r\n" <> @measurement <> "\r\n")

      log =
        capture_log(fn ->
          pid = start!(real_command(dir, device), min_backoff_ms: 60_000)
          assert_receive {:reading, %Reading{firmware_version: "dev (SEN66 4.0)"}}, 2_000
          assert eventually(fn -> :sys.get_state(pid).port == nil end)
        end)

      assert log =~ "serial reader ended with status 0"
    end

    test "a device stty cannot set up ends the program, and it is retried", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "stty"), "#!/bin/sh\nexit 1\n")
      device = Path.join(dir, "tty")
      File.write!(device, @measurement <> "\n")

      log =
        capture_log(fn ->
          pid = start!(real_command(dir, device), min_backoff_ms: 10)
          assert eventually(fn -> :sys.get_state(pid).backoff_ms >= 40 end)
        end)

      refute_received {:reading, _}
      assert log =~ "serial reader ended with status 1, reopening in 10 ms"
      assert log =~ "serial reader ended with status 1, reopening in 20 ms"
    end

    test "a device path starting with a dash is still a path", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "-tty"), @measurement <> "\n")
      {env, args} = real_command(dir, "-tty")

      assert {@measurement <> "\n", 0} = System.cmd(env, args, cd: dir, stderr_to_stdout: true)
    end

    test "stops reading the device once the port closes", %{tmp_dir: dir} do
      device = Path.join(dir, "tty")
      {_, 0} = System.cmd("mkfifo", [device])

      pid = start!(real_command(dir, device))
      {:ok, writer} = :file.open(device, [:write, :raw])
      :ok = :file.write(writer, @measurement <> "\n")
      assert_receive {:reading, _}, 2_000

      stop_supervised!({Sen66, @id})
      refute Process.alive?(pid)

      assert eventually_broken?(writer, 50)
    end
  end

  defp eventually(check, attempts \\ 100) do
    cond do
      check.() -> true
      attempts == 0 -> false
      true -> Process.sleep(20) && eventually(check, attempts - 1)
    end
  end

  defp eventually_broken?(_writer, 0), do: false

  defp eventually_broken?(writer, attempts) do
    case :file.write(writer, "\n") do
      {:error, :epipe} ->
        true

      :ok ->
        Process.sleep(20)
        eventually_broken?(writer, attempts - 1)
    end
  end
end
