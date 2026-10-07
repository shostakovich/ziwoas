defmodule Ziwoas.Fritz.Bridge do
  @moduledoc """
  Rails' `FritzMqttBridge` (task `fritz_bridge`), one process per Fritz!DECT plug:
  polls the plug through the Fritz!Box (`Ziwoas.Fritz.DectClient`, its own session)
  and publishes the reading the way a Shelly would — `{"apower":…,"aenergy":{"total":…}}`
  on `<prefix>/<plug>/status/switch:0` — so `plug_ingest` takes it from there.
  Every `active_interval_seconds` while the plug draws more than
  `idle_threshold_w`, else every `idle_interval_seconds`; the first poll is at once.

  As owner it publishes on the `ziwoas-phoenix-fritz` connection (Tortoise
  reconnects with backoff; a failed publish is logged and the next poll comes as
  scheduled). In shadow mode it polls and only logs what it would publish: the
  shared broker hears nothing from a shadow.
  """
  use GenServer

  require Logger

  alias Ziwoas.{Mqtt, Ownership, RubyJSON}
  alias Ziwoas.Fritz.DectClient

  @task :fritz_bridge
  @client_id "ziwoas-phoenix-fritz"

  def client_id, do: @client_id

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

  def child_spec(opts),
    do: %{
      id: {__MODULE__, Keyword.fetch!(opts, :plug).id},
      start: {__MODULE__, :start_link, [opts]}
    }

  @doc """
  Options: `:plug`, `:client` (a `DectClient`), `:poll` (`Config.FritzPoll`),
  `:topic_prefix`, `:owner` (default the task's mode); `:publish` (a function of
  topic and payload) and `:timer` (`Process.send_after/3`'s shape) for tests.
  """
  @impl true
  def init(opts) do
    state = %{
      plug: Keyword.fetch!(opts, :plug),
      client: Keyword.fetch!(opts, :client),
      poll: Keyword.fetch!(opts, :poll),
      topic_prefix: Keyword.fetch!(opts, :topic_prefix),
      publish:
        Keyword.get_lazy(opts, :publish, fn ->
          default_publish(Keyword.get_lazy(opts, :owner, fn -> Ownership.owner?(@task) end))
        end),
      timer: Keyword.get(opts, :timer, &Process.send_after/3),
      last_apower_w: 0.0
    }

    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = poll_and_publish(state)
    state.timer.(self(), :poll, round(interval(state) * 1000))
    {:noreply, state}
  end

  @doc "One poll: fetch, remember the watts, publish; a Fritz error is logged and publishes nothing."
  def poll_and_publish(state) do
    case DectClient.fetch(state.client, state.plug.ain) do
      {:ok, reading, client} ->
        topic = "#{state.topic_prefix}/#{state.plug.id}/status/switch:0"
        state.publish.(topic, payload(reading))
        %{state | client: client, last_apower_w: reading.apower_w}

      {:error, message, client} ->
        Logger.warning("FritzBridge #{state.plug.id}: #{message}")
        %{state | client: client}
    end
  end

  @doc "Rails' `JSON.generate({apower:, aenergy: {total:}})`."
  def payload(%{apower_w: watts, aenergy_wh: wh}),
    do: RubyJSON.generate!([{"apower", watts}, {"aenergy", [{"total", wh}]}])

  @doc "Seconds until the next poll."
  def interval(%{last_apower_w: watts, poll: poll}) do
    if watts > poll.idle_threshold_w,
      do: poll.active_interval_seconds,
      else: poll.idle_interval_seconds
  end

  defp default_publish(owner) do
    if owner do
      fn topic, payload ->
        try do
          case Mqtt.publish(@task, @client_id, topic, payload) do
            :ok ->
              :ok

            {:error, reason} ->
              Logger.warning("FritzBridge: publish on #{topic} failed: #{inspect(reason)}")
          end
        rescue
          # A task Phoenix does not own: the poll goes on, the publish is refused.
          error in Ownership.NotOwnerError ->
            Logger.error("FritzBridge: publish on #{topic} refused: #{Exception.message(error)}")
        end
      end
    else
      fn topic, payload ->
        Logger.debug("FritzBridge (shadow): would publish #{topic} #{payload}")
      end
    end
  end
end
