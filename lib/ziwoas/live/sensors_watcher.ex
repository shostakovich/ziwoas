defmodule Ziwoas.Live.SensorsWatcher do
  @moduledoc """
  Bridge for live updates while Rails' `SensorPollJob` still writes
  `sensor_readings` (issue #158, until the collector moves in Phase 4): polls
  the newest reading id and, when it changes, does what Rails'
  `SensorsBroadcaster.refresh` does — `{:sensors_updated}` on the `sensors`
  topic (the Sensoren dashboard) and `{:weather_updated}` on `weather` (the
  current conditions there show the outdoor sensor). Nothing is broadcast
  without configured sensors, like Rails.

  Options: `:interval_ms` (default 5 s), `:name`, `:repo` (a dynamic repo to
  read instead of `Ziwoas.Repo`, for tests).
  """
  use GenServer

  require Logger

  alias Ziwoas.{Config, Repo, Sensors}

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
    if id != state.last_id and id != :error, do: broadcast()
    {:noreply, schedule(%{state | last_id: if(id == :error, do: state.last_id, else: id)})}
  end

  defp schedule(state) do
    Process.send_after(self(), :poll, state.interval)
    state
  end

  # A busy or missing database is no reason to crash the bridge; try again next time.
  defp newest_id do
    Sensors.max_id()
  rescue
    error ->
      Logger.warning("SensorsWatcher: #{Exception.message(error)}")
      :error
  end

  defp broadcast do
    if Config.app_config().sensors != [] do
      Phoenix.PubSub.broadcast(Ziwoas.PubSub, "sensors", {:sensors_updated})
      Phoenix.PubSub.broadcast(Ziwoas.PubSub, "weather", {:weather_updated})
    end
  rescue
    error in Config.Error -> Logger.warning("SensorsWatcher: #{Exception.message(error)}")
  end
end
