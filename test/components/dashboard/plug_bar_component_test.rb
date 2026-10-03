require "test_helper"
require_relative "live_test_support"

class Dashboard::PlugBarComponentTest < ViewComponent::TestCase
  include Dashboard::LiveTestSupport

  cover "Dashboard::PlugBarComponent*"

  def render_bar(plugs)
    render_inline(Dashboard::PlugBarComponent.new(live: live(plugs: plugs)))
  end

  def segments(rendered) = rendered.css("#dashboard_plug_bar .progress-stacked > .progress")

  def bar_color(segment) = segment.at_css(".progress-bar")["style"][/background-color: (var\(--viz-\d+\))/, 1]

  def total(rendered) = rendered.css("#dashboard_plug_bar strong").text

  def legend_items(rendered) = rendered.css("#dashboard_plug_bar ul[aria-label='Legende'] > li")

  def legend_name(item) = item.css("span")[1].text

  def legend_color(item) = item.at_css(".badge")["style"][/background-color: (var\(--[\w-]+\))/, 1]

  test "consumers stack by falling wattage with widths summing to 100 percent" do
    rendered = render_bar([
      row(id: "fridge", role: :consumer, apower_w: 80.0),
      row(id: "tv", role: :consumer, apower_w: 240.0)
    ])

    segs = segments(rendered)
    assert_equal 2, segs.length
    assert_match(/width: 75\.0%/, segs.first["style"])
    assert_match(/Tv · 240 W/, segs.first["title"])
    assert_equal "Tv", segs.first["aria-label"]
    assert_equal "75", segs.first["aria-valuenow"]
    assert_match(/width: 25\.0%/, segs.last["style"])
    assert_equal "320 W", total(rendered)
  end

  test "a plug keeps its color from config order even when another is offline" do
    with_all = render_bar([
      row(id: "fridge", role: :consumer, apower_w: 80.0),
      row(id: "tv", role: :consumer, apower_w: 240.0)
    ])
    fridge_color = bar_color(segments(with_all).find { |seg| seg["title"].include?("Fridge") })

    alone = render_bar([
      row(id: "fridge", role: :consumer, apower_w: 80.0),
      row(id: "tv", role: :consumer, online: false, apower_w: 0.0)
    ])
    alone_color = bar_color(segments(alone).first)

    assert_equal fridge_color, alone_color
  end

  test "offline and idle consumers stay out of bar and legend" do
    rendered = render_bar([
      row(id: "fridge", role: :consumer, apower_w: 80.0),
      row(id: "tv", role: :consumer, online: false, apower_w: 100.0),
      row(id: "lamp", role: :consumer, apower_w: 0.0)
    ])

    assert_equal 1, segments(rendered).length
    assert_equal [ "Fridge" ], legend_items(rendered).map { |item| legend_name(item) }
  end

  test "producers lead the legend with a negative magnitude in producer color" do
    rendered = render_bar([
      row(id: "fridge", role: :consumer, apower_w: 80.0),
      row(id: "bkw", role: :producer, name: "Solar", apower_w: -300.4)
    ])

    first = legend_items(rendered).first
    assert_equal "Solar", legend_name(first)
    assert_equal "-300 W", first.css("span")[2].text
    assert_equal "var(--viz-solar)", legend_color(first)
  end

  test "with nothing online the bar renders empty at 0 W" do
    rendered = render_bar([ row(id: "fridge", role: :consumer, online: false, apower_w: 80.0) ])

    assert rendered.css("#dashboard_plug_bar").any?
    assert segments(rendered).none?
    assert_equal "0 W", total(rendered)
  end

  test "color follows the consumer's roster position, not display order or producers" do
    rendered = render_bar([
      row(id: "bkw", role: :producer, apower_w: -300.0),
      row(id: "washer", role: :consumer, apower_w: 50.0),
      row(id: "fridge", role: :consumer, apower_w: 300.0)
    ])

    # fridge outranks washer in wattage and renders first in the bar, but
    # washer is the first *consumer* in roster order and must own color 0.
    fridge_seg = segments(rendered).find { |seg| seg["title"].include?("Fridge") }
    legend_washer = legend_items(rendered).find { |item| legend_name(item) == "Washer" }

    assert_equal "var(--viz-2)", bar_color(fridge_seg)
    assert_equal "var(--viz-1)", legend_color(legend_washer)
  end

  test "color wraps around the palette after ten consumers" do
    palette_size = Dashboard::PlugBarComponent::PLUG_COLORS.length
    plugs = (0..palette_size).map { |i| row(id: "p#{i}", role: :consumer, apower_w: 100.0 - i) }

    rendered = render_bar(plugs)

    first_color = bar_color(segments(rendered)[0])
    wrapped_color = bar_color(segments(rendered)[palette_size])

    assert_equal 10, palette_size
    assert_equal "var(--viz-10)", bar_color(segments(rendered)[palette_size - 1])
    assert_equal first_color, wrapped_color
  end

  test "consumers excludes an online producer even if it reports positive wattage" do
    rendered = render_bar([
      row(id: "bkw", role: :producer, apower_w: 50.0),
      row(id: "fridge", role: :consumer, apower_w: 80.0)
    ])

    assert_equal 1, segments(rendered).length
    assert_equal "80 W", total(rendered)
  end

  test "consumers excludes an online consumer with no wattage reading" do
    rendered = render_bar([ row(id: "fridge", role: :consumer, apower_w: nil) ])

    assert segments(rendered).none?
    assert_equal "0 W", total(rendered)
  end

  test "consumers includes a consumer drawing a fraction of a watt" do
    rendered = render_bar([ row(id: "fridge", role: :consumer, apower_w: 0.5) ])

    assert_equal 1, segments(rendered).length
  end

  test "consumers includes a consumer drawing exactly one watt" do
    rendered = render_bar([ row(id: "fridge", role: :consumer, apower_w: 1.0) ])

    assert_equal 1, segments(rendered).length
  end

  test "producers excludes an offline producer from the legend" do
    rendered = render_bar([
      row(id: "bkw", role: :producer, online: false, apower_w: -300.0),
      row(id: "fridge", role: :consumer, apower_w: 80.0)
    ])

    assert legend_items(rendered).none? { |item| legend_name(item) == "Bkw" }
  end
end
