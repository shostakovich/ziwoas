defmodule ZiwoasWeb.DashboardComponents do
  @moduledoc """
  The dashboard's parts, ported from the `Dashboard::*` ViewComponents and the
  `shared/_energy_flow` partial (with `EnergyFlowHelper`). The PV page reuses
  the tile and the energy flow. Ids, classes and Stimulus `data-*` stay
  verbatim: the live updates replace these regions by id, like Rails'
  `DashboardBroadcaster` does over Turbo Streams.
  """
  use ZiwoasWeb, :html

  alias Ziwoas.{EnergyFlow, EnergySummary, Energy, GermanNumber, LiveState, RubyNumeric}

  @battery_assets [
    {"normal", "solakon_battery_normal.webp"},
    {"discharging", "solakon_battery_normal.webp"},
    {"charging", "solakon_battery_charging.webp"},
    {"low", "solakon_battery_low.webp"},
    {"hot", "solakon_battery_hot.webp"},
    {"cold", "solakon_battery_cold.webp"},
    {"fault", "solakon_battery_fault.webp"}
  ]
  @default_battery_asset "solakon_battery_normal.webp"

  def default_battery_asset, do: @default_battery_asset

  # --- Hero ------------------------------------------------------------------

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
        battery_asset: battery_asset(flow.battery_state)
      )

    ~H"""
    <div id="dashboard_hero" class="card text-bg-warning mb-3 live-dim">
      <div class="card-body p-3">
        <div class="row row-cols-2 g-2 align-items-center">
          <div class="col d-flex align-items-center gap-2 gap-sm-3">
            <img class="hero-icon" alt={@weather_alt} src={"/assets/#{@weather_asset}"} />
            <div class="stat">
              <span class="stat-label">PV jetzt</span>
              <span class="text-nowrap"><span class="display-4">{GermanNumber.format(@pv_watt)}</span>
              <span class="fs-3 fw-semibold">W</span></span>
            </div>
          </div>
          <div class="col d-flex align-items-center gap-2 gap-sm-3" hidden={!@battery}>
            <img class="hero-icon" alt="Batterie" src={"/assets/#{@battery_asset}"} />
            <div class="stat">
              <span class="stat-label">Batterie</span>
              <span class="text-nowrap"><span class="display-4">{GermanNumber.format(@soc)}</span>
              <span class="fs-3 fw-semibold">%</span></span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp pv_watt(%LiveState{energy_flow: %{solakon_online: true} = flow}),
    do: RubyNumeric.max([flow.solar_w || 0, 0])

  defp pv_watt(%LiveState{plugs: plugs}) do
    case Enum.find(plugs, &(&1.role == :producer)) do
      %{online: true, apower_w: watts} -> abs(watts || 0)
      _ -> nil
    end
  end

  defp battery_asset(state) do
    case List.keyfind(@battery_assets, state, 0) do
      {_, asset} -> asset
      nil -> @default_battery_asset
    end
  end

  # --- Tiles -----------------------------------------------------------------

  @doc "A stat tile (`Dashboard::TileComponent`); values sit at the foot, so a row lines them up."
  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :number, :string, required: true
  attr :unit, :string, default: nil
  attr :caption, :string, default: nil

  def tile(assigns) do
    ~H"""
    <div class="col" id={@id}>
      <div class="card h-100">
        <div class="card-body p-3 h-100 d-flex flex-column">
          <div class="stat flex-grow-1">
            <span class="stat-label">{@label}</span>
            <span class="stat-value fs-2 mt-auto">{@number}
            <%= if @unit do %>
              <span class="fs-5 fw-semibold">{@unit}</span>
            <% end %></span>
            <span :if={@caption} class="small text-body-secondary">{@caption}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc "The day's tiles, recomputed once a minute (`TileComponent.summary_tiles`)."
  @spec summary_tiles(EnergySummary.t()) :: [map]
  def summary_tiles(summary) do
    [
      energy("tile_produced", "Erzeugt heute", Energy.kwh(summary.produced)),
      energy("tile_consumed", "Verbraucht heute", Energy.kwh(summary.consumed)),
      measure("tile_savings", "Gespart heute", summary.savings_eur, "€", 2),
      energy(
        "tile_net_today",
        "Bilanz heute",
        (summary.produced.wh - summary.consumed.wh) / 1000.0,
        true
      ),
      share("tile_autarky", "Autarkie heute", EnergySummary.autarky_ratio(summary)),
      share(
        "tile_self_consumption",
        "Eigen­verbrauchs­quote",
        EnergySummary.self_consumption_ratio(summary)
      )
    ]
  end

  @doc "The live tiles, replaced with every live beat (`TileComponent.live_tiles`)."
  @spec live_tiles(LiveState.t()) :: [map]
  def live_tiles(%LiveState{energy_flow: flow, plugs: plugs}) do
    any_online = flow.solakon_online or Enum.any?(plugs, & &1.online)

    [
      measure("tile_consumption_now", "Verbrauch jetzt", if(any_online, do: flow.home_w), "W", 0),
      measure(
        "tile_netbalance_now",
        "Bilanz jetzt",
        flow.grid_w && -flow.grid_w,
        "W",
        0,
        true
      )
    ]
  end

  defp energy(id, label, kwh, signed \\ false), do: measure(id, label, kwh, "kWh", 2, signed)

  defp share(id, label, ratio), do: measure(id, label, (ratio || 0) * 100, "%", 1)

  @doc "A tile for one value: a dash without unit when unknown, a plus on a signed non-negative value."
  def measure(id, label, value, unit, precision, signed \\ false)

  def measure(id, label, nil, _unit, _precision, _signed),
    do: %{id: id, label: label, number: "—", unit: nil}

  def measure(id, label, value, unit, precision, signed) do
    number = GermanNumber.format(value, precision: precision)
    number = if signed and not (value < 0), do: "+" <> number, else: number
    %{id: id, label: label, number: number, unit: unit}
  end

  # --- Plug bar --------------------------------------------------------------

  # Colours are keyed by config position, so a plug keeps its colour across renders and charts.
  attr :live, LiveState, required: true

  def plug_bar(assigns) do
    plugs = assigns.live.plugs

    consumers =
      plugs
      |> Enum.filter(&(&1.role == :consumer and &1.online and RubyNumeric.to_f(&1.apower_w) > 0))
      |> Enum.sort_by(&(-&1.apower_w))

    order = for plug <- plugs, plug.role == :consumer, do: plug.id
    total_w = consumers |> Enum.map(& &1.apower_w) |> RubyNumeric.sum()

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
          style={"width: #{RubyNumeric.to_s(bar.width)}%"}
          aria-label={bar.plug.name}
          aria-valuenow={round(bar.width)}
          aria-valuemin="0"
          aria-valuemax="100"
          title={"#{bar.plug.name} · #{GermanNumber.format(bar.plug.apower_w, unit: "W")}"}
        >
          <div class="progress-bar" style={"background-color: #{bar.color}"}></div>
        </div>
      </div>
      <div class="d-flex justify-content-between align-items-baseline gap-3 mt-2 small text-body-secondary">
        <span>Verbrauch gesamt</span>
        <strong class="text-body tabular-nums" data-role="total">
          {GermanNumber.format(@total_w, unit: "W")}
        </strong>
      </div>
      <div
        :for={plug <- @producers}
        class="d-flex justify-content-between align-items-baseline gap-3 small text-body-secondary"
        data-role="producer"
      >
        <span>{plug.name}</span>
        <span class="text-body tabular-nums text-nowrap">
          erzeugt {GermanNumber.format(abs(RubyNumeric.to_f(plug.apower_w)), unit: "W")}
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
            {GermanNumber.format(bar.plug.apower_w, unit: "W")}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  # --- Data carriers ---------------------------------------------------------

  @doc """
  The energy flow's state for the `energy-flow` Stimulus controller: the SVG's
  running animations survive updates, only this hidden carrier is replaced.
  It doubles as the heartbeat `live-freshness` listens for.
  """
  attr :live, LiveState, required: true
  attr :id, :string, default: "energy_flow_state"

  def energy_flow_state(assigns) do
    ~H"""
    <div
      id={@id}
      hidden
      data-energy-flow-target="state"
      data-live-freshness-target="beat"
      data-state={EnergyFlow.to_json(@live.energy_flow)}
    >
    </div>
    """
  end

  @doc "Per-plug bucket deltas the 24 h chart appends in place (`Dashboard::PlugDeltasComponent`)."
  attr :deltas, :string, default: "[]"
  attr :id, :string, default: "plug_deltas"

  def plug_deltas(assigns) do
    ~H"""
    <div id={@id} hidden data-today-chart-target="deltas" data-payload={@deltas}></div>
    """
  end

  # --- Energy flow (shared/_energy_flow) -------------------------------------

  @width 400
  @height 320
  @radius 40
  @rings [
    pv: {200, 80, "--viz-solar"},
    grid: {58, 170, "--viz-grid"},
    consumer: {342, 170, "--ef-groove"},
    battery: {200, 260, "--viz-battery"}
  ]
  # Lines start inside their ring, so the dots enter from under it instead of waiting on top.
  @channels [
    {"SolarHome", "--viz-solar",
     "M 209.6,109.5 L 212.4,118 C 219.2,139 246.9,139.1 304,157.6 L 312.5,160.4"},
    {"SolarGrid", "--viz-solar",
     "M 190.4,109.5 L 187.6,118 C 180.8,139 153.1,139.1 96,157.6 L 87.5,160.4"},
    {"SolarBattery", "--viz-solar", "M 200,111 L 200,229"},
    {"GridHome", "--viz-grid", "M 89,170 L 311,170"},
    {"GridBattery", "--viz-grid",
     "M 87.5,179.6 L 96,182.4 C 153.1,200.9 180.8,201 187.6,222 L 190.4,230.5"},
    {"BatteryHome", "--viz-battery",
     "M 209.6,230.5 L 212.4,222 C 219.2,201 246.9,200.9 304,182.4 L 312.5,179.6"}
  ]

  attr :pv_asset, :string, required: true
  attr :pv_alt, :string, required: true
  attr :battery_asset, :string, required: true

  def energy_flow(assigns) do
    assigns =
      assign(assigns,
        channels: @channels,
        rings: @rings,
        width: @width,
        height: @height,
        radius: @radius,
        consumer: Keyword.fetch!(@rings, :consumer),
        battery_states:
          for(
            {state, asset} <- @battery_assets,
            do: {"data-battery-state-#{state}", "/assets/#{asset}"}
          )
      )

    ~H"""
    <div class="energy-flow">
      <svg viewBox={"0 0 #{@width} #{@height}"} class="d-block w-100 h-auto">
        <defs>
          <clipPath id="ef-clip">
            <path fill-rule="evenodd" d={clip_path()} />
          </clipPath>
        </defs>

        <g
          fill="none"
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          clip-path="url(#ef-clip)"
        >
          <path
            :for={{key, tone, d} <- @channels}
            data-ef={"efLine#{key}"}
            class="ef-link"
            style={"--ef-tone: var(#{tone})"}
            d={d}
          />
        </g>

        <g clip-path="url(#ef-clip)">
          <g :for={{key, tone, _d} <- @channels} data-ef={"efDots#{key}"} style={"fill: var(#{tone})"}>
          </g>
        </g>

        <g stroke-width="3" fill="none">
          <circle
            :for={{name, {cx, cy, stroke}} <- @rings}
            data-ring={name}
            cx={cx}
            cy={cy}
            r={@radius}
            style={"stroke: var(#{stroke})"}
          />
        </g>
        <g
          data-ef="efConsumerRing"
          transform={"rotate(-90 #{elem(@consumer, 0)} #{elem(@consumer, 1)})"}
          fill="none"
          stroke-linecap="butt"
        >
        </g>

        <g
          class="ef-names"
          text-anchor="middle"
          font-size="11"
          style="fill: var(--felt-secondary-color)"
        >
          <text x="200" y="22">PV-Anlage</text>
          <text data-ef="efGridName" x="58" y="224">Stromnetz</text>
          <text x="342" y="224">Verbraucher</text>
          <text x="200" y="315">
            <tspan data-ef="efBatteryName">Batterie</tspan><tspan data-ef="efBatterySoc"></tspan>
          </text>
        </g>
      </svg>

      <.ring name={:pv}>
        <img class="ef-icon" alt={@pv_alt} src={"/assets/#{@pv_asset}"} />
        <span class="ef-value fw-semibold tabular-nums lh-1" data-ef="efPvW">— W</span>
      </.ring>
      <.ring name={:grid}>
        <img class="ef-icon" alt="" src="/assets/icon_netz.webp" />
        <span class="ef-value fw-semibold tabular-nums lh-1" data-ef="efGridW">— W</span>
      </.ring>
      <.ring name={:consumer}>
        <img class="ef-icon" alt="" src="/assets/icon_haus.webp" />
        <span class="ef-value fw-semibold tabular-nums lh-1" data-ef="efConsumerW">— W</span>
      </.ring>
      <.ring name={:battery}>
        <img
          class="ef-icon"
          alt=""
          data-ef="efBatteryImage"
          src={"/assets/#{@battery_asset}"}
          {@battery_states}
        />
        <span class="ef-value fw-semibold tabular-nums lh-1" data-ef="efBatteryW">— W</span>
      </.ring>
    </div>
    <p class="energy-flow-key text-body-secondary text-center mt-2 mb-0">
      Verbraucher-Ring: Herkunft des Stroms
    </p>
    """
  end

  attr :name, :atom, required: true
  slot :inner_block, required: true

  defp ring(assigns) do
    {cx, cy, _stroke} = Keyword.fetch!(@rings, assigns.name)

    style =
      [
        left: percent(cx, @width),
        top: percent(cy, @height),
        width: percent(2 * @radius, @width),
        height: percent(2 * @radius, @height)
      ]
      |> Enum.map_join("; ", fn {side, value} -> "#{side}: #{value}" end)

    assigns = assign(assigns, :style, style)

    ~H"""
    <div class="ef-ring" style={@style} data-ring={@name}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp percent(units, extent), do: RubyNumeric.format_g(units * 100.0 / extent) <> "%"

  defp clip_path do
    holes =
      Enum.map_join(@rings, " ", fn {_name, {cx, cy, _stroke}} ->
        top = cy - @radius
        arc = "A #{@radius},#{@radius} 0 1,0"
        "M #{cx},#{top} #{arc} #{cx},#{cy + @radius} #{arc} #{cx},#{top} Z"
      end)

    "M 0,0 H #{@width} V #{@height} H 0 Z #{holes}"
  end
end
