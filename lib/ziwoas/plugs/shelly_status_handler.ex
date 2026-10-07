defmodule Ziwoas.Plugs.ShellyStatusHandler do
  @moduledoc """
  A `Ziwoas.Collector.MqttRouter` handler: every `<prefix>/<plug>/status/switch:0`
  status becomes a `samples` row (and a `plug_states` row when it carries a
  boolean `output`). Fritz!DECT plugs arrive the same way, through the Fritz
  bridge's MQTT messages.

  A status needs `apower` and `aenergy.total` as numbers; anything else (broken
  JSON, a missing field, an unknown plug) is logged and dropped, the state
  unchanged.

  Live deltas (a plug's newest watts and the signed mean of its current
  minute) collect per plug and go out at most every 5 s through `:broadcast`,
  by default `Ziwoas.Plugs.notify_live/1`.
  """
  @behaviour Ziwoas.Collector.MqttRouter

  require Logger

  alias Ziwoas.{Clock, Config, Plugs, Repo}
  alias Ziwoas.Plugs.{Roster, Sample, State}

  @broadcast_interval_s 5
  @bucket_s 60

  defstruct [
    :prefix,
    :roster,
    :clock,
    :broadcast,
    buckets: %{},
    pending: [],
    last_broadcast_at: 0
  ]

  @type t :: %__MODULE__{}

  @typedoc "One plug's live update, as the dashboard's `TodayChart` hook reads it."
  @type delta :: %{
          id: String.t(),
          name: String.t() | nil,
          role: atom,
          apower_w: float,
          last_seen_ts: integer,
          bucket_ts: integer,
          avg_power_w: float,
          output: boolean | nil
        }

  @doc """
  The handler for `config`'s plugs and topic prefix. Options for tests:
  `:clock` (Unix seconds as a float) and `:broadcast` (a function of the delta
  list).
  """
  @spec new(Config.t(), keyword) :: t
  def new(%Config{} = config, opts \\ []) do
    %__MODULE__{
      prefix: config.mqtt.topic_prefix,
      roster: Config.plug_roster(config),
      clock: Keyword.get(opts, :clock, &unix_now_f/0),
      broadcast: Keyword.get(opts, :broadcast, &Plugs.notify_live/1)
    }
  end

  defp unix_now_f, do: DateTime.to_unix(Clock.now(), :microsecond) / 1_000_000

  @impl Ziwoas.Collector.MqttRouter
  def subscriptions(%__MODULE__{prefix: prefix}), do: ["#{prefix}/+/status/switch:0"]

  @impl Ziwoas.Collector.MqttRouter
  def matches?(%__MODULE__{prefix: prefix}, topic), do: String.starts_with?(topic, prefix <> "/")

  @impl Ziwoas.Collector.MqttRouter
  def handle(%__MODULE__{} = state, topic, payload) do
    plug_id = Enum.at(String.split(topic, "/"), length(String.split(state.prefix, "/")))

    with {:ok, plug} <- fetch_plug(state, plug_id),
         {:ok, status} <- parse(payload) do
      record(state, plug, status)
    else
      {:error, reason} ->
        Logger.warning("ShellyStatusHandler: #{reason} on #{topic}")
        state
    end
  end

  defp fetch_plug(state, plug_id) do
    case Roster.find(state.roster, plug_id) do
      nil -> {:error, "unknown plug '#{plug_id}'"}
      plug -> {:ok, plug}
    end
  end

  defp parse(payload) do
    case JSON.decode(payload) do
      {:ok, %{"apower" => apower, "aenergy" => %{"total" => total}} = data}
      when is_number(apower) and is_number(total) ->
        {:ok, %{apower_w: apower * 1.0, aenergy_wh: total * 1.0, output: output(data["output"])}}

      {:ok, data} when is_map(data) ->
        {:error, "status without apower or aenergy.total"}

      _ ->
        {:error, "invalid JSON"}
    end
  end

  # A Shelly reports its relay as a JSON boolean; anything else says nothing about it.
  defp output(output) when is_boolean(output), do: output
  defp output(_output), do: nil

  defp record(state, plug, status) do
    ts = trunc(state.clock.())
    sample = %{plug_id: plug.id, ts: ts, apower_w: status.apower_w, aenergy_wh: status.aenergy_wh}

    case Repo.insert_all(Sample, [sample], on_conflict: :nothing) do
      {0, _} ->
        state

      {1, _} ->
        if is_boolean(status.output), do: State.record_output(plug.id, status.output)
        Logger.debug("ShellyStatusHandler: #{plug.id} #{status.apower_w} W")
        accumulate(state, plug, ts, status)
    end
  end

  defp accumulate(state, plug, ts, status) do
    bucket_ts = div(ts, @bucket_s) * @bucket_s

    bucket =
      case state.buckets[plug.id] do
        %{bucket_ts: ^bucket_ts, sum: sum, count: count} ->
          %{bucket_ts: bucket_ts, sum: sum + status.apower_w, count: count + 1}

        _ ->
          %{bucket_ts: bucket_ts, sum: status.apower_w, count: 1}
      end

    delta = %{
      id: plug.id,
      name: plug.name,
      role: plug.role,
      apower_w: status.apower_w,
      last_seen_ts: ts,
      bucket_ts: bucket_ts,
      avg_power_w: Roster.signed_watts(state.roster, plug.id, bucket.sum / bucket.count),
      output: status.output
    }

    %{state | buckets: Map.put(state.buckets, plug.id, bucket)}
    |> put_pending(plug.id, delta)
    |> maybe_broadcast()
  end

  # A plug keeps its first position among the pending deltas until the broadcast.
  defp put_pending(state, id, delta) do
    pending =
      if List.keymember?(state.pending, id, 0),
        do: List.keyreplace(state.pending, id, 0, {id, delta}),
        else: state.pending ++ [{id, delta}]

    %{state | pending: pending}
  end

  defp maybe_broadcast(state) do
    now = state.clock.()

    if now - state.last_broadcast_at >= @broadcast_interval_s do
      deltas = Enum.map(state.pending, &elem(&1, 1))
      state.broadcast.(deltas)
      %{state | pending: [], last_broadcast_at: now}
    else
      state
    end
  end
end
