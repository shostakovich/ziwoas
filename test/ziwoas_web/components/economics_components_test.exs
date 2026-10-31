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

  defp overview(result, opts \\ []) do
    (&EconomicsComponents.overview/1)
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

  defp stat(doc, id), do: hd(texts(doc, "##{id} .stat-value"))
  defp hint(doc), do: texts(doc, "[data-economics-hint]")

  test "shows cost, savings and the projected date as tiles, the covered share as a bar" do
    doc = overview(result())

    assert texts(doc, "h2") == ["Wirtschaftlichkeit"]
    assert stat(doc, "economics-cost") == "1.000,00 €"
    assert stat(doc, "economics-saved") == "200,00 €"
    assert stat(doc, "economics-payback") == "09.11.2028"

    assert texts(doc, ".stat-title") ==
             ["Anschaffungs­kosten", "Ersparnis", "Voraus­sichtliche Amortisation"]

    assert covered(doc) == ["20"]
    assert texts(doc, "#economics-covered progress[aria-label]") == [""]
    assert hd(texts(doc, "#economics-covered")) == "Zurückverdient 20,0 %"

    assert [solar] =
             doc |> LazyHTML.query("#economics-covered progress") |> LazyHTML.attribute("class")

    assert solar =~ "text-chart-2-fill"
    assert hd(texts(doc, "p")) =~ ~r/^Seit 14.02.2026\. Gerechnet wird nur/
    assert hint(doc) == ["Hochrechnung aus 200 Tagen."]
    assert texts(doc, "a.btn") == ["Kosten und Preise pflegen"]

    assert doc |> LazyHTML.query("a.btn") |> LazyHTML.attribute("href") == [
             "/solakon/wirtschaftlichkeit"
           ]
  end

  test "the covered share rounds from its own ratio and keeps one decimal" do
    assert covered(overview(result(covered_ratio: 0.51))) == ["51"]

    assert hd(texts(overview(result(covered_ratio: 1.0 / 3)), "#economics-covered")) ==
             "Zurückverdient 33,3 %"

    assert overview(result(covered_ratio: 1.2))
           |> LazyHTML.query("#economics-covered progress")
           |> LazyHTML.attribute("value") == ["100"]
  end

  test "the payback: a dash, the day it was reached, or too little data" do
    no_projection = overview(result(projected_payback_date: nil))
    assert stat(no_projection, "economics-payback") == "—"
    assert hint(no_projection) == []

    reached =
      overview(
        result(
          saved_eur: 1200.0,
          covered_ratio: 1.0,
          reached_on: ~D[2027-05-04],
          projected_payback_date: nil
        )
      )

    assert List.last(texts(reached, ".stat-title")) == "Amortisiert"
    assert stat(reached, "economics-payback") == "04.05.2027"

    short = overview(result(projected_payback_date: nil, projection_days: 12))
    assert stat(short, "economics-payback") == "Noch zu wenig Daten"
    assert hint(short) == ["Basis sind erst 12 Tage."]
  end

  test "without cost items it asks for them, without a price it says the savings are unknown" do
    uncosted =
      overview(
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
    assert stat(uncosted, "economics-cost") == "0,00 €"
    assert hint(uncosted) == ["Noch keine Kosten erfasst."]

    unpriced =
      overview(
        result(
          saved_eur: nil,
          covered_ratio: nil,
          priced: false,
          projected_payback_date: nil,
          projection_days: 10
        )
      )

    assert stat(unpriced, "economics-saved") == "—"
    assert hint(unpriced) == ["Noch kein Strompreis erfasst."]
  end

  test "without any data it names no start date; under a page header it has no heading of its own" do
    refute hd(texts(overview(result(data_start: nil)), "p")) =~ "Seit"
    assert EconomicsComponents.since(result()) == "seit 14.02.2026"
    assert EconomicsComponents.since(result(data_start: nil)) == nil

    own = overview(result(), heading: false)
    assert texts(own, "h2") == []
    assert texts(own, "a") == []
    refute hd(texts(own, "p")) =~ "Seit"
  end
end
