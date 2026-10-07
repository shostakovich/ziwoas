defmodule Ziwoas.FakeGoveeBridge do
  @moduledoc false
  use GenServer

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Ziwoas.Govee.Bridge)

  @impl true
  def init(opts),
    do:
      {:ok,
       %{
         test: Keyword.fetch!(opts, :test),
         answer: Keyword.get(opts, :answer, :ok),
         sleep_ms: Keyword.get(opts, :sleep_ms, 0)
       }}

  @impl true
  def handle_call({:command, key, verb}, _from, state) do
    send(state.test, {:govee, key, verb})
    Process.sleep(state.sleep_ms)
    {:reply, state.answer, state}
  end
end
