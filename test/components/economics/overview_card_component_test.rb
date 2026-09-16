require "test_helper"

class Economics::OverviewCardComponentTest < ViewComponent::TestCase
  cover "Economics::OverviewCardComponent*"

  def result(**overrides)
    defaults = {
      saved_eur: 200.0, acquisition_cost_eur: 1000.0, covered_ratio: 0.2,
      data_start: Date.new(2026, 2, 14), projected_payback_date: Date.new(2028, 11, 9),
      reached_on: nil, projection_days: 200, priced?: true, costed?: true
    }
    Economics::Overview::Result.new(**defaults.merge(overrides))
  end

  test "shows cost, savings, covered share and the projected date" do
    rendered = render_inline(Economics::OverviewCardComponent.new(result: result))

    assert_equal "Wirtschaftlichkeit", rendered.css(".card-title").text.split(" seit ").first.strip
    assert_match "seit 14.02.2026", rendered.css(".card-subtitle").text
    values = rendered.css(".tile-value").map { |node| node.text.squish }
    assert_equal [ "1.000,00 €", "200,00 €", "20,0 %", "09.11.2028" ], values
    assert_equal "20", rendered.css("[data-economics-covered-pct]").first["data-economics-covered-pct"]
  end

  test "a reached payback names the day instead of a projection" do
    rendered = render_inline(Economics::OverviewCardComponent.new(
      result: result(saved_eur: 1200.0, covered_ratio: 1.0, reached_on: Date.new(2027, 5, 4),
                     projected_payback_date: nil)
    ))

    assert_match "Amortisiert", rendered.to_html
    assert_match "04.05.2027", rendered.css(".tile-value").last.text
  end

  test "too short a record says so instead of naming a date" do
    rendered = render_inline(Economics::OverviewCardComponent.new(
      result: result(projected_payback_date: nil, projection_days: 12)
    ))

    assert_match "Noch zu wenig Daten", rendered.css(".tile-value").last.text
    assert_match "Basis sind erst 12 Tage", rendered.to_html
  end

  test "without cost items it asks for them instead of showing a payback" do
    rendered = render_inline(Economics::OverviewCardComponent.new(
      result: result(acquisition_cost_eur: 0.0, costed?: false, covered_ratio: nil,
                     projected_payback_date: nil)
    ))

    assert_match "Kosten erfassen", rendered.to_html
    assert_empty rendered.css("[data-economics-covered-pct]")
  end

  test "without a price it says the savings are unknown" do
    rendered = render_inline(Economics::OverviewCardComponent.new(
      result: result(saved_eur: nil, covered_ratio: nil, priced?: false,
                     projected_payback_date: nil)
    ))

    assert_match "Strompreis", rendered.to_html
    assert_equal "—", rendered.css(".tile-value")[1].text.squish
  end

  test "without any data it names no start date" do
    rendered = render_inline(Economics::OverviewCardComponent.new(
      result: result(data_start: nil, saved_eur: 0.0, projected_payback_date: nil, projection_days: 0)
    ))

    assert_empty rendered.css(".card-subtitle")
  end
end
