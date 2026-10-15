defmodule ZiwoasWeb.DashboardComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Energy
  alias Ziwoas.Energy.{Amount, Balance, Flow, LiveState}
  alias Ziwoas.Plugs.Roster
  alias ZiwoasWeb.Charts
  alias ZiwoasWeb.Charts.Categories
  alias ZiwoasWeb.Components.EnergyFlow

  attr :live, LiveState, required: true
  attr :weather_plush, :string, required: true
  attr :weather_alt, :string, required: true
  attr :class, :any, default: nil

  def hero(assigns) do
    flow = assigns.live.energy_flow

    assigns =
      assign(assigns,
        pv_watt: pv_watt(assigns.live),
        battery: flow.solakon_online,
        soc: flow.battery_soc_pct,
        battery_plush: EnergyFlow.battery_plush(flow.battery_state),
        battery_alt: EnergyFlow.battery_alt(flow.battery_state)
      )

    ~H"""
    <section
      id="dashboard_hero"
      aria-label="Jetzt"
      class={["card @container bg-warning text-warning-content", @class]}
    >
      <div class="card-body grid grid-cols-2 gap-3 p-4 @md:gap-4 @md:p-6">
        <.hero_value id="hero_pv" label="PV jetzt" value={number(@pv_watt)} unit="W">
          <.plush name={@weather_plush} alt={@weather_alt} size={:xl} class="@md:size-16 @xl:size-20" />
        </.hero_value>
        <.hero_value :if={@battery} id="hero_battery" label="Batterie" value={number(@soc)} unit="%">
          <.plush name={@battery_plush} alt={@battery_alt} size={:xl} class="@md:size-16 @xl:size-20" />
        </.hero_value>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :unit, :string, required: true
  slot :inner_block, required: true

  defp hero_value(assigns) do
    ~H"""
    <div class="flex min-w-0 items-center gap-2.5 @md:gap-4">
      {render_slot(@inner_block)}
      <div class="min-w-0">
        <p class="text-sm font-medium text-warning-content/80">{@label}</p>
        <p id={@id} class="whitespace-nowrap font-semibold tabular-nums">
          <span class="text-2xl tracking-[-0.02em] @[22rem]:text-3xl @md:text-4xl @xl:text-5xl">{@value}</span>
          <span class="text-base text-warning-content/80 @md:text-xl">{@unit}</span>
        </p>
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
    net_kwh = (summary.produced.wh - summary.consumed.wh) / 1000.0

    [
      energy("tile_produced", "Erzeugt", Amount.kwh(summary.produced)),
      energy("tile_consumed", "Verbraucht", Amount.kwh(summary.consumed)),
      measure_stat("tile_savings", "Gespart", summary.savings_eur, "€", 2),
      energy_balance_stat("tile_net_today", "Bilanz", net_kwh),
      share("tile_autarky", "Autarkie", Energy.autarky_ratio(summary)),
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
    net_w = flow.grid_w && -flow.grid_w

    [
      "tile_consumption_now"
      |> measure_stat("Verbrauch jetzt", if(any_online, do: flow.home_w), "W", 0)
      |> Map.put(:desc, sources(flow)),
      balance_stat("tile_netbalance_now", "Bilanz jetzt", net_w, "W", 0,
        positive: "Überschuss",
        negative: "Netzbezug"
      )
    ]
  end

  @doc "Produced minus consumed energy in kWh as its magnitude and a word: no sign, no verdict colour."
  @spec energy_balance_stat(String.t() | nil, String.t(), number | nil) :: map
  def energy_balance_stat(id, label, kwh),
    do: balance_stat(id, label, kwh, "kWh", 2, positive: "Überschuss", negative: "Mehrverbrauch")

  defp balance_stat(id, label, nil, unit, precision, _words),
    do: measure_stat(id, label, nil, unit, precision)

  defp balance_stat(id, label, value, unit, precision, words) do
    direction =
      case Float.round(value * 1.0, precision) do
        rounded when rounded > 0 -> Keyword.fetch!(words, :positive)
        rounded when rounded < 0 -> Keyword.fetch!(words, :negative)
        _even -> "ausgeglichen"
      end

    id |> measure_stat(label, abs(value), unit, precision) |> Map.put(:desc, direction)
  end

  @sources [solar_to_home_w: "PV", battery_to_home_w: "Batterie", grid_to_home_w: "Netz"]
  @single_source %{"PV" => "aus PV", "Batterie" => "aus der Batterie", "Netz" => "aus dem Netz"}

  defp sources(%Flow{flows: flows}) do
    names = for {key, name} <- @sources, (Map.fetch!(flows, key) || 0) >= 1, do: name

    case names do
      [] -> nil
      [name] -> @single_source[name]
      names -> "aus #{Enum.join(Enum.drop(names, -1), ", ")} und #{List.last(names)}"
    end
  end

  defp energy(id, label, kwh), do: measure_stat(id, label, kwh, "kWh", 2)

  defp share(id, label, ratio), do: measure_stat(id, label, (ratio || 0) * 100, "%", 1)

  attr :live, LiveState, required: true
  attr :rank, :list, required: true, doc: "consumer ids by `Ziwoas.Plugs.consumer_rank/2`"
  attr :class, :any, default: nil

  def plug_bar(assigns) do
    plugs = assigns.live.plugs
    series = Categories.series(assigns.rank, [:solar])

    entries =
      plugs
      |> Enum.filter(&(&1.role == :consumer and &1.online and (&1.apower_w || 0) > 0))
      |> Enum.sort_by(&(-&1.apower_w))
      |> Enum.map(fn plug ->
        %{id: plug.id, name: plug.name, watts: plug.apower_w, series: series[plug.id] || :other}
      end)

    assigns =
      assign(assigns,
        entries: entries,
        producers: Enum.filter(plugs, &(&1.role == :producer and &1.online)),
        total_w: entries |> Enum.map(& &1.watts) |> Enum.sum()
      )

    ~H"""
    <.card id="dashboard_plug_bar" title="Steckdosen" class={@class}>
      <.share_bar
        :if={@entries != []}
        id="dashboard_plug_shares"
        label="Gesamt"
        value_label={number(@total_w, unit: "W")}
        segments={
          for entry <- @entries,
              do: %{
                label: entry.name,
                value: entry.watts,
                color: entry.series,
                value_label: number(entry.watts, unit: "W")
              }
        }
        data-plugs={Enum.map_join(@entries, " ", & &1.id)}
        data-series={Enum.map_join(@entries, " ", & &1.series)}
      />
      <p :if={@entries == []} class="text-sm text-base-content/70" data-role="idle">
        Gerade zieht keine Steckdose Strom.
      </p>
      <div :if={@producers != []} class="mt-auto pt-3">
        <div class="border-t border-base-content/10 pt-3">
          <p :for={plug <- @producers} class="flex items-center gap-2 text-sm" data-role="producer">
            <.plush name="sun" size={:sm} />
            <span class="min-w-0 truncate">{plug.name}</span>
            <span class="ms-auto whitespace-nowrap tabular-nums">
              erzeugt {number(plug.apower_w && abs(plug.apower_w), unit: "W")}
            </span>
          </p>
        </div>
      </div>
    </.card>
    """
  end

  attr :chart, :map, default: nil, doc: "`Charts.Dashboard.today/2`, nil until connected"
  attr :consumers, :list, required: true, doc: "`{id, name}` of the consumers"
  attr :rank, :list, required: true, doc: "consumer ids by `Ziwoas.Plugs.consumer_rank/2`"
  attr :producers, :list, required: true, doc: "producer names in config order"
  attr :roster, Roster, required: true
  attr :zone, :string, required: true

  def today_charts(assigns) do
    assigns =
      assign(
        assigns,
        :measured,
        is_nil(assigns.chart) or Charts.Dashboard.measured?(assigns.chart)
      )

    ~H"""
    <.empty_state
      :if={!@measured}
      id="today_empty"
      plush="plug"
      title="Keine Messwerte der letzten 24 Stunden"
    >
      Die Diagramme füllen sich, sobald die Steckdosen wieder melden.
    </.empty_state>
    <div :if={@measured} class="flex flex-col gap-4 md:gap-6">
      <.chart_card
        id="today_energy"
        title="Energie je Stunde"
        subtitle="kWh · letzte 24 Stunden"
        summary={summary(@chart, &Charts.Dashboard.energy_summary(&1.energy))}
        hook="TodayChart"
        hook_attrs={
          payload(@chart, "energy", &JSON.encode!(Map.put(&1.energy, :consumer_order, @rank)))
        }
        loading={is_nil(@chart)}
      >
        <:legend>
          <.legend items={[
            %{label: "Erzeugt", color: 2} | Categories.legend(@consumers, @rank, [:solar])
          ]} />
        </:legend>
        <:data :if={@chart}>
          <.table
            id="today_energy_data"
            rows={Charts.Dashboard.energy_rows(@chart.energy, @zone)}
            row_id={& &1.id}
            size={:sm}
            flush
          >
            <:col :let={row} label="Stunde">{row.time}</:col>
            <:col :let={row} label="Erzeugt" align={:end}>
              {number(row.produced, precision: 2, unit: "kWh")}
            </:col>
            <:col :let={row} label="Verbraucht" align={:end}>
              {number(row.consumed, precision: 2, unit: "kWh")}
            </:col>
          </.table>
        </:data>
      </.chart_card>

      <.chart_card
        id="today_power"
        title="Leistung"
        subtitle="Watt · letzte 24 Stunden"
        summary={summary(@chart, &Charts.Dashboard.power_summary(&1.power, @roster))}
        hook="TodayChart"
        hook_attrs={payload(@chart, "power", &JSON.encode!(&1.power))}
        loading={is_nil(@chart)}
      >
        <:legend>
          <.legend items={power_legend(@producers, @consumers)} />
        </:legend>
      </.chart_card>
    </div>
    """
  end

  defp summary(nil, _fun), do: ""
  defp summary(data, fun), do: fun.(data)

  defp payload(nil, _chart, _fun), do: %{}
  defp payload(data, chart, fun), do: %{"data-chart" => chart, "data-payload" => fun.(data)}

  defp power_legend(producers, consumers) do
    total = if consumers != [], do: [%{label: "Gesamtverbrauch", color: :neutral, marker: :line}]
    Enum.map(producers, &%{label: &1, color: 2}) ++ List.wrap(total)
  end

  attr :points, :list, default: nil, doc: "the producer's daily totals, nil until connected"

  def history_chart(%{points: []} = assigns) do
    ~H"""
    <.empty_state id="history_empty" plush="sun" title="Noch kein Ertrag aufgezeichnet">
      Jeder Tag erscheint hier nach der nächtlichen Auswertung.
    </.empty_state>
    """
  end

  def history_chart(assigns) do
    ~H"""
    <.chart_card
      id="history"
      title="Ertrag je Tag"
      subtitle="kWh · letzte 14 Tage"
      summary={summary(@points, &Charts.Dashboard.history_summary/1)}
      hook="HistoryChart"
      hook_attrs={payload(@points, "history", &JSON.encode!/1)}
      height={:sm}
      loading={is_nil(@points)}
    >
      <:data :if={@points}>
        <.table
          id="history_data"
          rows={Charts.Dashboard.history_rows(@points)}
          row_id={& &1.id}
          size={:sm}
          flush
        >
          <:col :let={row} label="Tag">{row.day}</:col>
          <:col :let={row} label="Ertrag" align={:end}>
            {number(row.kwh, precision: 2, unit: "kWh")}
          </:col>
        </.table>
      </:data>
    </.chart_card>
    """
  end
end
