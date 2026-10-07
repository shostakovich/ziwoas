defmodule ZiwoasWeb.DashboardComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Energy
  alias Ziwoas.Energy.{Amount, Balance, LiveState}
  alias ZiwoasWeb.Components.EnergyFlow

  attr :live, LiveState, required: true
  attr :weather_asset, :string, required: true
  attr :weather_alt, :string, required: true

  def hero(assigns) do
    flow = assigns.live.energy_flow

    assigns =
      assign(assigns,
        pv_watt: pv_watt(assigns.live),
        battery: flow.solakon_online,
        soc: flow.battery_soc_pct,
        battery_asset: EnergyFlow.battery_asset(flow.battery_state)
      )

    ~H"""
    <div id="dashboard_hero" class="card text-bg-warning mb-3 live-dim">
      <div class="card-body p-3">
        <div class="row row-cols-2 g-2 align-items-center">
          <div class="col d-flex align-items-center gap-2 gap-sm-3">
            <img class="hero-icon" alt={@weather_alt} src={~p"/images/#{@weather_asset}"} />
            <div class="stat">
              <span class="stat-label">PV jetzt</span>
              <span class="text-nowrap"><span class="display-4">{number(@pv_watt)}</span>
              <span class="fs-3 fw-semibold">W</span></span>
            </div>
          </div>
          <div class="col d-flex align-items-center gap-2 gap-sm-3" hidden={!@battery}>
            <img class="hero-icon" alt="Batterie" src={~p"/images/#{@battery_asset}"} />
            <div class="stat">
              <span class="stat-label">Batterie</span>
              <span class="text-nowrap"><span class="display-4">{number(@soc)}</span>
              <span class="fs-3 fw-semibold">%</span></span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp pv_watt(%LiveState{energy_flow: %{solakon_online: true} = flow}),
    do: max(flow.solar_w || 0, 0)

  defp pv_watt(%LiveState{plugs: plugs}) do
    case Enum.find(plugs, &(&1.role == :producer)) do
      %{online: true, apower_w: watts} -> abs(watts || 0)
      _ -> nil
    end
  end

  @spec summary_tiles(Balance.t()) :: [map]
  def summary_tiles(summary) do
    [
      energy("tile_produced", "Erzeugt heute", Amount.kwh(summary.produced)),
      energy("tile_consumed", "Verbraucht heute", Amount.kwh(summary.consumed)),
      measure_tile("tile_savings", "Gespart heute", summary.savings_eur, "€", 2),
      energy(
        "tile_net_today",
        "Bilanz heute",
        (summary.produced.wh - summary.consumed.wh) / 1000.0,
        true
      ),
      share("tile_autarky", "Autarkie heute", Energy.autarky_ratio(summary)),
      share(
        "tile_self_consumption",
        "Eigen­verbrauchs­quote",
        Energy.self_consumption_ratio(summary)
      )
    ]
  end

  @spec live_tiles(LiveState.t()) :: [map]
  def live_tiles(%LiveState{energy_flow: flow, plugs: plugs}) do
    any_online = flow.solakon_online or Enum.any?(plugs, & &1.online)

    [
      measure_tile(
        "tile_consumption_now",
        "Verbrauch jetzt",
        if(any_online, do: flow.home_w),
        "W",
        0
      ),
      measure_tile(
        "tile_netbalance_now",
        "Bilanz jetzt",
        flow.grid_w && -flow.grid_w,
        "W",
        0,
        true
      )
    ]
  end

  defp energy(id, label, kwh, signed \\ false),
    do: measure_tile(id, label, kwh, "kWh", 2, signed)

  defp share(id, label, ratio), do: measure_tile(id, label, (ratio || 0) * 100, "%", 1)

  # Colours are keyed by config position, so a plug keeps its colour across renders and charts.
  attr :live, LiveState, required: true

  def plug_bar(assigns) do
    plugs = assigns.live.plugs

    consumers =
      plugs
      |> Enum.filter(&(&1.role == :consumer and &1.online and (&1.apower_w || 0) > 0))
      |> Enum.sort_by(&(-&1.apower_w))

    order = for plug <- plugs, plug.role == :consumer, do: plug.id
    total_w = consumers |> Enum.map(& &1.apower_w) |> Enum.sum()

    assigns =
      assign(assigns,
        consumers:
          for plug <- consumers do
            width = plug.apower_w / total_w * 100

            %{
              plug: plug,
              width: width,
              color: "var(--viz-#{rem(Enum.find_index(order, &(&1 == plug.id)), 10) + 1})"
            }
          end,
        producers: Enum.filter(plugs, &(&1.role == :producer and &1.online)),
        total_w: total_w
      )

    ~H"""
    <div id="dashboard_plug_bar" class="card card-body mb-3 live-dim">
      <div class="progress-stacked plug-bar" style="height: 1.5rem">
        <div
          :for={bar <- @consumers}
          class="progress h-100"
          role="progressbar"
          style={"width: #{css_number(bar.width)}%"}
          aria-label={bar.plug.name}
          aria-valuenow={round(bar.width)}
          aria-valuemin="0"
          aria-valuemax="100"
          title={"#{bar.plug.name} · #{number(bar.plug.apower_w, unit: "W")}"}
        >
          <div class="progress-bar" style={"background-color: #{bar.color}"}></div>
        </div>
      </div>
      <div class="d-flex justify-content-between align-items-baseline gap-3 mt-2 small text-body-secondary">
        <span>Verbrauch gesamt</span>
        <strong class="text-body tabular-nums" data-role="total">
          {number(@total_w, unit: "W")}
        </strong>
      </div>
      <div
        :for={plug <- @producers}
        class="d-flex justify-content-between align-items-baseline gap-3 small text-body-secondary"
        data-role="producer"
      >
        <span>{plug.name}</span>
        <span class="text-body tabular-nums text-nowrap">
          erzeugt {number(plug.apower_w && abs(plug.apower_w), unit: "W")}
        </span>
      </div>
      <ul
        class="list-unstyled row row-cols-1 row-cols-sm-2 row-cols-md-3 gx-4 gy-1 small tabular-nums mt-2 mb-0"
        aria-label="Legende"
      >
        <li :for={bar <- @consumers} class="col d-flex align-items-center gap-2">
          <span class="badge rounded-pill legend-dot" style={"background-color: #{bar.color}"}></span>
          <span class="plug-bar-name">{bar.plug.name}</span>
          <span class="ms-auto text-body-secondary text-nowrap">
            {number(bar.plug.apower_w, unit: "W")}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  defp css_number(value) do
    rounded = Float.round(value * 1.0, 3)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: Float.to_string(rounded)
  end
end
