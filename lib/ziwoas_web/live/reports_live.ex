defmodule ZiwoasWeb.ReportsLive do
  @moduledoc """
  The Berichte page: the energy report over a preset or custom range. The
  range lives in the query (`preset`, `start_date`, `end_date`,
  `selected_date`); presets patch to it, the range form pushes a patch.
  Nothing pushes to the page.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.ReportsComponents

  alias Ziwoas.{Clock, Config, EnergyReport}

  @params ~w[preset start_date end_date selected_date]

  @impl true
  def mount(_params, _session, socket) do
    config = Config.app_config()

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

    report =
      EnergyReport.build(
        params: params,
        plugs: socket.assigns.plugs,
        location: socket.assigns.location,
        today: socket.assigns.today
      )

    {:noreply,
     assign(socket, report: report, weather_assets: weather_assets(report), params: params)}
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
