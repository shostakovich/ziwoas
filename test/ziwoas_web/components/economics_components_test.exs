defmodule ZiwoasWeb.EconomicsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Ziwoas.Economics.Overview
  alias ZiwoasWeb.EconomicsComponents

  defp result(overrides \\ []) do
    struct!(
      %Overview{
        saved_eur: 200.0,
        acquisition_cost_eur: 1000.0,
        covered_ratio: 0.2,
        data_start: ~D[2026-02-14],
        projected_payback_date: ~D[2028-11-09],
        reached_on: nil,
        projection_days: 200,
        priced: true,
        costed: true
      },
      overrides
    )
  end

  defp card(result, opts \\ []) do
    (&EconomicsComponents.overview_card/1)
    |> render_component([result: result] ++ opts)
    |> LazyHTML.from_fragment()
  end

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  defp covered(doc),
    do:
      doc
      |> LazyHTML.query("[data-economics-covered-pct]")
      |> LazyHTML.attribute("data-economics-covered-pct")

  test "shows cost, savings, covered share and the projected date" do
    doc = card(result())

    assert texts(doc, ".card-title") == ["Wirtschaftlichkeit"]
    assert texts(doc, ".card-subtitle") == ["seit 14.02.2026"]
    assert texts(doc, ".stat-value") == ["1.000,00 €", "200,00 €", "20,0 %", "09.11.2028"]
    assert covered(doc) == ["20"]

    assert texts(doc, ".stat-label") ==
             [
               "Anschaffungs­kosten",
               "Ersparnis",
               "Zurückverdient",
               "Voraus­sichtliche Amortisation"
             ]

    assert "Hochrechnung aus 200 Tagen." in texts(doc, "p")
    assert texts(doc, "a.btn") == ["Kosten und Preise pflegen"]

    assert doc |> LazyHTML.query("a.btn") |> LazyHTML.attribute("href") == [
             "/solakon/wirtschaftlichkeit"
           ]
  end

  test "the covered share rounds from its own ratio and keeps one decimal" do
    assert covered(card(result(covered_ratio: 0.51))) == ["51"]
    assert Enum.at(texts(card(result(covered_ratio: 1.0 / 3)), ".stat-value"), 2) == "33,3 %"
  end

  test "the payback: a dash, the day it was reached, or too little data" do
    no_projection = card(result(projected_payback_date: nil))
    assert List.last(texts(no_projection, ".stat-value")) == "—"
    assert length(texts(no_projection, "p.text-body-secondary")) == 1

    reached =
      card(
        result(
          saved_eur: 1200.0,
          covered_ratio: 1.0,
          reached_on: ~D[2027-05-04],
          projected_payback_date: nil
        )
      )

    assert List.last(texts(reached, ".stat-label")) == "Amortisiert"
    assert List.last(texts(reached, ".stat-value")) == "04.05.2027"

    short = card(result(projected_payback_date: nil, projection_days: 12))
    assert List.last(texts(short, ".stat-value")) == "Noch zu wenig Daten"
    assert "Basis sind erst 12 Tage." in texts(short, "p")
  end

  test "without cost items it asks for them, without a price it says the savings are unknown" do
    uncosted =
      card(
        result(
          acquisition_cost_eur: 0.0,
          costed: false,
          covered_ratio: nil,
          projected_payback_date: nil,
          projection_days: 10
        )
      )

    assert texts(uncosted, "a.btn") == ["Kosten erfassen"]
    assert covered(uncosted) == []
    assert Enum.at(texts(uncosted, ".stat-value"), 2) == "—"
    assert "Noch keine Kosten erfasst." in texts(uncosted, "p")

    unpriced =
      card(
        result(
          saved_eur: nil,
          covered_ratio: nil,
          priced: false,
          projected_payback_date: nil,
          projection_days: 10
        )
      )

    assert Enum.at(texts(unpriced, ".stat-value"), 1) == "—"
    assert "Noch kein Strompreis erfasst." in texts(unpriced, "p")
  end

  test "without any data it names no start date; on its own page it takes a title and no link" do
    assert texts(card(result(data_start: nil)), ".card-subtitle") == []

    own = card(result(), title: "Stand", link: false)
    assert texts(own, ".card-title") == ["Stand"]
    assert texts(own, "a") == []
  end
end
