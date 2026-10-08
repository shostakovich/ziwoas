defmodule ZiwoasWeb.ReportsLive do
  @moduledoc false
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.ReportsComponents

  alias Ziwoas.{Clock, Config, Energy}
  alias Ziwoas.Energy.Report
  alias ZiwoasWeb.{Charts, ReportRange}

  @params ~w[preset start_date end_date]

  @impl true
  def mount(_params, _session, socket) do
    config = Config.get()

    {:ok,
     assign(socket,
       page_title: "Berichte",
       plugs: config.plugs,
       location: config.location,
       today: Clock.today(config.location.timezone)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = Map.take(params, @params)
    %{range: range, preset: preset, invalid: invalid} = ReportRange.resolve(params)
    %{location: location} = socket.assigns

    report =
      Energy.report(range,
        plugs: socket.assigns.plugs,
        location: location,
        today: socket.assigns.today
      )

    charts = Charts.EnergyReport.payload(report, location.timezone)

    socket =
      assign(socket,
        report: report,
        preset: preset,
        range_invalid: invalid,
        params: params,
        weather: %{
          daily: Map.has_key?(charts.daily, :weather),
          detail: Map.has_key?(charts.detail, :weather)
        }
      )

    {:noreply,
     if(connected?(socket), do: push_event(socket, "energy_report:data", charts), else: socket)}
  end

  @impl true
  def handle_event("apply_range", params, socket) do
    range = Map.take(params, ~w[start_date end_date])
    {:noreply, push_patch(socket, to: ~p"/reports?#{range}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path} main_class="app-main-wide">
      <.header>Berichte</.header>

      <div id="energy_report" phx-hook="EnergyReport">
        <.range_picker report={@report} preset={@preset} params={@params} />

        <p :if={@range_invalid} class="alert alert-warning mb-3" role="status">
          Der Datumsbereich war ungültig und wurde auf die letzten 7 Tage zurückgesetzt.
        </p>

        <%= if Report.empty?(@report) do %>
          <.card title="Noch keine Berichtsdaten">
            <p class="mb-0">
              Die Rückschau erscheint, sobald die erste Tagesaggregation vorhanden ist.
            </p>
          </.card>
        <% else %>
          <.summary summary={@report.summary} />

          <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">Steckdosen</h2>
          <.ranking producers={@report.producer_ranking} consumers={@report.consumer_ranking} />

          <.card title="Energie" subtitle="kWh je Tag · Ertrag und Verbrauch">
            <.weather_switch :if={@weather.daily} chart="daily" />
            <div class="chart-frame" id="report_daily_chart" phx-update="ignore">
              <canvas data-chart="daily"></canvas>
            </div>
          </.card>

          <.card title="Leistung" subtitle={power_subtitle(@report, @today)}>
            <.weather_switch :if={@weather.detail} chart="detail" />
            <div class="chart-frame" id="report_detail_chart" phx-update="ignore">
              <canvas data-chart="detail"></canvas>
            </div>
          </.card>

          <.card title="Autarkie & Eigenverbrauchsquote" subtitle="Prozent je Tag">
            <div class="chart-frame" id="report_ratios_chart" phx-update="ignore">
              <canvas data-chart="ratios"></canvas>
            </div>
          </.card>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
