defmodule Ziwoas.Switching.ScheduleTickJob do
  @moduledoc false
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.{Clock, Switching}
  alias Ziwoas.Switching.Edges

  # Switching a running appliance off late is worse than not switching it at all.
  @grace_s 10 * 60

  def grace_s, do: @grace_s

  @impl true
  def perform(opts), do: opts |> Keyword.fetch!(:config) |> tick(Clock.now())

  @spec tick(Ziwoas.Config.t(), DateTime.t()) :: [{String.t(), Edges.Edge.t(), atom}]
  def tick(config, now) do
    zone = config.location.timezone
    plugs = Enum.filter(config.plugs, & &1.switchable)
    ids = Enum.map(plugs, & &1.id)

    rules = Switching.enabled_rules(ids)

    Enum.flat_map(plugs, fn plug ->
      edge = due_edge(plug.id, Map.get(rules, plug.id, []), now, zone)
      outcome = edge && dispatch(plug, edge)

      # Every plug advances, or an untouched plug would drag an ancient watermark along.
      if outcome != :failed, do: Switching.advance_tick!(plug.id, now)

      if edge, do: [{plug.id, edge, outcome}], else: []
    end)
  end

  defp due_edge(plug_id, rules, now, zone) do
    floor = DateTime.add(now, -@grace_s)

    from =
      case Switching.last_tick_at(plug_id) do
        nil -> floor
        watermark -> if DateTime.compare(watermark, floor) == :gt, do: watermark, else: floor
      end

    case Edges.latest_edge_per_plug(rules, from, now, zone) do
      [edge | _] -> if Switching.manual_after?(plug_id, edge.at), do: nil, else: edge
      [] -> nil
    end
  end

  defp dispatch(plug, edge) do
    case Switching.switch(plug, edge.action, :schedule) do
      {:ok, _command} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "ScheduleTick: #{plug.id} rule #{edge.rule_id} #{edge.action} failed: #{inspect(reason)}"
        )

        :failed
    end
  end
end
