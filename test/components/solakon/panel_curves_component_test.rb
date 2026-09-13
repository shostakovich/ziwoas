require "test_helper"

class Solakon::PanelCurvesComponentTest < ViewComponent::TestCase
  cover "Solakon::PanelCurvesComponent*"

  def curves(**overrides)
    defaults = {
      pv1: [ [ 12, 300.0 ], [ 13, 400.0 ], [ 14, 350.0 ] ],
      pv2: [ [ 12, 280.0 ], [ 13, 380.0 ], [ 14, 330.0 ] ],
      pv3: [ [ 12, 120.0 ], [ 13, 160.0 ], [ 14, 150.0 ] ],
      pv4: [ [ 12, 100.0 ], [ 13, 140.0 ], [ 14, 130.0 ] ]
    }.merge(overrides)

    defaults.map { |key, points| Shading::Curve.new(key: key, points: points) }
  end

  def render_panels(curves: curves(), days: 16, since: Date.new(2026, 8, 27))
    render_inline(Solakon::PanelCurvesComponent.new(panels: Shading::Panels.new(curves: curves, days: days, since: since)))
  end

  test "draws one line per panel and names it in the legend" do
    rendered = render_panels

    assert_equal %w[pv1 pv2 pv3 pv4], rendered.css("polyline").map { |node| node["class"].split.last }
    assert_equal [ "Panel 1", "Panel 2", "Panel 3", "Panel 4" ], rendered.css(".legend-item").map(&:text)
  end

  test "writes every panel's name next to its own line" do
    labels = render_panels.css(".direct-labels text")

    assert_equal [ "Panel 1", "Panel 2", "Panel 3", "Panel 4" ], labels.map(&:text).sort
    assert_equal 1, labels.map { |node| node["x"] }.uniq.length

    by_name = labels.to_h { |node| [ node.text, node["y"].to_f ] }
    assert_operator by_name.fetch("Panel 1"), :<, by_name.fetch("Panel 3")
  end

  test "lifts the names back over the axis when pushing them apart ran out of room" do
    flat = curves(pv1: [ [ 12, 5.0 ] ], pv2: [ [ 12, 4.0 ] ], pv3: [ [ 12, 3.0 ] ], pv4: [ [ 12, 2.0 ] ])
    rendered = render_panels(curves: flat)
    baseline = rendered.css("line.axis").sole["y1"].to_f

    rendered.css(".direct-labels text").each do |label|
      assert_operator label["y"].to_f, :<, baseline
    end
  end

  test "pushes two names apart where the lines run together" do
    together = curves(pv2: [ [ 12, 299.0 ], [ 13, 399.0 ], [ 14, 349.0 ] ])
    ys = render_panels(curves: together).css(".direct-labels text").map { |node| node["y"].to_f }.sort

    assert_operator ys[1] - ys[0], :>=, 20.0
  end

  test "says since when the days were counted" do
    assert_equal "Stundenmittel je Panel seit 27.08.2026 · 16 Tage", render_panels.css(".chart-title").sole.text.squish
  end

  test "counts a single day in the singular" do
    assert_includes render_panels(days: 1).css(".chart-title").sole.text, "1 Tag"
  end

  test "tells all four numbers of an hour" do
    title = render_panels.css(".hits rect title").first.text

    assert_equal "12–13 Uhr · Panel 1 Ø 300 W · Panel 2 Ø 280 W · Panel 3 Ø 120 W · Panel 4 Ø 100 W", title
  end

  test "names the hours with their unit on the wide axis and bare on the narrow one" do
    rendered = render_panels

    assert_equal [ "12 Uhr", "14 Uhr" ], rendered.css(".label-dense text").map(&:text)
    assert_equal [ "12" ], rendered.css(".label-sparse text").map(&:text)
  end

  test "breaks a line where an hour is missing" do
    gapped = curves(pv1: [ [ 8, 100.0 ], [ 9, 200.0 ], [ 14, 300.0 ] ])

    assert_equal 2, render_panels(curves: gapped).css("polyline.pv1").length
  end

  test "waits for the first full day with a word" do
    rendered = render_panels(curves: curves(pv1: [], pv2: [], pv3: [], pv4: []), days: 0, since: nil)

    assert_empty rendered.css("svg")
    assert_match(/Vergleich erscheint/, rendered.css(".note").sole.text)
  end

  test "spreads the watt grid over the plot instead of stacking it on the axis" do
    labels = render_panels.css(".value-labels text")

    assert_equal [ "100", "200", "300" ], labels.map(&:text)
    assert_equal labels.length, labels.map { |node| node["y"] }.uniq.length
    assert_operator labels.last["y"].to_f, :<, labels.first["y"].to_f
  end
end
