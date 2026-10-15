defmodule ZiwoasWeb.ReportsComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Energy
  alias Ziwoas.Energy.{Amount, DailyPoint, Report}
  alias Ziwoas.Plugs.Roster
  alias ZiwoasWeb.Charts.Categories
  alias ZiwoasWeb.DashboardComponents

  @presets [{:last_7, "Letzte 7 Tage"}, {:last_30, "Letzte 30 Tage"}]

  attr :report, Report, required: true
  attr :preset, :atom, required: true, doc: ":last_7, :last_30 or :custom"
  attr :params, :map, required: true

  def range_picker(assigns) do
    form =
      to_form(%{
        "start_date" => presence(assigns.params["start_date"]) || assigns.report.start_date,
        "end_date" => presence(assigns.params["end_date"]) || assigns.report.end_date
      })

    assigns =
      assign(assigns,
        form: form,
        presets:
          for(
            {preset, label} <- @presets,
            do: %{label: label, value: preset, path: ~p"/reports?#{[preset: preset]}"}
          )
      )

    ~H"""
    <section
      aria-label="Zeitraum"
      class="flex flex-col gap-4 sm:flex-row sm:flex-wrap sm:items-end sm:justify-between"
    >
      <.segmented
        id="range_presets"
        mode={:patch}
        label="Schnellauswahl"
        value={@preset}
        options={@presets}
        block={:phone}
      />
      <.form
        for={@form}
        id="range_form"
        class="grid grid-cols-2 items-end gap-x-3 sm:flex"
        phx-submit="apply_range"
      >
        <.input
          field={@form[:start_date]}
          type="date"
          label="Von"
          min={@report.first_date}
          max={@report.last_date}
          class="sm:w-40"
        />
        <.input
          field={@form[:end_date]}
          type="date"
          label="Bis"
          min={@report.first_date}
          max={@report.last_date}
          class="sm:w-40"
        />
        <.button type="submit" class="col-span-2 mt-2 sm:mt-0" phx-disable-with="Anwenden">
          Anwenden
        </.button>
      </.form>
    </section>
    """
  end

  defp energy_tile(label, kwh), do: measure_stat(nil, label, kwh, "kWh", 2)

  defp money_tile(label, eur), do: measure_stat(nil, label, eur, "€", 2)

  defp share_tile(label, ratio),
    do: measure_stat(nil, label, (ratio || 0) * 100, "%", 1)

  attr :summary, :map, required: true

  def summary(assigns) do
    s = assigns.summary

    assigns =
      assign(assigns, :tiles, [
        energy_tile("Ertrag", s.produced_kwh),
        energy_tile("Verbrauch", s.consumed_kwh),
        money_tile("Gespart", s.savings_eur),
        DashboardComponents.energy_balance_stat(nil, "Bilanz", s.balance_kwh),
        share_tile("Autarkie", s.autarky_ratio),
        share_tile("Eigen­verbrauchs­quote", s.self_consumption_ratio),
        energy_tile("Ø Ertrag je Tag", s.avg_produced_kwh),
        energy_tile("Ø Verbrauch je Tag", s.avg_consumed_kwh)
      ])

    ~H"""
    <section
      class="setzkasten-stat-grid grid grid-cols-2 gap-4 md:grid-cols-4 md:gap-6"
      aria-label="Zusammenfassung"
    >
      <.stat :for={tile <- @tiles} {tile} size={:sm} />
    </section>
    """
  end

  attr :producers, :list, required: true
  attr :consumers, :list, required: true

  def ranking(assigns) do
    groups =
      [
        {"producers", "Erzeugung", assigns.producers, false},
        {"consumers", "Verbrauch", assigns.consumers, true}
      ]
      |> Enum.reject(fn {_id, _label, rows, _ranked} -> rows == [] end)
      |> Enum.map(fn {id, label, rows, ranked} ->
        total = rows |> Enum.map(& &1.kwh) |> Enum.sum()

        %{
          id: id,
          label: label,
          rows:
            rows
            |> Enum.with_index(1)
            |> Enum.map(fn {row, place} ->
              Map.merge(row, %{share: share(row.kwh, total), place: ranked && place})
            end)
        }
      end)

    assigns = assign(assigns, :groups, groups)

    ~H"""
    <section aria-labelledby="ranking_heading">
      <.section_heading id="ranking_heading">Steckdosen</.section_heading>
      <.table
        :if={@groups != []}
        id="ranking"
        groups={@groups}
        row_id={&"ranking-plug-#{&1.plug_id}"}
        row_attrs={&%{"data-plug-id" => &1.plug_id}}
      >
        <:col :let={row} label="Platz" align={:end} class="w-px text-base-content/70">
          <span :if={row.place} data-role="place">{row.place}</span>
        </:col>
        <:col :let={row} label="Steckdose">
          <.bar
            label={row.name}
            value={row.share}
            tone={:neutral}
            show_value
            value_label={number(row.share, unit: "%")}
            data-role="share"
          />
        </:col>
        <:col :let={row} label="Energie" align={:end}>
          {number(row.kwh, precision: 2, unit: "kWh")}
        </:col>
      </.table>
      <.empty_state :if={@groups == []} title="Keine Steckdosendaten">
        Für diesen Zeitraum liegen keine Tageswerte der Steckdosen vor.
      </.empty_state>
    </section>
    """
  end

  defp share(kwh, total) when total > 0, do: Float.round(kwh * 1.0 / total * 100, 1)
  defp share(_kwh, _total), do: 0.0

  attr :report, Report, required: true
  attr :today, Date, required: true
  attr :charts, :map, default: nil, doc: "`Charts.EnergyReport.payload/2`, nil until connected"
  attr :weather, :map, required: true, doc: "which charts show the weather"
  attr :weather_available, :map, required: true
  attr :rank, :list, required: true, doc: "consumer ids by `Ziwoas.Plugs.consumer_rank/2`"
  attr :roster, Roster, required: true

  def charts(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 md:gap-6">
      <.chart_card
        id="report_daily"
        title="Energie"
        subtitle="kWh je Tag"
        summary={daily_summary(@report)}
        hook="EnergyReport"
        hook_attrs={hook_attrs(@charts, "daily", &(&1.daily |> with_assets(&1) |> ranked(@rank)))}
        loading={is_nil(@charts)}
        height={:lg}
      >
        <:actions :if={@weather_available.daily}>
          <.weather_switch chart="daily" checked={@weather.daily} />
        </:actions>
        <:legend>
          <.legend items={daily_legend(@report, @rank, @weather.daily and @weather_available.daily)} />
        </:legend>
        <:data>
          <.table
            id="report_daily_data"
            rows={@report.daily_points}
            row_id={&"day-#{&1.date}"}
            size={:sm}
            flush
          >
            <:col :let={point} label="Tag">{date(point.date)}</:col>
            <:col :let={point} label="Ertrag" align={:end}>{kwh(point, :produced)}</:col>
            <:col :let={point} label="Verbrauch" align={:end}>{kwh(point, :consumed)}</:col>
          </.table>
        </:data>
      </.chart_card>

      <.chart_card
        id="report_detail"
        title="Leistung"
        subtitle={power_subtitle(@report, @today)}
        summary={"Leistung von PV und Verbrauch, #{power_subtitle(@report, @today)}"}
        hook="EnergyReport"
        hook_attrs={hook_attrs(@charts, "detail", &(&1.detail |> with_assets(&1) |> ranked(@rank)))}
        loading={is_nil(@charts)}
        height={:lg}
      >
        <:actions :if={@weather_available.detail}>
          <.weather_switch chart="detail" checked={@weather.detail} />
        </:actions>
        <:legend>
          <.legend items={
            detail_legend(@report, @roster, @rank, @weather.detail and @weather_available.detail)
          } />
        </:legend>
      </.chart_card>

      <.chart_card
        id="report_ratios"
        title="Autarkie und Eigenverbrauchsquote"
        subtitle="Prozent je Tag"
        summary={ratios_summary(@report.summary)}
        hook="EnergyReport"
        hook_attrs={hook_attrs(@charts, "ratios", &%{ratios: &1.daily.ratios})}
        loading={is_nil(@charts)}
      >
        <:legend>
          <.legend items={[
            %{label: "Autarkie", color: 3},
            %{label: "Eigenverbrauchsquote", color: 2, marker: :line}
          ]} />
        </:legend>
        <:data>
          <.table
            id="report_ratios_data"
            rows={@report.daily_points}
            row_id={&"ratio-#{&1.date}"}
            size={:sm}
            flush
          >
            <:col :let={point} label="Tag">{date(point.date)}</:col>
            <:col :let={point} label="Autarkie" align={:end}>
              {ratio(point, &Energy.autarky_ratio/1)}
            </:col>
            <:col :let={point} label="Eigenverbrauchsquote" align={:end}>
              {ratio(point, &Energy.self_consumption_ratio/1)}
            </:col>
          </.table>
        </:data>
      </.chart_card>
    </div>
    """
  end

  defp hook_attrs(nil, _chart, _fun), do: %{}

  defp hook_attrs(charts, chart, fun),
    do: %{"data-chart" => chart, "data-payload" => JSON.encode!(fun.(charts))}

  defp with_assets(chart, charts), do: Map.put(chart, :weather_assets, charts.weather_assets)

  defp ranked(chart, rank), do: Map.put(chart, :consumer_order, rank)

  attr :chart, :string, required: true
  attr :checked, :boolean, required: true

  defp weather_switch(assigns) do
    ~H"""
    <form id={"report_#{@chart}_weather"} phx-change="toggle_weather">
      <input type="hidden" name="chart" value={@chart} />
      <.input
        type="toggle"
        id={"report-#{@chart}-weather"}
        name="visible"
        checked={@checked}
        label="Wetter"
        data-weather-toggle={@chart}
      />
    </form>
    """
  end

  @irradiance_daily %{label: "Einstrahlung (kWh/m²)", color: 2, marker: :dashed}
  @irradiance_detail %{label: "Einstrahlung (W/m²)", color: 2, marker: :dashed}

  defp daily_legend(%Report{consumer_daily: consumers}, rank, weather) do
    consumed =
      if consumers == [],
        do: [%{label: "Verbrauch", color: 1}],
        else: Categories.legend(Enum.map(consumers, &{&1.plug_id, &1.name}), rank, [:solar])

    [%{label: "Ertrag", color: 2}] ++ consumed ++ if(weather, do: [@irradiance_daily], else: [])
  end

  defp detail_legend(%Report{detail: %{series: series} = detail}, roster, rank, weather) do
    producer_ids = Roster.producer_ids(roster)
    {producers, consumers} = Enum.split_with(series, &(&1.plug_id in producer_ids))
    produced = Enum.map(producers, &%{label: &1.name, color: 2})

    case detail.resolution do
      :daily_mean ->
        produced ++ Categories.legend(Enum.map(consumers, &{&1.plug_id, &1.name}), rank, [:solar])

      :five_minutes ->
        total =
          if consumers != [], do: [%{label: "Gesamtverbrauch", color: :neutral, marker: :line}]

        produced ++ List.wrap(total) ++ if(weather, do: [@irradiance_detail], else: [])
    end
  end

  defp daily_summary(%Report{summary: summary} = report) do
    "Ertrag #{number(summary.produced_kwh, precision: 2, unit: "kWh")} und Verbrauch " <>
      "#{number(summary.consumed_kwh, precision: 2, unit: "kWh")} vom " <>
      "#{date(report.start_date)} bis #{date(report.end_date)}"
  end

  defp ratios_summary(summary) do
    "Autarkie #{number(summary.autarky_ratio * 100, precision: 1, unit: "%")}, " <>
      "Eigenverbrauchsquote #{number(summary.self_consumption_ratio * 100, precision: 1, unit: "%")} im Zeitraum"
  end

  defp kwh(%DailyPoint{covered: false}, _field), do: number(nil, unit: "kWh")

  defp kwh(%DailyPoint{} = point, field),
    do:
      point
      |> Map.fetch!(field)
      |> Amount.kwh()
      |> number(precision: 2, unit: "kWh")

  defp ratio(%DailyPoint{covered: false}, _fun), do: number(nil, unit: "%")
  defp ratio(%DailyPoint{} = point, fun), do: number(fun.(point) * 100, precision: 1, unit: "%")

  def power_subtitle(%Report{start_date: from, end_date: to}, today) do
    resolution = if Date.diff(to, from) > 6, do: "Tagesmittel", else: "5-Min-Werte"
    day = &if(&1.year == today.year, do: day_month(&1), else: date(&1))
    range = if from == to, do: day.(from), else: "#{day.(from)}–#{day.(to)}"
    "Watt · #{resolution} · #{range}"
  end

  defp presence(value) when is_binary(value), do: if(String.trim(value) != "", do: value)
  defp presence(_value), do: nil
end
