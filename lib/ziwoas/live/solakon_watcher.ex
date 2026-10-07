defmodule Ziwoas.Live.SolakonWatcher do
  @moduledoc """
  Bridge for the inverter's live updates while Rails' `Solakon::MonitorJob`
  still writes `solakon_readings` (issue #158, until Phase 4). The job reads
  the inverter every 30 s and then calls `DashboardBroadcaster.broadcast_live`;
  here the newest reading id is polled every `:interval_ms` (default 5 s) and
  a change goes out as `{:solakon_reading, id}` on the `solakon` topic, which
  the dashboard and the PV page treat as a live beat.

  Options as `Ziwoas.Live.SensorsWatcher`: `:interval_ms`, `:name`, `:repo`.
  """
  use GenServer

  import Ecto.Query

  require Logger

  alias Ziwoas.Repo
  alias Ziwoas.Solakon.Reading

  @topic "solakon"
  @default_interval_ms 5_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    if repo = opts[:repo], do: Repo.put_dynamic_repo(repo)
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
    {:ok, schedule(%{interval: interval, last_id: newest_id()})}
  end

  @impl true
  def handle_info(:poll, state) do
    id = newest_id()

    if id != state.last_id and id != :error,
      do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, @topic, {:solakon_reading, id})

    {:noreply, schedule(%{state | last_id: if(id == :error, do: state.last_id, else: id)})}
  end

  defp schedule(state) do
    Process.send_after(self(), :poll, state.interval)
    state
  end

  # A busy or missing database is no reason to crash the bridge; try again next time.
  defp newest_id do
    Repo.one(from r in Reading, select: max(r.id))
  rescue
    error ->
      Logger.warning("SolakonWatcher: #{Exception.message(error)}")
      :error
  end
end
