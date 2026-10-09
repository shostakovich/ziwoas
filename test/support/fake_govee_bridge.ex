defmodule Ziwoas.FakeGoveeBridge do
  @moduledoc false
  use GenServer

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Ziwoas.Govee.Bridge)

  @doc "Plays a LAN reply of the lamp to its watcher."
  def hear(key, telemetry), do: GenServer.call(Ziwoas.Govee.Bridge, {:hear, key, telemetry})

  @impl true
  def init(opts),
    do:
      {:ok,
       %{
         test: Keyword.fetch!(opts, :test),
         answer: Keyword.get(opts, :answer, :ok),
         sleep_ms: Keyword.get(opts, :sleep_ms, 0),
         silent: Keyword.get(opts, :silent, []),
         watchers: %{}
       }}

  @impl true
  def handle_call({:command, key, verb}, _from, state) do
    send(state.test, {:govee, key, verb})
    Process.sleep(state.sleep_ms)
    answer = if is_function(state.answer, 1), do: state.answer.(verb), else: state.answer
    {:reply, answer, state}
  end

  def handle_call({:silent?, key}, _from, state), do: {:reply, key in state.silent, state}

  def handle_call({:watch, key, watcher}, _from, state) do
    send(state.test, {:govee_watch, key})
    {:reply, :ok, put_in(state.watchers[key], watcher)}
  end

  def handle_call({:unwatch, key}, _from, state) do
    send(state.test, {:govee_unwatch, key})
    {:reply, :ok, %{state | watchers: Map.delete(state.watchers, key)}}
  end

  def handle_call({:hear, key, telemetry}, _from, state) do
    if watcher = state.watchers[key], do: send(watcher, {:lamp_heard, key, telemetry})
    {:reply, :ok, state}
  end
end
