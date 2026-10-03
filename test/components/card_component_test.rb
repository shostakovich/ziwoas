require "test_helper"

class CardComponentTest < ViewComponent::TestCase
  cover "CardComponent*"

  def render_card(**options, &block)
    render_inline(CardComponent.new(**options), &(block || proc { "Inhalt" }))
  end

  test "writes the heading into the box, over what the box holds" do
    rendered = render_card(title: "Solakon-Verlauf")

    body = rendered.css("section.card > .card-body").sole
    assert_equal "Solakon-Verlauf", body.css("h2.card-title").sole.text.squish
    assert_equal %w[h2], body.element_children.map(&:name).first(1)
    assert_includes body.text, "Inhalt"
  end

  test "puts the subtitle under the heading" do
    body = render_card(title: "Leistung", subtitle: "Letzte 24 h").css(".card-body").sole

    assert_equal "Leistung", body.css(".card-title").sole.text
    assert_equal "Letzte 24 h", body.css(".card-title + .card-subtitle").sole.text
  end

  test "leaves the heading out where the box speaks for itself" do
    rendered = render_card(subtitle: "ohne Titel")

    assert_empty rendered.css(".card-title, .card-subtitle")
    assert_includes rendered.css(".card").sole.text, "Inhalt"
  end

  test "keeps the classes and attributes the page needs on the box" do
    rendered = render_card(title: "Energiefluss", classes: "energy-flow-card",
                           data: { controller: "energy-flow" }, aria: { label: "Fluss" })

    card = rendered.css(".card").sole
    assert_equal "card mb-3 energy-flow-card", card["class"]
    assert_equal "energy-flow", card["data-controller"]
    assert_equal "Fluss", card["aria-label"]
  end

  test "is a plain card where the page adds no classes" do
    assert_equal "card mb-3", render_card(title: "Ertrag").css(".card").sole["class"]
  end

  test "takes another element where the page needs one" do
    assert_equal 1, render_card(title: "Ertrag", as: :div).css("div.card").length
  end

  test "sits a level deeper where the box belongs to a labelled group" do
    rendered = render_card(title: "PV-Leistung", level: 3)

    assert_equal "PV-Leistung", rendered.css("h3.card-title").sole.text.squish
    assert_empty rendered.css("h2")
  end
end
