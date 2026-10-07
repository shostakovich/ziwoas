defmodule Ziwoas.FakeGoveeBridge do
  @moduledoc """
  Stands in for `Ziwoas.Govee.Bridge` under its name: every command goes to the
  test as `{:govee, key, verb}` and is answered with `:answer` (default `:ok`),
  after `:sleep_ms` (default 0) — longer than the bridge's timeout makes it busy.
  The name is global, so a test that starts it is not async.
  """
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
