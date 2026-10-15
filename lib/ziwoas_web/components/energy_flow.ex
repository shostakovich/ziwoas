defmodule ZiwoasWeb.Components.EnergyFlow do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Energy.{Flow, LiveState}

  @battery_plush [
    normal: {"battery", "Batterie"},
    discharging: {"battery", "Batterie"},
    charging: {"battery-charging", "Batterie lädt"},
    low: {"battery-low", "Batterie fast leer"},
    hot: {"battery-hot", "Batterie zu warm"},
    cold: {"battery-cold", "Batterie zu kalt"},
    fault: {"battery-warning", "Batteriefehler"}
  ]

  @width 400
  @height 320
  @radius 40
  @rings [
    pv: {200, 80, "stroke-solar"},
    grid: {58, 170, "stroke-grid"},
    consumer: {342, 170, "stroke-base-content/15"},
    battery: {200, 260, "stroke-battery"}
  ]
  # Lines start inside their ring, so the dots enter from under it instead of waiting on top.
  @channels [
    {"SolarHome", "data-flowing:stroke-solar", "fill-solar",
     "M 209.6,109.5 L 212.4,118 C 219.2,139 246.9,139.1 304,157.6 L 312.5,160.4"},
    {"SolarGrid", "data-flowing:stroke-solar", "fill-solar",
     "M 190.4,109.5 L 187.6,118 C 180.8,139 153.1,139.1 96,157.6 L 87.5,160.4"},
    {"SolarBattery", "data-flowing:stroke-solar", "fill-solar", "M 200,111 L 200,229"},
    {"GridHome", "data-flowing:stroke-grid", "fill-grid", "M 89,170 L 311,170"},
    {"GridBattery", "data-flowing:stroke-grid", "fill-grid",
     "M 87.5,179.6 L 96,182.4 C 153.1,200.9 180.8,201 187.6,222 L 190.4,230.5"},
    {"BatteryHome", "data-flowing:stroke-battery", "fill-battery",
     "M 209.6,230.5 L 212.4,222 C 219.2,201 246.9,200.9 304,182.4 L 312.5,179.6"}
  ]

  @spec battery_plush(atom | nil) :: String.t()
  def battery_plush(state), do: state |> battery() |> elem(0)

  @spec battery_alt(atom | nil) :: String.t()
  def battery_alt(state), do: state |> battery() |> elem(1)

  defp battery(state), do: Keyword.get(@battery_plush, state, @battery_plush[:normal])

  @spec state_json(Flow.t()) :: String.t()
  def state_json(%Flow{} = flow) do
    flow
    |> Map.from_struct()
    |> Map.update!(:flows, &Map.from_struct/1)
    |> JSON.encode!()
  end

  attr :live, LiveState, required: true
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
        flow: assigns.live.energy_flow
      )

    ~H"""
    <.card
      id="energy_flow"
      title="Energiefluss"
      subtitle="Der Ring am Verbrauch zeigt, woher der Strom kommt."
      class={@class}
      phx-hook="EnergyFlow"
      data-state={@state}
    >
      <div class="energy-flow @container relative m-auto w-full max-w-136 max-sm:-mx-4 max-sm:w-auto">
        <svg
          id="energy_flow_svg"
          phx-update="ignore"
          viewBox={"0 0 #{@width} #{@height}"}
          class="block h-auto w-full"
          aria-hidden="true"
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
              :for={{key, flowing, _dots, d} <- @channels}
              data-ef={"efLine#{key}"}
              class={["stroke-base-content/7 transition-colors duration-300", flowing]}
              d={d}
            />
          </g>

          <g clip-path="url(#ef-clip)">
            <g :for={{key, _flowing, dots, _d} <- @channels} data-ef={"efDots#{key}"} class={dots}>
            </g>
          </g>

          <g stroke-width="3" fill="none">
            <circle
              :for={{name, {cx, cy, stroke}} <- @rings}
              data-ring={name}
              cx={cx}
              cy={cy}
              r={@radius}
              class={stroke}
            />
          </g>
          <g
            data-ef="efConsumerRing"
            transform={"rotate(-90 #{elem(@consumer, 0)} #{elem(@consumer, 1)})"}
            fill="none"
            stroke-linecap="butt"
          >
          </g>
        </svg>

        <.ring name={:pv} label="PV-Anlage" watts={pv_watts(@flow)} plush="sun" />
        <.ring
          name={:grid}
          label={direction(@flow.grid_w, "Netzbezug", "Überschuss", "Stromnetz")}
          watts={magnitude(@flow.grid_w)}
          plush="utility-pole"
        />
        <.ring name={:consumer} label="Verbrauch" watts={@flow.home_w} plush="household" />
        <.ring
          name={:battery}
          label={battery_label(@flow)}
          watts={magnitude(@flow.battery_w)}
          plush={battery_plush(@flow.battery_state)}
        />
      </div>
    </.card>
    """
  end

  attr :name, :atom, required: true
  attr :label, :string, required: true
  attr :watts, :any, required: true
  attr :plush, :string, required: true
  attr :alt, :string, default: ""

  defp ring(assigns) do
    {cx, cy, _stroke} = Keyword.fetch!(@rings, assigns.name)
    label_cy = if assigns.name == :pv, do: cy - @radius - 20, else: cy + @radius + 14

    assigns =
      assign(assigns,
        ring_style:
          style(
            left: percent(cx, @width),
            top: percent(cy, @height),
            width: percent(2 * @radius, @width),
            height: percent(2 * @radius, @height)
          ),
        label_style: style(left: percent(cx, @width), top: percent(label_cy, @height))
      )

    ~H"""
    <div class="ef-ring" style={@ring_style} data-ring={@name}>
      <.plush name={@plush} alt={@alt} class="size-[calc(38*var(--ef-unit))]" />
      <span class="ef-value font-semibold leading-none whitespace-nowrap tabular-nums">
        {number(@watts, unit: "W")}
      </span>
    </div>
    <p
      class="ef-name leading-tight whitespace-nowrap text-base-content/70"
      style={@label_style}
      data-name={@name}
    >
      {@label}
    </p>
    """
  end

  # Below this a reading is noise, not a direction.
  @idle_w 1

  defp pv_watts(%Flow{solakon_online: true, solar_w: watts}), do: max(watts || 0, 0)
  defp pv_watts(%Flow{}), do: nil

  defp magnitude(nil), do: nil
  defp magnitude(watts), do: abs(watts)

  defp direction(watts, _positive, _negative, idle) when is_nil(watts) or abs(watts) < @idle_w,
    do: idle

  defp direction(watts, positive, _negative, _idle) when watts > 0, do: positive
  defp direction(_watts, _positive, negative, _idle), do: negative

  defp battery_label(%Flow{battery_w: watts, battery_soc_pct: soc}) do
    name = direction(watts, "Batterie lädt", "Batterie entlädt", "Batterie")
    if soc, do: join_meta([name, number(soc, unit: "%")]), else: name
  end

  defp style(properties),
    do: Enum.map_join(properties, "; ", fn {property, value} -> "#{property}: #{value}" end)

  defp percent(units, extent), do: css_number(units * 100.0 / extent) <> "%"

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
