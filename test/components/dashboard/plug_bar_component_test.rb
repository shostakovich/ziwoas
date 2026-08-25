require "test_helper"
require_relative "live_test_support"

class Dashboard::PlugBarComponentTest < ViewComponent::TestCase
  include Dashboard::LiveTestSupport

  cover "Dashboard::PlugBarComponent*"

  def render_bar(plugs)
    render_inline(Dashboard::PlugBarComponent.new(live: live(plugs: plugs)))
  end

  test "consumers stack by falling wattage with widths summing to 100 percent" do
    rendered = render_bar([
      row(id: "fridge", role: :consumer, apower_w: 80.0),
      row(id: "tv", role: :consumer, apower_w: 240.0)
    ])

    segs = rendered.css(".plug-bar .plug-seg")
    assert_equal 2, segs.length
    assert_match(/width: 75\.0%/, segs.first["style"])
    assert_match(/Tv · 240 W/, segs.first["title"])
    assert_match(/width: 25\.0%/, segs.last["style"])
    assert_equal "320 W", rendered.css(".plug-bar-meta b").text
  end

  test "a plug keeps its color from config order even when another is offline" do
    with_all = render_bar([
      row(id: "fridge", role: :consumer, apower_w: 80.0),
      row(id: "tv", role: :consumer, apower_w: 240.0)
    ])
    fridge_color = with_all.css(".plug-seg").find { |seg| seg["title"].include?("Fridge") }["style"][/background: (#\h{6})/, 1]

    alone = render_bar([
      row(id: "fridge", role: :consumer, apower_w: 80.0),
      row(id: "tv", role: :consumer, online: false, apower_w: 0.0)
    ])
    alone_color = alone.css(".plug-seg").first["style"][/background: (#\h{6})/, 1]

    assert_equal fridge_color, alone_color
  end

  test "offline and idle consumers stay out of bar and legend" do
    rendered = render_bar([
      row(id: "fridge", role: :consumer, apower_w: 80.0),
      row(id: "tv", role: :consumer, online: false, apower_w: 100.0),
      row(id: "lamp", role: :consumer, apower_w: 0.0)
    ])

    assert_equal 1, rendered.css(".plug-seg").length
    assert_equal [ "Fridge" ], rendered.css(".plug-legend .plug-name").map(&:text)
  end

  test "producers lead the legend with a negative magnitude in producer color" do
    rendered = render_bar([
      row(id: "fridge", role: :consumer, apower_w: 80.0),
      row(id: "bkw", role: :producer, name: "Solar", apower_w: -300.4)
    ])

    first = rendered.css(".plug-legend-item").first
    assert_equal "Solar", first.css(".plug-name").text
    assert_equal "-300 W", first.css(".plug-value").text
    assert_match(/#f59f00/, first.css(".plug-legend-swatch").first["style"])
  end

  test "with nothing online the bar renders empty at 0 W" do
    rendered = render_bar([ row(id: "fridge", role: :consumer, online: false, apower_w: 80.0) ])

    assert rendered.css("#dashboard_plug_bar").any?
    assert rendered.css(".plug-seg").none?
    assert_equal "0 W", rendered.css(".plug-bar-meta b").text
  end

  test "color follows the consumer's roster position, not display order or producers" do
    rendered = render_bar([
      row(id: "bkw", role: :producer, apower_w: -300.0),
      row(id: "washer", role: :consumer, apower_w: 50.0),
      row(id: "fridge", role: :consumer, apower_w: 300.0)
    ])

    # fridge outranks washer in wattage and renders first in the bar, but
    # washer is the first *consumer* in roster order and must own color 0.
    fridge_seg = rendered.css(".plug-seg").find { |seg| seg["title"].include?("Fridge") }
    legend_washer = rendered.css(".plug-legend-item").find { |el| el.css(".plug-name").text == "Washer" }

    assert_equal Dashboard::PlugBarComponent::PLUG_COLORS[1], fridge_seg["style"][/background: (#\h{6})/, 1]
    assert_equal Dashboard::PlugBarComponent::PLUG_COLORS[0],
      legend_washer.css(".plug-legend-swatch").first["style"][/background: (#\h{6})/, 1]
  end

  test "color wraps around the palette after ten consumers" do
    palette_size = Dashboard::PlugBarComponent::PLUG_COLORS.length
    plugs = (0..palette_size).map { |i| row(id: "p#{i}", role: :consumer, apower_w: 100.0 - i) }

    rendered = render_bar(plugs)

    first_color = rendered.css(".plug-seg")[0]["style"][/background: (#\h{6})/, 1]
    wrapped_color = rendered.css(".plug-seg")[palette_size]["style"][/background: (#\h{6})/, 1]

    assert_equal first_color, wrapped_color
  end

  test "consumers excludes an online producer even if it reports positive wattage" do
    rendered = render_bar([
      row(id: "bkw", role: :producer, apower_w: 50.0),
      row(id: "fridge", role: :consumer, apower_w: 80.0)
    ])

    assert_equal 1, rendered.css(".plug-seg").length
    assert_equal "80 W", rendered.css(".plug-bar-meta b").text
  end

  test "consumers excludes an online consumer with no wattage reading" do
    rendered = render_bar([ row(id: "fridge", role: :consumer, apower_w: nil) ])

    assert rendered.css(".plug-seg").none?
    assert_equal "0 W", rendered.css(".plug-bar-meta b").text
  end

  test "consumers includes a consumer drawing a fraction of a watt" do
    rendered = render_bar([ row(id: "fridge", role: :consumer, apower_w: 0.5) ])

    assert_equal 1, rendered.css(".plug-seg").length
  end

  test "consumers includes a consumer drawing exactly one watt" do
    rendered = render_bar([ row(id: "fridge", role: :consumer, apower_w: 1.0) ])

    assert_equal 1, rendered.css(".plug-seg").length
  end

  test "producers excludes an offline producer from the legend" do
    rendered = render_bar([
      row(id: "bkw", role: :producer, online: false, apower_w: -300.0),
      row(id: "fridge", role: :consumer, apower_w: 80.0)
    ])

    assert rendered.css(".plug-legend-item").none? { |el| el.css(".plug-name").text == "Bkw" }
  end
end
