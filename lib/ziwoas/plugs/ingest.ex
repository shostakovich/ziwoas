defmodule Ziwoas.Plugs.Ingest do
  @moduledoc """
  A process's intake of plug readings, the one path for a Shelly status from
  MQTT (`ShellyStatusHandler`) and a Fritz!DECT poll (`Ziwoas.Fritz.Bridge`):
  each reading becomes a `samples` row (and a `plug_states` row when it
  carries a relay output), and a live delta.

  Live deltas (a plug's newest watts and the signed mean of its current
  minute) collect per plug and go out at most every 5 s through `:broadcast`,
  by default `Ziwoas.Plugs.notify_live/1`.
  """
  require Logger

  alias Ziwoas.{Clock, Plugs}
  alias Ziwoas.Plugs.Plug

  @broadcast_interval_s 5
  @bucket_s 60

  defstruct [:clock, :broadcast, buckets: %{}, pending: [], last_broadcast_at: 0]

  @type t :: %__MODULE__{}

  @typedoc "A plug's reading: watts, the counter in Wh and the relay output if it reported one."
  @type reading :: %{apower_w: float, aenergy_wh: float, output: boolean | nil}

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

  @doc "Options for tests: `:clock` (Unix seconds as a float) and `:broadcast` (a function of the delta list)."
  @spec new(keyword) :: t
  def new(opts \\ []) do
    %__MODULE__{
      clock: Keyword.get(opts, :clock, &unix_now_f/0),
      broadcast: Keyword.get(opts, :broadcast, &Plugs.notify_live/1)
    }
  end

  defp unix_now_f, do: DateTime.to_unix(Clock.now(), :microsecond) / 1_000_000

  @doc "Records the reading at the clock's whole second; a second reading in that second changes nothing."
  @spec record(t, Plug.t(), reading) :: t
  def record(%__MODULE__{} = ingest, %Plug{} = plug, reading) do
    ts = trunc(ingest.clock.())

    case Plugs.record_sample(plug.id, ts, reading.apower_w, reading.aenergy_wh) do
      :duplicate ->
        ingest

      :ok ->
        if is_boolean(reading.output), do: Plugs.record_output(plug.id, reading.output)
        Logger.debug("Plugs.Ingest: #{plug.id} #{reading.apower_w} W")
        accumulate(ingest, plug, ts, reading)
    end
  end

  defp accumulate(ingest, plug, ts, reading) do
    bucket_ts = div(ts, @bucket_s) * @bucket_s

    bucket =
      case ingest.buckets[plug.id] do
        %{bucket_ts: ^bucket_ts, sum: sum, count: count} ->
          %{bucket_ts: bucket_ts, sum: sum + reading.apower_w, count: count + 1}

        _ ->
          %{bucket_ts: bucket_ts, sum: reading.apower_w, count: 1}
      end

    delta = %{
      id: plug.id,
      name: plug.name,
      role: plug.role,
      apower_w: reading.apower_w,
      last_seen_ts: ts,
      bucket_ts: bucket_ts,
      avg_power_w: signed_watts(plug, bucket.sum / bucket.count),
      output: reading.output
    }

    %{ingest | buckets: Map.put(ingest.buckets, plug.id, bucket)}
    |> put_pending(plug.id, delta)
    |> maybe_broadcast()
  end

  # Producers report with the opposite sign; the live mean is a positive magnitude.
  defp signed_watts(%Plug{role: :producer}, watts), do: abs(watts)
  defp signed_watts(%Plug{}, watts), do: watts

  # A plug keeps its first position among the pending deltas until the broadcast.
  defp put_pending(ingest, id, delta) do
    pending =
      if List.keymember?(ingest.pending, id, 0),
        do: List.keyreplace(ingest.pending, id, 0, {id, delta}),
        else: ingest.pending ++ [{id, delta}]

    %{ingest | pending: pending}
  end

  defp maybe_broadcast(ingest) do
    now = ingest.clock.()

    if now - ingest.last_broadcast_at >= @broadcast_interval_s do
      deltas = Enum.map(ingest.pending, &elem(&1, 1))
      ingest.broadcast.(deltas)
      %{ingest | pending: [], last_broadcast_at: now}
    else
      ingest
    end
  end
end
