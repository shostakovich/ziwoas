defmodule Ziwoas.Fritz.Bridge do
  @moduledoc false
  use GenServer

  require Logger

  alias Ziwoas.Fritz.DectClient
  alias Ziwoas.Plugs.Ingest

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

  def child_spec(opts),
    do: %{
      id: {__MODULE__, Keyword.fetch!(opts, :plug).id},
      start: {__MODULE__, :start_link, [opts]}
    }

  @impl true
  def init(opts) do
    state = %{
      plug: Keyword.fetch!(opts, :plug),
      client: Keyword.fetch!(opts, :client),
      poll: Keyword.fetch!(opts, :poll),
      ingest: Ingest.new(Keyword.get(opts, :ingest, [])),
      timer: Keyword.get(opts, :timer, &Process.send_after/3),
      last_apower_w: 0.0
    }

    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = poll(state)
    state.timer.(self(), :poll, round(interval(state) * 1000))
    {:noreply, state}
  end

  def poll(state) do
    case DectClient.fetch(state.client, state.plug.ain) do
      {:ok, reading, client} ->
        ingest = Ingest.record(state.ingest, state.plug, Map.put(reading, :output, nil))
        %{state | client: client, ingest: ingest, last_apower_w: reading.apower_w}

      {:error, reason, client} ->
        Logger.warning("FritzBridge #{state.plug.id}: #{inspect(reason)}")
        %{state | client: client}
    end
  end

  def interval(%{last_apower_w: watts, poll: poll}) do
    if watts > poll.idle_threshold_w,
      do: poll.active_interval_seconds,
      else: poll.idle_interval_seconds
  end
end
