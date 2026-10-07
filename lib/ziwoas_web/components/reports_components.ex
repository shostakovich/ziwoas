defmodule ZiwoasWeb.ReportsComponents do
  @moduledoc """
  The parts of the Berichte page: range picker, plug ranking, chart cards and
  the chart payload the `EnergyReport` hook reads.
  """
  use ZiwoasWeb, :html

  import ZiwoasWeb.DashboardComponents, only: [tile: 1]

  alias ZiwoasWeb.DashboardComponents

  alias Ziwoas.EnergyReport

  @presets [{"last_7", "7 Tage"}, {"last_30", "30 Tage"}]

  @doc """
  Presets as patch links, a custom range as a form that submits `apply_range`
  to the LiveView. The fields keep what was asked for, else the report's range.
  """
  attr :report, EnergyReport, required: true
  attr :params, :map, required: true

  def range_picker(assigns) do
    form =
      to_form(%{
        "start_date" => presence(assigns.params["start_date"]) || assigns.report.start_date,
        "end_date" => presence(assigns.params["end_date"]) || assigns.report.end_date
      })

    assigns =
      assign(assigns,
        presets: @presets,
        custom: assigns.report.preset not in Enum.map(@presets, &elem(&1, 0)),
        form: form
      )

    ~H"""
    <section
      class="card card-body mb-3 d-flex flex-column flex-sm-row flex-wrap align-items-stretch align-items-sm-end justify-content-between gap-3"
      aria-label="Zeitraum"
    >
      <div class="btn-group" role="group" aria-label="Schnellauswahl">
        <.link
          :for={{preset, label} <- @presets}
          class={["btn btn-outline-primary flex-fill", @report.preset == preset && "active"]}
          aria-current={@report.preset == preset && "page"}
          patch={~p"/reports?#{[preset: preset]}"}
        ><span><span class="d-none d-sm-inline">Letzte </span>{label}</span></.link>
        <span :if={@custom} class="btn btn-outline-primary flex-fill active" aria-current="true">
          Benutzerdefiniert
        </span>
      </div>

      <.form for={@form} id="range_form" class="row g-2 align-items-end" phx-submit="apply_range">
        <.input
          field={@form[:start_date]}
          type="date"
          label="Von"
          min={@report.first_date}
          max={@report.last_date}
          wrapper_class="col-6 col-sm-auto"
        />
        <.input
          field={@form[:end_date]}
          type="date"
          label="Bis"
          min={@report.first_date}
          max={@report.last_date}
          wrapper_class="col-6 col-sm-auto"
        />
        <div class="col-12 col-sm-auto">
          <.button type="submit" class="w-100" phx-disable-with="Anwenden">Anwenden</.button>
        </div>
      </.form>
    </section>
    """
  end

  @plug_colors for n <- 1..10, do: "var(--viz-#{n})"

  # As on the dashboard's plug bar: consumers by config position, producers in the sun's colour.
  defp plug_color(position), do: Enum.at(@plug_colors, Integer.mod(position || 0, 10))
  defp producer_color, do: "var(--viz-solar)"

  # The dashboard's energy, money and share tiles, without an id.
  defp energy_tile(label, kwh, signed \\ false),
    do: DashboardComponents.measure(nil, label, kwh, "kWh", 2, signed)

  defp money_tile(label, eur), do: DashboardComponents.measure(nil, label, eur, "€", 2)

  defp share_tile(label, ratio),
    do: DashboardComponents.measure(nil, label, (ratio || 0) * 100, "%", 1)

  @doc "The eight summary tiles."
  attr :summary, :map, required: true

  def summary(assigns) do
    s = assigns.summary

    assigns =
      assign(assigns, :tiles, [
        energy_tile("Ertrag", s.produced_kwh),
        energy_tile("Verbrauch", s.consumed_kwh),
        money_tile("Gespart", s.savings_eur),
        energy_tile("Bilanz", s.balance_kwh, true),
        share_tile("Autarkie", s.autarky_ratio),
        share_tile("Eigen­verbrauchs­quote", s.self_consumption_ratio),
        energy_tile("Ø Ertrag/Tag", s.avg_produced_kwh),
        energy_tile("Ø Verbrauch/Tag", s.avg_consumed_kwh)
      ])

    ~H"""
    <section class="row row-cols-2 row-cols-md-4 g-2 mb-3" aria-label="Zusammenfassung">
      <.tile :for={tile <- @tiles} {tile} />
    </section>
    """
  end

  @doc "Producers apart, consumers numbered; bars take each plug's dashboard colour (config order, never its rank)."
  attr :producers, :list, required: true
  attr :consumers, :list, required: true

  def ranking(assigns) do
    rows = assigns.producers ++ assigns.consumers
    max_kwh = if rows != [], do: rows |> Enum.map(&(&1.kwh * 1.0)) |> Enum.max()
    assigns = assign(assigns, rows: rows, max_kwh: max_kwh)

    ~H"""
    <%= if @rows != [] do %>
      <ul :if={@producers != []} class="list-group mb-2 small" aria-label="Erzeugung">
        <.ranking_row
          :for={row <- @producers}
          row={row}
          max_kwh={@max_kwh}
          colour={producer_color()}
        >
          <img alt="Erzeuger" class="app-nav-icon" src={~p"/images/icon_sonne.webp"} />
        </.ranking_row>
      </ul>
      <ol :if={@consumers != []} class="list-group mb-3 small" aria-label="Rangliste">
        <.ranking_row
          :for={{row, index} <- Enum.with_index(@consumers, 1)}
          row={row}
          max_kwh={@max_kwh}
          colour={plug_color(row.position)}
        >
          {index}
        </.ranking_row>
      </ol>
    <% else %>
      <p class="small text-body-secondary">Keine Daten</p>
    <% end %>
    """
  end

  attr :row, :map, required: true
  attr :max_kwh, :float, required: true
  attr :colour, :string, required: true
  slot :inner_block, required: true

  defp ranking_row(assigns) do
    assigns = assign(assigns, :share, share(assigns.row.kwh, assigns.max_kwh))

    ~H"""
    <li class="list-group-item" data-plug-id={@row.plug_id}>
      <div class="row gx-2 gy-1 align-items-center">
        <span class="col-1 text-body-secondary tabular-nums">{render_slot(@inner_block)}</span>
        <span class="col col-sm-4 col-md-3 text-truncate">{@row.name}</span>
        <span class="col-11 offset-1 order-last col-sm offset-sm-0 order-sm-0">
          <span class="progress" style="height: .5rem" aria-hidden="true">
            <span class="progress-bar" style={"width: #{@share}%; background-color: #{@colour}"}></span>
          </span>
        </span>
        <span class="col-auto col-sm-3 col-md-2 text-end tabular-nums text-nowrap">
          {de_number(@row.kwh, precision: 2)} kWh
        </span>
      </div>
    </li>
    """
  end

  defp share(kwh, max_kwh) when max_kwh > 0, do: Float.round(kwh * 1.0 / max_kwh * 100, 1)
  defp share(_kwh, _max_kwh), do: 0

  @doc "The switch that overlays weather on a chart (`daily` or `detail`)."
  attr :chart, :string, required: true

  def weather_switch(assigns) do
    ~H"""
    <div class="d-flex align-items-center mb-2">
      <div class="form-check form-switch mb-0">
        <input
          type="checkbox"
          class="form-check-input"
          role="switch"
          id={"report-#{@chart}-weather"}
          phx-update="ignore"
          data-weather-toggle={@chart}
        />
        <label class="form-check-label" for={"report-#{@chart}-weather"}>Wetter einblenden</label>
      </div>
    </div>
    """
  end

  @doc "The Leistung card's subtitle: resolution and range, the year only when it is not this one."
  def power_subtitle(%EnergyReport{detail_start_date: from, detail_end_date: to}, today) do
    resolution = if Date.diff(to, from) > 6, do: "Tagesmittel", else: "5-Min-Werte"
    day = &Calendar.strftime(&1, if(&1.year == today.year, do: "%d.%m.", else: "%d.%m.%Y"))
    range = if from == to, do: day.(from), else: "#{day.(from)}–#{day.(to)}"
    "Watt · #{resolution} · #{range}"
  end

  @doc "Whether the chart (`:daily` or `:detail`) carries a weather overlay."
  def weather?(%EnergyReport{chart_payload: payload}, chart),
    do: Map.has_key?(Map.fetch!(payload, chart), :weather)

  @doc "The chart payload as JSON for the `payload` island."
  def payload_json(%EnergyReport{chart_payload: payload}), do: json_escape(payload)

  @doc "Every weather icon's asset path by name, daily icons first (the `weather-assets` island)."
  def weather_assets(%EnergyReport{chart_payload: payload}) do
    [payload.daily, payload.detail]
    |> Enum.flat_map(&get_in(&1, [Access.key(:weather, %{}), Access.key(:icons, [])]))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce([], fn %{asset_name: name}, acc ->
      if List.keymember?(acc, name, 0), do: acc, else: acc ++ [{name, ~p"/images/#{name}"}]
    end)
  end

  def weather_assets_json(assets), do: json_escape(Map.new(assets))

  @doc """
  A JSON data island for the `EnergyReport` hook, written whole: the HEEx
  formatter would wrap a `<script>` body in whitespace.
  """
  def json_script(name, json) do
    raw(~s(<script type="application/json" data-island="#{name}">#{json}</script>))
  end

  # Safe inside <script>: no "</script>" or HTML comment can close it early.
  defp json_escape(data) do
    data
    |> JSON.encode!()
    |> String.replace("<", "\\u003c")
    |> String.replace(">", "\\u003e")
    |> String.replace("&", "\\u0026")
    |> String.replace(<<0x2028::utf8>>, "\\u2028")
    |> String.replace(<<0x2029::utf8>>, "\\u2029")
  end

  defp presence(value) when is_binary(value), do: if(String.trim(value) != "", do: value)
  defp presence(_value), do: nil
end
