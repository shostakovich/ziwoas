defmodule Ziwoas.Switching.ScheduleTickJob do
  @moduledoc """
  The edge-driven scheduler (`schedule_tick`, every minute, ADR-0001). Per
  switchable plug the latest edge between its watermark and now is switched,
  unless a manual command came after it; the watermark then moves to now. A
  missed edge is made up within `grace_s/0` only. A failed switch leaves its
  plug's watermark, so the next tick retries that plug alone.
  """
  @behaviour Ziwoas.Scheduler.Job

  import Ecto.Query

  require Logger

  alias Ziwoas.{Clock, Repo}
  alias Ziwoas.Switching.{Command, Commander, EdgeCalculator, Rule, SchedulerState}

  # Switching a running appliance off late is worse than not switching it at all.
  @grace_s 10 * 60

  def grace_s, do: @grace_s

  @impl true
  def perform(opts), do: opts |> Keyword.fetch!(:config) |> tick(Clock.now())

  @doc "One tick at `now`; returns the edges it dispatched, `{plug_id, edge, :ok | :failed}`."
  @spec tick(Ziwoas.Config.t(), DateTime.t()) :: [{String.t(), EdgeCalculator.Edge.t(), atom}]
  def tick(config, now) do
    zone = config.location.timezone
    plugs = Enum.filter(config.plugs, & &1.switchable)
    ids = Enum.map(plugs, & &1.id)

    rules =
      Repo.all(from r in Rule, where: r.enabled == true and r.plug_id in ^ids)
      |> Enum.group_by(& &1.plug_id)

    Enum.flat_map(plugs, fn plug ->
      edge = due_edge(plug.id, Map.get(rules, plug.id, []), now, zone)
      outcome = edge && dispatch(plug, edge, config.mqtt)

      # Every plug of the tick advances, not just the ones with an edge, or an
      # untouched plug would drag an ancient watermark along.
      if outcome != :failed, do: SchedulerState.advance!(plug.id, now)

      if edge, do: [{plug.id, edge, outcome}], else: []
    end)
  end

  # The calculator knows neither clock nor grace: both live in the interval.
  defp due_edge(plug_id, rules, now, zone) do
    floor = DateTime.add(now, -@grace_s)

    from =
      case SchedulerState.last_tick_at(plug_id) do
        nil -> floor
        watermark -> if DateTime.compare(watermark, floor) == :gt, do: watermark, else: floor
      end

    case EdgeCalculator.latest_edge_per_plug(rules, from, now, zone) do
      [edge | _] -> if Command.manual_after?(plug_id, edge.at), do: nil, else: edge
      [] -> nil
    end
  end

  defp dispatch(plug, edge, mqtt) do
    case Commander.switch(plug, edge.action, :schedule, mqtt) do
      {:ok, _command} ->
        :ok

      {:error, message} ->
        Logger.warning(
          "ScheduleTick: #{plug.id} rule #{edge.rule_id} #{edge.action} failed: #{message}"
        )

        :failed
    end
  end
end
