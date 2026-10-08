defmodule Ziwoas.Sensors.Sen66 do
  @moduledoc """
  Reads one SEN66 over its USB serial port and records every measurement of the configured
  device (ADR-0009). The port runs `cat` on the device; when the device goes away the
  program ends and the port is reopened with backoff. A warning of one kind is logged at most
  once a minute, so a babbling device cannot flood the log.
  """
  use GenServer

  require Logger

  alias Ziwoas.{Clock, Sensors}
  alias Ziwoas.Config.Sensor
  alias Ziwoas.Sensors.Sen66.Line

  @min_backoff_ms 1_000
  @max_backoff_ms 60_000
  @max_line_bytes 4_096
  @warn_interval_ms 60_000
  @logged_chars 120

  # `cat` ends with the device; the watcher kills it once the port closes stdin. `-F` takes
  # the next argument as the device whatever it starts with.
  @script """
  exec 3<&0
  stty -F "$1" raw -echo || exit
  cat -- "$1" & reader=$!
  { read -r _ <&3; kill $reader; } >/dev/null 2>&1 &
  watcher=$!
  wait $reader 2>/dev/null; status=$?
  kill $watcher 2>/dev/null
  wait $watcher 2>/dev/null
  exit $status
  """

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

  def child_spec(opts),
    do: %{
      id: {__MODULE__, Keyword.fetch!(opts, :sensor).id},
      start: {__MODULE__, :start_link, [opts]}
    }

  @spec port_command(String.t()) :: {String.t(), [String.t()]}
  def port_command(device_path), do: {"/bin/sh", ["-c", @script, "sen66", device_path]}

  @impl true
  def init(opts) do
    %Sensor{type: :sen66} = sensor = Keyword.fetch!(opts, :sensor)
    min_backoff_ms = Keyword.get(opts, :min_backoff_ms, @min_backoff_ms)

    state = %{
      sensor: sensor,
      command: Keyword.get_lazy(opts, :command, fn -> port_command(sensor.port) end),
      port: nil,
      min_backoff_ms: min_backoff_ms,
      backoff_ms: min_backoff_ms,
      firmware_version: nil,
      overlong: false,
      warned_at: %{}
    }

    {:ok, state, {:continue, :open}}
  end

  @impl true
  def handle_continue(:open, state), do: {:noreply, open(state)}

  @impl true
  def handle_info(:open, state), do: {:noreply, open(state)}

  def handle_info({port, {:data, {:noeol, _chunk}}}, %{port: port} = state),
    do: {:noreply, %{state | overlong: true}}

  def handle_info({port, {:data, {:eol, _rest}}}, %{port: port, overlong: true} = state) do
    state = warn(state, :overlong, "line longer than #{@max_line_bytes} bytes dropped")
    {:noreply, %{state | overlong: false}}
  end

  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    case Line.parse(line) do
      {:ok, message} ->
        {:noreply, handle_message(message, %{state | backoff_ms: state.min_backoff_ms})}

      {:error, reason} ->
        {:noreply,
         warn(
           state,
           {:unreadable, if(is_tuple(reason), do: elem(reason, 0), else: reason)},
           "unreadable line #{quoted(line)} (#{inspect(reason)})"
         )}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning(
      "SEN66 #{state.sensor.id}: serial reader ended with status #{status}, " <>
        "reopening in #{state.backoff_ms} ms"
    )

    Process.send_after(self(), :open, state.backoff_ms)

    {:noreply,
     %{
       state
       | port: nil,
         overlong: false,
         backoff_ms: min(state.backoff_ms * 2, @max_backoff_ms)
     }}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp open(state) do
    {executable, args} = state.command

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        line: @max_line_bytes,
        args: args
      ])

    %{state | port: port}
  end

  defp handle_message({_type, device_id, _payload}, %{sensor: %{id: id}} = state)
       when is_binary(device_id) and device_id != id,
       do: warn(state, :foreign_device, "line from device #{quoted(device_id)} dropped")

  defp handle_message({:hello, _id, hello}, state) do
    version = "#{hello.firmware} (#{hello.product} #{hello.sensor_fw})"

    if version != state.firmware_version,
      do: Logger.info("SEN66 #{state.sensor.id}: firmware #{version}")

    %{state | firmware_version: version}
  end

  defp handle_message({:measurement, id, values}, state) do
    taken_at = %{Clock.now() | microsecond: {0, 6}}
    values = Map.put(values, :firmware_version, state.firmware_version)

    case Sensors.create_reading(id, taken_at, values) do
      {:ok, _reading} -> state
      {:error, changeset} -> warn(state, :invalid, "invalid reading #{inspect(changeset.errors)}")
    end
  end

  defp handle_message({:device_error, _id, message}, state),
    do: warn(state, :device_error, "device reports #{quoted(message)}")

  defp warn(state, kind, message) do
    now = System.monotonic_time(:millisecond)
    recent = Map.reject(state.warned_at, fn {_kind, at} -> now - at >= @warn_interval_ms end)

    if Map.has_key?(recent, kind) do
      %{state | warned_at: recent}
    else
      Logger.warning("SEN66 #{state.sensor.id}: #{message}")
      %{state | warned_at: Map.put(recent, kind, now)}
    end
  end

  defp quoted(text), do: inspect(String.slice(text, 0, @logged_chars))
end
