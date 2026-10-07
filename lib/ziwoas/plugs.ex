defmodule Ziwoas.Plugs do
  @moduledoc """
  The plugs: their measurements and live updates.

  `subscribe/0` delivers `{:live, deltas}`, at most every 5 s, with one
  `Ziwoas.Plugs.ShellyStatusHandler.delta()` per plug that reported since.
  """
  import Ecto.Query

  alias Ziwoas.Live
  alias Ziwoas.Plugs.{Measurement, Sample}
  alias Ziwoas.Repo

  @topic inspect(__MODULE__)

  @spec subscribe() :: :ok | {:error, term}
  def subscribe, do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)

  @doc "Sends the live deltas the status handler collected to the subscribers."
  @spec notify_live([map]) :: :ok
  def notify_live(deltas) do
    broadcast(:live, deltas)
    Live.broadcast("dashboard", {:dashboard_live, deltas})
    :ok
  end

  defp broadcast(event, payload),
    do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, @topic, {event, payload})

  @doc """
  One `Measurement` per plug id as of `now`: the newest sample's watts, offline
  once no sample arrived for `offline_after_s` (fractions of a second count).
  """
  @spec latest_measurements([String.t()], DateTime.t(), number) :: %{
          String.t() => Measurement.t()
        }
  def latest_measurements(
        plug_ids,
        %DateTime{} = now,
        offline_after_s \\ Measurement.offline_after_s()
      ) do
    samples = latest_samples(plug_ids)
    now_s = DateTime.to_unix(now, :microsecond) / 1_000_000

    Map.new(plug_ids, fn plug_id ->
      sample = samples[plug_id]
      last_seen_ts = sample && sample.ts

      {plug_id,
       %Measurement{
         plug_id: plug_id,
         watt: sample && sample.apower_w && sample.apower_w * 1.0,
         last_seen_ts: last_seen_ts,
         offline: is_nil(last_seen_ts) or now_s - last_seen_ts > offline_after_s
       }}
    end)
  end

  defp latest_samples([]), do: %{}

  defp latest_samples(plug_ids) do
    newest =
      from s in Sample,
        where: s.plug_id in ^plug_ids,
        group_by: s.plug_id,
        select: %{plug_id: s.plug_id, ts: max(s.ts)}

    from(s in Sample,
      join: n in subquery(newest),
      on: n.plug_id == s.plug_id and n.ts == s.ts,
      select: %{plug_id: s.plug_id, ts: s.ts, apower_w: s.apower_w}
    )
    |> Repo.all()
    |> Map.new(&{&1.plug_id, &1})
  end
end
