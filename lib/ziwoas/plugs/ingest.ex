defmodule Ziwoas.Plugs.Ingest do
  @moduledoc false
  require Logger

  alias Ziwoas.{Clock, Plugs}
  alias Ziwoas.Plugs.Plug

  @broadcast_interval_s 5
  @bucket_s 60

  defstruct [:clock, :broadcast, buckets: %{}, last: %{}, pending: [], last_broadcast_at: 0]

  @type t :: %__MODULE__{}

  @type reading :: %{apower_w: float, aenergy_wh: float, output: boolean | nil}

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
  @spec new(keyword) :: t
  def new(opts \\ []) do
    %__MODULE__{
      clock: Keyword.get(opts, :clock, &unix_now_f/0),
      broadcast: Keyword.get(opts, :broadcast, &Plugs.notify_live/1)
    }
  end

  defp unix_now_f, do: DateTime.to_unix(Clock.now(), :microsecond) / 1_000_000

  @spec record(t, Plug.t(), reading) :: t
  def record(%__MODULE__{} = ingest, %Plug{} = plug, reading) do
    ts = trunc(ingest.clock.())

    case Plugs.record_sample(plug.id, ts, reading.apower_w, reading.aenergy_wh) do
      :duplicate ->
        record_output(ingest, plug, reading.output)

      :ok ->
        Logger.debug("Plugs.Ingest: #{plug.id} #{reading.apower_w} W")
        if is_boolean(reading.output), do: Plugs.record_output(plug.id, reading.output)
        accumulate(ingest, plug, ts, reading)
    end
  end

  @spec record_output(t, Plug.t(), boolean | nil) :: t
  def record_output(%__MODULE__{} = ingest, %Plug{}, nil), do: ingest

  def record_output(%__MODULE__{} = ingest, %Plug{} = plug, output) when is_boolean(output) do
    Plugs.record_output(plug.id, output)

    case ingest.last[plug.id] do
      %{output: last} = delta when last != output ->
        ingest |> put_pending(plug.id, %{delta | output: output}) |> maybe_broadcast()

      _unchanged_or_unknown ->
        ingest
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

  defp signed_watts(%Plug{role: :producer}, watts), do: abs(watts)
  defp signed_watts(%Plug{}, watts), do: watts

  defp put_pending(ingest, id, delta) do
    pending =
      if List.keymember?(ingest.pending, id, 0),
        do: List.keyreplace(ingest.pending, id, 0, {id, delta}),
        else: ingest.pending ++ [{id, delta}]

    %{ingest | pending: pending, last: Map.put(ingest.last, id, delta)}
  end

  # A process whose readings may pause must flush/1 while pending?/1, or the last deltas wait.
  @spec pending?(t) :: boolean
  def pending?(%__MODULE__{pending: pending}), do: pending != []
  @spec flush(t) :: t
  def flush(%__MODULE__{pending: []} = ingest), do: ingest
  def flush(%__MODULE__{} = ingest), do: broadcast(ingest, ingest.clock.())
  @spec broadcast_interval_s() :: pos_integer
  def broadcast_interval_s, do: @broadcast_interval_s

  defp maybe_broadcast(ingest) do
    now = ingest.clock.()

    if now - ingest.last_broadcast_at >= @broadcast_interval_s,
      do: broadcast(ingest, now),
      else: ingest
  end

  defp broadcast(ingest, now) do
    deltas = Enum.map(ingest.pending, &elem(&1, 1))
    ingest.broadcast.(deltas)
    %{ingest | pending: [], last_broadcast_at: now}
  end
end
