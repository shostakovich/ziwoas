defmodule Ziwoas.Plugs.ShellyStatusHandler do
  @moduledoc """
  Rails' `ShellyStatusHandler` (task `plug_ingest`), a `Ziwoas.Collector.MqttRouter`
  handler: every `<prefix>/<plug>/status/switch:0` status becomes a `samples` row
  (and a `plug_states` row when it carries `output`), written through
  `Ziwoas.Repo.write/2`. Fritz!DECT plugs arrive the same way, through the Fritz
  bridge's MQTT messages.

  Live deltas (`LiveState::Update`s: newest watts, the signed mean of the plug's
  current minute) collect per plug and go out at most every 5 s
  (`BROADCAST_INTERVAL`) through `:broadcast` — `{:dashboard_live, deltas}` on
  `dashboard` via `Ziwoas.Live.broadcast/3`, so only as owner. The deltas are pair lists as
  `Ziwoas.Live.DashboardWatcher` sends them.

  The clock (`:clock`, Unix seconds as a float) is read twice per message, as in
  Rails: the sample's second and the broadcast interval.
  """
  @behaviour Ziwoas.Collector.MqttRouter

  require Logger

  alias Ziwoas.{Clock, Config, Live, Repo, RubyNumeric}
  alias Ziwoas.Plugs.{Roster, Sample, State}

  @broadcast_interval_s 5
  @bucket_s 60

  defstruct [
    :task,
    :prefix,
    :roster,
    :clock,
    :broadcast,
    buckets: %{},
    pending: [],
    last_broadcast_at: 0
  ]

  @type t :: %__MODULE__{}

  @doc """
  The handler for `config`'s plugs and topic prefix. Options: `:task` (default
  `:plug_ingest`); for tests `:clock` and `:broadcast` (a function of the delta
  list).
  """
  @spec new(Config.t(), keyword) :: t
  def new(%Config{} = config, opts \\ []) do
    task = Keyword.get(opts, :task, :plug_ingest)

    %__MODULE__{
      task: task,
      prefix: config.mqtt.topic_prefix,
      roster: Config.plug_roster(config),
      clock: Keyword.get(opts, :clock, &unix_now_f/0),
      broadcast:
        Keyword.get(opts, :broadcast, &Live.broadcast(task, "dashboard", {:dashboard_live, &1}))
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

    case state.roster.by_id[plug_id] do
      nil ->
        Logger.warning("ShellyStatusHandler: unknown plug '#{plug_id}' on topic #{topic}")
        state

      plug ->
        case JSON.decode(payload) do
          {:ok, data} when is_map(data) ->
            record(state, plug, data, topic)

          _ ->
            Logger.warning("ShellyStatusHandler: invalid JSON on #{topic}")
            state
        end
    end
  end

  defp record(state, plug, data, topic) do
    apower_w = RubyNumeric.to_f(data["apower"])
    aenergy_wh = data |> Map.get("aenergy") |> total() |> RubyNumeric.to_f()
    output = data["output"]
    ts = trunc(state.clock.())

    written =
      Repo.write(state.task, fn ->
        case Repo.insert_all(
               Sample,
               [%{plug_id: plug.id, ts: ts, apower_w: apower_w, aenergy_wh: aenergy_wh}],
               on_conflict: :nothing
             ) do
          {1, _} when is_nil(output) -> :ok
          {1, _} -> State.record_output(plug.id, output)
          {0, _} -> :duplicate
        end
      end)

    case written do
      :duplicate ->
        state

      {:error, :invalid} ->
        Logger.warning("ShellyStatusHandler: invalid output on #{topic}: #{inspect(output)}")
        state

      _ ->
        Logger.debug("ShellyStatusHandler: #{plug.id} #{apower_w} W / #{aenergy_wh} Wh")
        accumulate(state, plug, ts, apower_w, output)
    end
  end

  defp total(aenergy) when is_map(aenergy), do: aenergy["total"]
  defp total(_), do: nil

  defp accumulate(state, plug, ts, apower_w, output) do
    bucket_ts = div(ts, @bucket_s) * @bucket_s

    bucket =
      case state.buckets[plug.id] do
        %{bucket_ts: ^bucket_ts, sum: sum, count: count} ->
          %{bucket_ts: bucket_ts, sum: sum + apower_w, count: count + 1}

        _ ->
          %{bucket_ts: bucket_ts, sum: apower_w, count: 1}
      end

    state = %{state | buckets: Map.put(state.buckets, plug.id, bucket)}

    # LiveState::Update's output is a strict boolean; Rails' struct raised here.
    if is_boolean(output) or is_nil(output) do
      avg = Roster.signed_watts(state.roster, plug.id, bucket.sum / bucket.count)

      delta = [
        {"id", plug.id},
        {"name", plug.name},
        {"role", plug.role},
        {"apower_w", apower_w},
        {"last_seen_ts", ts},
        {"bucket_ts", bucket_ts},
        {"avg_power_w", avg},
        {"output", output}
      ]

      state |> put_pending(plug.id, delta) |> maybe_broadcast()
    else
      Logger.warning("ShellyStatusHandler: dashboard broadcast failed: output #{inspect(output)}")
      state
    end
  end

  # Rails' @pending is a Hash: a plug keeps its first position until the broadcast.
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
      state.broadcast.(Enum.map(state.pending, &elem(&1, 1)))
      %{state | pending: [], last_broadcast_at: now}
    else
      state
    end
  end
end
