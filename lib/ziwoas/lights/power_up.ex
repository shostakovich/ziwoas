defmodule Ziwoas.Lights.PowerUp do
  @moduledoc false
  use GenServer

  require Logger

  alias Ziwoas.{Clock, Lights, Switching}
  alias Ziwoas.Govee.Bridge
  alias Ziwoas.Lights.{Commands, Light}
  alias Ziwoas.Plugs.Plug

  @deadline_s 60
  @retry_ms 5_000

  @type command :: {String.t(), map}
  @type failure :: :timeout | :plug_unreachable

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec deadline_s() :: pos_integer
  def deadline_s, do: @deadline_s

  @doc "Joins the attempt under way for the lamp, if there is one."
  @spec queue(String.t(), command) :: :queued | :idle
  def queue(key, command), do: call({:queue, key, command}, :idle)

  @doc "Switches the plug on and waits for the lamp; a lamp already starting takes the command."
  @spec begin(Light.t(), Plug.t(), command) :: :ok | {:error, :unavailable}
  def begin(light, plug, command),
    do: call({:begin, light, plug, command}, {:error, :unavailable})

  @spec starting() :: %{String.t() => %{since: DateTime.t(), on: boolean}}
  def starting, do: call(:starting, %{})

  defp call(request, fallback) do
    case GenServer.whereis(__MODULE__) do
      nil -> fallback
      pid -> GenServer.call(pid, request)
    end
  catch
    :exit, _reason -> fallback
  end

  @impl true
  def init(opts),
    do:
      {:ok,
       %{
         attempts: %{},
         retry_ms: Keyword.get(opts, :retry_ms, @retry_ms),
         tasks: Keyword.get(opts, :tasks, Ziwoas.Lights.Tasks)
       }}

  @impl true
  def handle_call({:queue, key, command}, _from, state) do
    if Map.has_key?(state.attempts, key),
      do: {:reply, :queued, take(state, key, command)},
      else: {:reply, :idle, state}
  end

  def handle_call({:begin, light, plug, command}, _from, state) do
    if Map.has_key?(state.attempts, light.key),
      do: {:reply, :ok, take(state, light.key, command)},
      else: start_attempt(state, light, plug, command)
  end

  def handle_call(:starting, _from, state) do
    starting =
      Map.new(state.attempts, fn {key, attempt} ->
        {key, %{since: attempt.started_at, on: wants_on?(attempt.commands)}}
      end)

    {:reply, starting, state}
  end

  @impl true
  def handle_info({:lamp_heard, key, telemetry}, state) do
    case state.attempts[key] do
      nil -> {:noreply, state}
      attempt -> {:noreply, heard(state, %{attempt | heard: true}, telemetry)}
    end
  end

  def handle_info({:tick, key}, state) do
    case state.attempts[key] do
      nil -> {:noreply, state}
      attempt -> {:noreply, tick(state, attempt)}
    end
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, switched(state, ref, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state),
    do: {:noreply, switched(state, ref, {:error, {:exit, reason}})}

  def handle_info(message, state) do
    Logger.debug("Lights.PowerUp: ignoring #{inspect(message)}")
    {:noreply, state}
  end

  defp start_attempt(state, light, plug, command) do
    case Bridge.watch(light.key) do
      :ok ->
        attempt = %{
          light: light,
          commands: merge([{"turn", %{on: true}}], command),
          started_at: Clock.now(),
          heard: false,
          pending: true,
          switch: Task.Supervisor.async_nolink(state.tasks, fn -> switch_on(plug) end).ref,
          tick: schedule_tick(state, light.key)
        }

        Lights.notify_updated(light.key)
        {:reply, :ok, put_attempt(state, attempt)}

      {:error, :unavailable} = error ->
        {:reply, error, state}
    end
  end

  defp switch_on(plug), do: Switching.switch(plug, :on, :manual)

  # A lamp already heard has power, whatever the plug answered.
  defp switched(state, ref, result) do
    case {Enum.find(Map.values(state.attempts), &(&1.switch == ref)), result} do
      {nil, _result} ->
        state

      {%{heard: false} = attempt, {:error, _reason}} ->
        give_up(state, attempt.light.key, :plug_unreachable)

      {attempt, _result} ->
        put_attempt(state, %{attempt | switch: nil})
    end
  end

  defp heard(state, %{pending: true} = attempt, _telemetry),
    do: put_attempt(state, deliver(attempt))

  defp heard(state, attempt, telemetry) do
    if arrived?(attempt, telemetry),
      do: finish(state, attempt.light.key),
      else: put_attempt(state, attempt)
  end

  defp tick(state, attempt) do
    key = attempt.light.key

    cond do
      DateTime.diff(Clock.now(), attempt.started_at) < @deadline_s ->
        Bridge.watch(key)
        attempt = if attempt.heard, do: deliver(attempt), else: attempt
        put_attempt(state, %{attempt | tick: schedule_tick(state, key, attempt.tick)})

      attempt.heard ->
        attempt = if attempt.pending, do: deliver(attempt), else: attempt
        state |> put_attempt(attempt) |> finish(key)

      true ->
        give_up(state, key, :timeout)
    end
  end

  defp take(state, key, command) do
    update_in(state.attempts[key], &%{&1 | commands: merge(&1.commands, command), pending: true})
  end

  defp merge(_commands, {"turn", %{on: false}} = off), do: [off]

  defp merge([{"turn", %{on: false}}], command), do: merge([{"turn", %{on: true}}], command)

  defp merge(commands, command),
    do: Enum.reject(commands, &(kind(&1) == kind(command))) ++ [command]

  defp kind({"zone", %{zone: zone}}), do: {"zone", zone}
  defp kind({name, _values}) when name in ["color", "color_temp"], do: "colour"
  defp kind({name, _values}), do: name

  defp deliver(attempt) do
    attempt.commands
    |> Enum.sort_by(&(kind(&1) != "turn"))
    |> Enum.each(fn {name, values} -> Commands.deliver(attempt.light, name, values) end)

    %{attempt | pending: false}
  end

  defp arrived?(_attempt, nil), do: false
  defp arrived?(attempt, telemetry), do: telemetry[:on] == wants_on?(attempt.commands)

  defp wants_on?([{"turn", %{on: false}}]), do: false
  defp wants_on?(_commands), do: true

  defp finish(state, key), do: drop(state, key, &Lights.notify_updated/1)

  defp give_up(state, key, failure),
    do: drop(state, key, &Lights.notify_power_up_failed(&1, failure))

  # The news goes out before the watch ends: whoever sees the watch end has been told.
  defp drop(state, key, tell) do
    Process.cancel_timer(state.attempts[key].tick)
    tell.(key)
    Bridge.unwatch(key)
    %{state | attempts: Map.delete(state.attempts, key)}
  end

  defp put_attempt(state, attempt),
    do: %{state | attempts: Map.put(state.attempts, attempt.light.key, attempt)}

  defp schedule_tick(state, key, previous \\ nil) do
    if previous, do: Process.cancel_timer(previous)
    Process.send_after(self(), {:tick, key}, state.retry_ms)
  end
end
