defmodule ZiwoasWeb.ReportsLive do
  @moduledoc """
  The Berichte page (Rails' `ReportsController#index`): the energy report over
  a preset or custom range. Nothing pushes to it; it reads its range from the
  query (`preset`, `start_date`, `end_date`, `selected_date`).
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.CoreComponents
  import ZiwoasWeb.ReportsComponents

  alias Ziwoas.{Clock, Config, EnergyReport}

  @params ~w[preset start_date end_date selected_date]

  @impl true
  def mount(params, _session, socket) do
    config = Config.app_config()
    today = Clock.today(config.location.timezone)

    report =
      EnergyReport.build(
        params: Map.take(params, @params),
        plugs: config.plugs,
        location: config.location,
        today: today
      )

    {:ok,
     assign(socket,
       page_title: "Berichte",
       report: report,
       weather_assets: weather_assets(report),
       params: params,
       today: today
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app look={@look} current_path={@current_path} main_class="app-main-wide">
      <h1 class="h2 mb-3">Berichte</h1>

      <div id="energy_report" phx-hook="EnergyReport">
        <.range_picker report={@report} params={@params} />

        <p :for={message <- @report.messages} class="alert alert-warning mb-3" role="status">
          {message}
        </p>

        <%= if EnergyReport.empty?(@report) do %>
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
            <.weather_switch :if={weather?(@report, :daily)} chart="daily" />
            <div class="chart-frame" id="report_daily_chart" phx-update="ignore">
              <canvas data-chart="daily"></canvas>
            </div>
          </.card>

          <.card title="Leistung" subtitle={power_subtitle(@report, @today)}>
            <.weather_switch :if={weather?(@report, :detail)} chart="detail" />
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

        {json_script("payload", payload_json(@report))}
        {if @weather_assets != [],
          do: json_script("weather-assets", weather_assets_json(@weather_assets))}
      </div>
    </Layouts.app>
    """
  end
end
