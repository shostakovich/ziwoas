defmodule ZiwoasWeb.ReportsLive do
  @moduledoc false
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.ReportsComponents

  alias Ziwoas.{Clock, Config, Energy, Plugs}
  alias Ziwoas.Energy.Report
  alias ZiwoasWeb.{Charts, ReportRange}

  @params ~w[preset start_date end_date]

  @impl true
  def mount(_params, _session, socket) do
    config = Config.get()
    today = Clock.today(config.location.timezone)
    roster = Config.plug_roster(config)

    {:ok,
     assign(socket,
       page_title: "Berichte",
       roster: roster,
       location: config.location,
       today: today,
       rank: Plugs.consumer_rank(roster, today),
       weather: %{daily: false, detail: false}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = Map.take(params, @params)
    %{range: range, preset: preset, invalid: invalid} = ReportRange.resolve(params)
    %{location: location} = socket.assigns

    report =
      Energy.report(range,
        plugs: socket.assigns.roster,
        location: location,
        today: socket.assigns.today
      )

    charts = Charts.EnergyReport.payload(report, location.timezone)

    {:noreply,
     assign(socket,
       report: report,
       preset: preset,
       range_invalid: invalid,
       params: params,
       charts: if(connected?(socket), do: charts),
       weather_available: %{
         daily: Map.has_key?(charts.daily, :weather),
         detail: Map.has_key?(charts.detail, :weather)
       }
     )}
  end

  @impl true
  def handle_event("apply_range", params, socket) do
    range = Map.take(params, ~w[start_date end_date])
    {:noreply, push_patch(socket, to: ~p"/reports?#{range}", replace: true)}
  end

  def handle_event("toggle_weather", %{"chart" => chart, "visible" => visible}, socket)
      when chart in ~w[daily detail] do
    weather = Map.put(socket.assigns.weather, String.to_existing_atom(chart), visible == "true")
    {:noreply, assign(socket, :weather, weather)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} width={:default}>
      <.header>
        Berichte
        <:subtitle :if={!Report.empty?(@report)}>{range_label(@report)}</:subtitle>
      </.header>

      <.empty_state
        :if={Report.empty?(@report)}
        layout={:page}
        plush="chart-column"
        title="Noch keine Berichtsdaten"
      >
        Die Rückschau erscheint, sobald die erste Tagesaggregation vorhanden ist.
      </.empty_state>

      <div :if={!Report.empty?(@report)} class="flex flex-col gap-8">
        <div class="flex flex-col gap-4">
          <.range_picker report={@report} preset={@preset} params={@params} />
          <.alert :if={@range_invalid} id="range_invalid" tone={:warning}>
            Der Datumsbereich war ungültig und wurde auf die letzten 7 Tage zurückgesetzt.
          </.alert>
        </div>

        <.summary summary={@report.summary} />
        <.ranking producers={@report.producer_ranking} consumers={@report.consumer_ranking} />
        <.charts
          report={@report}
          today={@today}
          charts={@charts}
          weather={@weather}
          weather_available={@weather_available}
          rank={@rank}
          roster={@roster}
        />
      </div>
    </Layouts.app>
    """
  end

  defp range_label(%Report{start_date: day, end_date: day}), do: date(day)

  defp range_label(%Report{start_date: from, end_date: to}) do
    first = if from.year == to.year, do: day_month(from), else: date(from)
    join_meta(["#{first}–#{date(to)}", "#{Date.diff(to, from) + 1} Tage"])
  end
end
