defmodule ZiwoasWeb.ReportsComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Energy.Report

  @presets [{:last_7, "7 Tage"}, {:last_30, "30 Tage"}]

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
        presets: @presets,
        custom: assigns.preset == :custom,
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
          class={["btn btn-outline-primary flex-fill", @preset == preset && "active"]}
          aria-current={@preset == preset && "page"}
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

  defp plug_color(position), do: Enum.at(@plug_colors, Integer.mod(position || 0, 10))
  defp producer_color, do: "var(--viz-solar)"

  defp energy_tile(label, kwh, signed \\ false),
    do: measure_tile(nil, label, kwh, "kWh", 2, signed)

  defp money_tile(label, eur), do: measure_tile(nil, label, eur, "€", 2)

  defp share_tile(label, ratio),
    do: measure_tile(nil, label, (ratio || 0) * 100, "%", 1)

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
          {number(@row.kwh, precision: 2)} kWh
        </span>
      </div>
    </li>
    """
  end

  defp share(kwh, max_kwh) when max_kwh > 0, do: Float.round(kwh * 1.0 / max_kwh * 100, 1)
  defp share(_kwh, _max_kwh), do: 0

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

  def power_subtitle(%Report{start_date: from, end_date: to}, today) do
    resolution = if Date.diff(to, from) > 6, do: "Tagesmittel", else: "5-Min-Werte"
    day = &if(&1.year == today.year, do: day_month(&1), else: date(&1))
    range = if from == to, do: day.(from), else: "#{day.(from)}–#{day.(to)}"
    "Watt · #{resolution} · #{range}"
  end

  defp presence(value) when is_binary(value), do: if(String.trim(value) != "", do: value)
  defp presence(_value), do: nil
end
