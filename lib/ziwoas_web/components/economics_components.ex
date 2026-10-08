defmodule ZiwoasWeb.EconomicsComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Economics.Overview

  @min_projection_days 90

  attr :result, Overview, required: true
  attr :title, :string, default: "Wirtschaftlichkeit"
  attr :link, :boolean, default: true

  def overview_card(assigns) do
    result = assigns.result

    assigns =
      assign(assigns,
        subtitle: result.data_start && "seit #{date(result.data_start)}",
        tiles: [
          {"Anschaffungs­kosten", eur(result.acquisition_cost_eur)},
          {"Ersparnis", eur(result.saved_eur)},
          {"Zurückverdient", covered_value(result)},
          {payback_label(result), payback_value(result)}
        ],
        covered_value: covered_value(result),
        covered_pct: result.covered_ratio && round(result.covered_ratio * 100),
        hint: hint(result)
      )

    ~H"""
    <.card title={@title} subtitle={@subtitle}>
      <div class="row row-cols-2 row-cols-md-4 g-3 mb-3 economics-tiles">
        <div :for={{label, value} <- @tiles} class="col d-flex">
          <div class="stat flex-grow-1">
            <span class="stat-label">{label}</span>
            <span class="stat-value fs-4 mt-auto">{value}</span>
          </div>
        </div>
      </div>

      <div
        :if={@covered_pct}
        class="progress mb-3"
        role="progressbar"
        aria-label={"#{@covered_value} der Anschaffungskosten zurückverdient"}
        aria-valuenow={@covered_pct}
        aria-valuemin="0"
        aria-valuemax="100"
        data-economics-covered-pct={@covered_pct}
      >
        <div class="progress-bar bg-warning" style={"width: #{@covered_pct}%"}></div>
      </div>

      <p class="small text-body-secondary">
        Gerechnet wird nur mit dem Strom, den die gemessenen Verbraucher im selben
        Moment genutzt haben. Eingespeister Strom wird nicht vergütet und zählt nicht.
      </p>

      <p :if={@hint} class="small text-body-secondary">{@hint}</p>

      <.button
        :if={@link}
        variant="outline-secondary"
        size="sm"
        navigate={~p"/solakon/wirtschaftlichkeit"}
      >
        {if @result.costed, do: "Kosten und Preise pflegen", else: "Kosten erfassen"}
      </.button>
    </.card>
    """
  end

  defp covered_value(%Overview{covered_ratio: nil}), do: "—"

  defp covered_value(%Overview{covered_ratio: ratio}),
    do: number(ratio * 100, precision: 1, unit: "%")

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
