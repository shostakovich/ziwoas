defmodule ZiwoasWeb.Components.EnergyFlow do
  @moduledoc """
  The Energiefluss card of the dashboard and the PV page: four rings (PV, grid,
  consumers, battery) and the channels between them. The card is the
  `EnergyFlow` hook; the flow's state rides on its `data-state` and the hook
  draws values, dots and the consumer ring from it on every update.
  """
  use ZiwoasWeb, :html

  alias Ziwoas.Energy.{Flow, LiveState}

  @battery_assets [
    {:normal, "solakon_battery_normal.webp"},
    {:discharging, "solakon_battery_normal.webp"},
    {:charging, "solakon_battery_charging.webp"},
    {:low, "solakon_battery_low.webp"},
    {:hot, "solakon_battery_hot.webp"},
    {:cold, "solakon_battery_cold.webp"},
    {:fault, "solakon_battery_fault.webp"}
  ]
  @default_battery_asset "solakon_battery_normal.webp"

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

  @doc "The battery picture for a battery state; an unknown state shows the normal one."
  @spec battery_asset(atom | nil) :: String.t()
  def battery_asset(state) do
    case List.keyfind(@battery_assets, state, 0) do
      {_, asset} -> asset
      nil -> @default_battery_asset
    end
  end

  @doc "The flow's state as JSON, for the `EnergyFlow` hook's `data-state`."
  @spec state_json(Flow.t()) :: String.t()
  def state_json(%Flow{} = flow) do
    flow
    |> Map.from_struct()
    |> Map.update!(:flows, &Map.from_struct/1)
    |> JSON.encode!()
  end

  attr :live, LiveState, required: true
  attr :pv_asset, :string, required: true
  attr :pv_alt, :string, required: true
  attr :class, :any, default: nil

  def energy_flow(assigns) do
    assigns =
      assign(assigns,
        state: state_json(assigns.live.energy_flow),
        channels: @channels,
        rings: @rings,
        width: @width,
        height: @height,
        radius: @radius,
        consumer: Keyword.fetch!(@rings, :consumer),
        battery_asset: @default_battery_asset,
        battery_states:
          for(
            {state, asset} <- @battery_assets,
            do: {"data-battery-state-#{state}", ~p"/images/#{asset}"}
          )
      )

    ~H"""
    <.card
      id="energy_flow"
      title="Energiefluss"
      class={["energy-flow-card", @class]}
      phx-hook="EnergyFlow"
      data-state={@state}
    >
      <div class="energy-flow">
        <svg
          id="energy_flow_svg"
          phx-update="ignore"
          viewBox={"0 0 #{@width} #{@height}"}
          class="d-block w-100 h-auto"
        >
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
            <g
              :for={{key, tone, _d} <- @channels}
              data-ef={"efDots#{key}"}
              style={"fill: var(#{tone})"}
            >
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
          <img class="ef-icon" alt={@pv_alt} src={~p"/images/#{@pv_asset}"} />
          <span class="ef-value fw-semibold tabular-nums lh-1" data-ef="efPvW">— W</span>
        </.ring>
        <.ring name={:grid}>
          <img class="ef-icon" alt="" src={~p"/images/icon_netz.webp"} />
          <span class="ef-value fw-semibold tabular-nums lh-1" data-ef="efGridW">— W</span>
        </.ring>
        <.ring name={:consumer}>
          <img class="ef-icon" alt="" src={~p"/images/icon_haus.webp"} />
          <span class="ef-value fw-semibold tabular-nums lh-1" data-ef="efConsumerW">— W</span>
        </.ring>
        <.ring name={:battery}>
          <img
            class="ef-icon"
            alt=""
            data-ef="efBatteryImage"
            src={~p"/images/#{@battery_asset}"}
            {@battery_states}
          />
          <span class="ef-value fw-semibold tabular-nums lh-1" data-ef="efBatteryW">— W</span>
        </.ring>
      </div>
      <p class="energy-flow-key text-body-secondary text-center mt-2 mb-0">
        Verbraucher-Ring: Herkunft des Stroms
      </p>
    </.card>
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

  defp percent(units, extent), do: css_number(units * 100.0 / extent) <> "%"

  # Three decimals are finer than a pixel; an integral value drops its ".0".
  defp css_number(value) do
    rounded = Float.round(value * 1.0, 3)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: Float.to_string(rounded)
  end

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
