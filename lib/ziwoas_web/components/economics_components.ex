defmodule ZiwoasWeb.EconomicsComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Economics.Overview
  alias ZiwoasWeb.Charts.Series

  @min_projection_days 90

  @spec since(Overview.t()) :: String.t() | nil
  def since(%Overview{data_start: nil}), do: nil
  def since(%Overview{data_start: start}), do: "seit #{date(start)}"

  attr :result, Overview, required: true
  attr :heading, :boolean, default: true, doc: "off where the page header names it"

  def overview(assigns) do
    result = assigns.result

    assigns =
      assign(assigns,
        payback_label: payback_label(result),
        payback_value: payback_value(result),
        covered_pct: result.covered_ratio && result.covered_ratio * 100,
        since: assigns.heading && since(result),
        hint: hint(result)
      )

    ~H"""
    <section id="economics" aria-labelledby={@heading && "economics-heading"}>
      <.overview_heading :if={@heading} costed={@result.costed} />
      <div class="flex flex-col gap-4">
        <div class="setzkasten-stat-grid grid grid-cols-2 md:grid-cols-3 gap-4">
          <.stat id="economics-cost" label="Anschaffungs­kosten" size={:sm}>
            <.euro value={@result.acquisition_cost_eur} />
          </.stat>
          <.stat id="economics-saved" label="Ersparnis" size={:sm}>
            <.euro value={@result.saved_eur} />
          </.stat>
          <.stat
            id="economics-payback"
            label={@payback_label}
            value={@payback_value}
            size={:sm}
            class="col-span-2 md:col-span-1"
          />
        </div>
        <.bar
          :if={@covered_pct}
          id="economics-covered"
          label="Zurückverdient"
          value={min(@covered_pct, 100)}
          color={Series.of(:solar)}
          show_value
          value_label={number(@covered_pct, precision: 1, unit: "%")}
          data-economics-covered-pct={round(@covered_pct)}
        />
        <div class="flex flex-col gap-1 text-sm text-base-content/70 max-w-prose">
          <p>
            <span :if={@since}>{String.capitalize(@since)}.</span>
            Gerechnet wird nur mit dem Strom, den die gemessenen Verbraucher im selben
            Moment genutzt haben. Eingespeister Strom wird nicht vergütet und zählt nicht.
          </p>
          <p :if={@hint} data-economics-hint>{@hint}</p>
        </div>
      </div>
    </section>
    """
  end

  attr :costed, :boolean, default: nil, doc: "nil while the overview is unknown"

  def overview_heading(assigns) do
    ~H"""
    <.section_heading id="economics-heading">
      Wirtschaftlichkeit
      <:actions>
        <.button size={:sm} navigate={~p"/solakon/wirtschaftlichkeit"}>
          {if @costed == false, do: "Kosten erfassen", else: "Kosten und Preise pflegen"}
        </.button>
      </:actions>
    </.section_heading>
    """
  end

  attr :value, :any, required: true

  def euro(%{value: nil} = assigns), do: ~H"—"
  def euro(assigns), do: ~H|<.amount value={Decimal.from_float(@value * 1.0)} />|

  defp payback_label(result),
    do: if(Overview.reached?(result), do: "Amortisiert", else: "Voraus­sichtliche Amortisation")

  defp payback_value(result) do
    cond do
      Overview.reached?(result) -> date(result.reached_on)
      result.projected_payback_date -> date(result.projected_payback_date)
      short_of_data?(result) -> "Noch zu wenig Daten"
      true -> "—"
    end
  end

  defp short_of_data?(result),
    do: result.priced and result.costed and result.projection_days < @min_projection_days

  defp hint(result) do
    cond do
      not result.priced -> "Noch kein Strompreis erfasst."
      not result.costed -> "Noch keine Kosten erfasst."
      result.projected_payback_date -> "Hochrechnung aus #{result.projection_days} Tagen."
      short_of_data?(result) -> "Basis sind erst #{result.projection_days} Tage."
      true -> nil
    end
  end
end
