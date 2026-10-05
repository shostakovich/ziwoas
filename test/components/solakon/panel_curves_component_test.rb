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

  def single(watts) = curves(pv1: [ [ 13, watts ] ], pv2: [], pv3: [], pv4: [])

  def render_panels(curves: curves(), days: 16, since: Date.new(2026, 8, 27))
    render_inline(Solakon::PanelCurvesComponent.new(panels: Shading::Panels.new(curves: curves, days: days, since: since)))
  end

  def wide(rendered = render_panels) = rendered.css("svg.panel-chart-wide").sole

  def narrow(rendered = render_panels) = rendered.css("svg.panel-chart-narrow").sole

  test "draws the day twice: wide from a small tablet up, narrow and taller on a phone" do
    rendered = render_panels

    assert_equal "0 0 720 220", wide(rendered)["viewBox"]
    assert_equal %w[d-none d-sm-block], wide(rendered)["class"].split.last(2)
    assert_equal "0 0 360 240", narrow(rendered)["viewBox"]
    assert_equal "d-sm-none", narrow(rendered)["class"].split.last
  end

  test "draws one line per panel in each drawing and names it once in the legend" do
    rendered = render_panels

    assert_equal %w[pv1 pv2 pv3 pv4], wide(rendered).css("polyline").map { |node| node["class"].split.last }
    assert_equal %w[pv1 pv2 pv3 pv4], narrow(rendered).css("polyline").map { |node| node["class"].split.last }
    assert_equal [ "Panel 1", "Panel 2", "Panel 3", "Panel 4" ], rendered.css(".legend-item").map(&:text)
    assert_equal %w[pv1 pv2 pv3 pv4], rendered.css(".legend-line").map { |node| node["class"].split.last }
  end

  test "writes every panel's name at the end of its own line in the wide drawing only" do
    rendered = render_panels
    labels = wide(rendered).css(".direct-labels text")

    assert_equal [ "Panel 1", "Panel 2", "Panel 3", "Panel 4" ], labels.map(&:text).sort
    assert_equal 1, labels.map { |node| node["x"] }.uniq.length
    by_name = labels.to_h { |node| [ node.text, node["y"].to_f ] }
    assert_operator by_name.fetch("Panel 1"), :<, by_name.fetch("Panel 3")

    assert_empty narrow(rendered).css(".direct-labels")
    assert_empty narrow(rendered).css(".leaders")
  end

  test "places no names in the narrow drawing, which leaves them to the legend" do
    panels = Shading::Panels.new(curves: curves, days: 16, since: Date.new(2026, 8, 27))
    wide_chart, narrow_chart = Solakon::PanelCurvesComponent.new(panels: panels).charts

    assert_equal 4, wide_chart.labels.length
    assert_equal [], narrow_chart.labels
  end

  test "joins a name to where its line ends, even when that is before the last hour" do
    early = curves(pv4: [ [ 12, 100.0 ], [ 13, 140.0 ] ])

    leader = wide(render_panels(curves: early)).css(".leaders line.pv4").sole

    assert_equal %w[336 129], %w[x1 y1].map { |name| leader[name] }
  end

  test "keeps the legend for the phone drawing only" do
    assert_includes render_panels.css("ul.legend").sole["class"].split, "d-sm-none"
  end

  test "lifts the names back over the axis when pushing them apart ran out of room" do
    flat = curves(pv1: [ [ 12, 5.0 ] ], pv2: [ [ 12, 4.0 ] ], pv3: [ [ 12, 3.0 ] ], pv4: [ [ 12, 2.0 ] ])
    chart = wide(render_panels(curves: flat))

    assert_equal %w[122 142 162 182], chart.css(".direct-labels text").map { |label| label["y"] }
  end

  test "lifts a name by exactly the amount that pushed it past the axis" do
    label = wide(render_panels(curves: single(0.0))).css(".direct-labels text").sole

    assert_equal "182", label["y"]
  end

  test "lifts a name that pushed past the axis by less than a unit" do
    label = wide(render_panels(curves: single(1.3))).css(".direct-labels text").sole

    assert_equal "182", label["y"]
  end

  test "leaves a name in place when it clears the axis" do
    label = wide(render_panels(curves: single(1.4))).css(".direct-labels text").sole

    assert_equal "181.9", label["y"]
  end

  test "sorts the placed names by height before spreading them, skipping any panel with no reading" do
    scattered = curves(pv1: [ [ 13, 50.0 ] ], pv2: [ [ 13, 750.0 ] ], pv3: [ [ 13, 400.0 ] ], pv4: [])

    assert_equal %w[pv2 pv3 pv1], wide(render_panels(curves: scattered)).css(".direct-labels text").map { |node| node["class"] }
  end

  test "pushes two names apart where the lines run together" do
    together = curves(pv2: [ [ 12, 299.0 ], [ 13, 399.0 ], [ 14, 349.0 ] ])
    ys = wide(render_panels(curves: together)).css(".direct-labels text").map { |node| node["y"].to_f }.sort

    assert_operator ys[1] - ys[0], :>=, 20.0
  end

  test "says since when the days were counted" do
    rendered = render_panels
    assert_equal "Die vier Panels im Tagesverlauf", rendered.css(".card-title").sole.text.squish
    assert_equal "seit 27.08.2026 · 16 Tage", rendered.css(".card-subtitle").sole.text.squish
  end

  test "counts a single day in the singular and every other count in the plural" do
    assert_equal "seit 27.08.2026 · 1 Tag", render_panels(days: 1).css(".card-subtitle").sole.text.squish
    assert_equal "seit 27.08.2026 · 2 Tage", render_panels(days: 2).css(".card-subtitle").sole.text.squish
  end

  test "explains why a day can go uncounted" do
    assert_equal "Gezählt sind nur Tage, an denen alle vier Panels geliefert haben — ein Panel, das noch nicht " \
                 "angeschlossen war, meldet null Watt und würde seine eigene Linie nach unten ziehen.",
                 render_panels.css(".note").sole.text
  end

  test "tells all four numbers of an hour" do
    title = wide.css(".hits rect title").first.text

    assert_equal "12–13 Uhr · Panel 1 Ø 300 W · Panel 2 Ø 280 W · Panel 3 Ø 120 W · Panel 4 Ø 100 W", title
  end

  test "says so where a panel has no reading for an hour the others do" do
    gapped = curves(pv1: [ [ 8, 100.0 ], [ 9, 200.0 ], [ 14, 300.0 ] ])

    title = wide(render_panels(curves: gapped)).css(".hits rect title").first.text

    assert_equal "8–9 Uhr · Panel 1 Ø 100 W · Panel 2 keine Daten · Panel 3 keine Daten · Panel 4 keine Daten", title
  end

  test "names the hours as clock times on the wide drawing and bare, further apart, on the narrow one" do
    scattered = curves(pv1: [ [ 6, 300.0 ], [ 18, 310.0 ] ])
    rendered = render_panels(curves: scattered)

    assert_equal %w[06:00 08:00 10:00 12:00 14:00 16:00 18:00], wide(rendered).css(".hour-labels text").map(&:text)
    assert_equal %w[06 09 12 15 18], narrow(rendered).css(".hour-labels text").map(&:text)
  end

  test "puts the hour labels on the clock's step, not on the first hour measured" do
    scattered = curves(pv1: [ [ 5, 300.0 ], [ 19, 310.0 ] ])
    rendered = render_panels(curves: scattered)

    assert_equal %w[06:00 08:00 10:00 12:00 14:00 16:00 18:00], wide(rendered).css(".hour-labels text").map(&:text)
    assert_equal %w[06 09 12 15 18], narrow(rendered).css(".hour-labels text").map(&:text)
  end

  test "breaks a line where an hour is missing" do
    gapped = curves(pv1: [ [ 8, 100.0 ], [ 9, 200.0 ], [ 14, 300.0 ] ])

    assert_equal 2, wide(render_panels(curves: gapped)).css("polyline.pv1").length
  end

  test "spans the shared axis from the earliest to the latest hour across every panel" do
    scattered = curves(pv1: [ [ 16, 300.0 ], [ 17, 310.0 ] ], pv2: [ [ 8, 100.0 ], [ 9, 110.0 ] ],
                       pv3: [ [ 12, 50.0 ] ], pv4: [ [ 12, 40.0 ] ])

    rendered = render_panels(curves: scattered)

    assert_equal %w[08:00 10:00 12:00 14:00 16:00], wide(rendered).css(".hour-labels text").map(&:text)
  end

  test "waits for the first full day with a word" do
    rendered = render_panels(curves: curves(pv1: [], pv2: [], pv3: [], pv4: []), days: 0, since: nil)

    assert_empty rendered.css("svg")
    assert_match(/Vergleich erscheint/, rendered.css(".note").sole.text)
  end

  test "measures the lines, the grid, the names and the hits against the same axes" do
    chart = wide

    axis = chart.css("line.axis").sole
    assert_equal %w[40 632 192 192], %w[x1 x2 y1 y2].map { |name| axis[name] }

    assert_equal [ [ "0", "35", "192" ], [ "100", "35", "147" ], [ "200", "35", "102" ], [ "300", "35", "57" ],
                   [ "400", "35", "12" ], [ "W", "38", "12" ] ],
                 chart.css(".value-labels text").map { |node| [ node.text, node["x"], node["y"] ] }

    assert_equal "40,57 336,12 632,34.5", chart.css("polyline.pv1").sole["points"]
    assert_equal "40,147 336,129 632,133.5", chart.css("polyline.pv4").sole["points"]

    names = chart.css(".direct-labels text")
    assert_equal %w[644 644 644 644], names.map { |node| node["x"] }
    assert_equal %w[34.5 54.5 124.5 144.5], names.map { |node| node["y"] }

    # Each leader runs from the end of its line to just before its name.
    leaders = chart.css(".leaders line").map { |node| [ node["class"], *%w[x1 y1 x2 y2].map { |name| node[name] } ] }
    assert_equal [ [ "pv1", "632", "34.5", "641", "34.5" ], [ "pv2", "632", "43.5", "641", "54.5" ],
                   [ "pv3", "632", "124.5", "641", "124.5" ], [ "pv4", "632", "133.5", "641", "144.5" ] ], leaders

    hit = chart.css(".hits rect").first
    assert_equal %w[40 12 296 180], %w[x y width height].map { |name| hit[name] }
    assert_equal %w[632 0], %w[x width].map { |name| chart.css(".hits rect").last[name] }

    assert_equal %w[40 632], chart.css(".hour-labels text").map { |node| node["x"] }
    assert_equal %w[197 197], chart.css(".hour-labels text").map { |node| node["y"] }
  end

  test "measures the narrow drawing against its own, taller frame" do
    chart = narrow

    assert_equal %w[36 348 216 216], %w[x1 x2 y1 y2].map { |name| chart.css("line.axis").sole[name] }
    assert_equal [ [ "0", "31", "216" ], [ "100", "31", "165" ], [ "200", "31", "114" ], [ "300", "31", "63" ],
                   [ "400", "31", "12" ], [ "W", "34", "12" ] ],
                 chart.css(".value-labels text").map { |node| [ node.text, node["x"], node["y"] ] }
    assert_equal "36,63 192,12 348,37.5", chart.css("polyline.pv1").sole["points"]
    assert_equal [ [ "12", "36", "221" ] ], chart.css(".hour-labels text").map { |node| [ node.text, node["x"], node["y"] ] }
  end

  test "draws a grid line at each labeled height above zero, spanning the full width" do
    lines = wide.css(".grid line")

    assert_equal %w[147 102 57 12], lines.map { |line| line["y1"] }, "the axis stands for zero"
    assert_equal lines.map { |line| line["y1"] }, lines.map { |line| line["y2"] }
    assert_equal %w[40 40 40 40], lines.map { |line| line["x1"] }
    assert_equal %w[632 632 632 632], lines.map { |line| line["x2"] }
  end

  test "steps the grid in round watts that leave the curves filling the plot" do
    {
      110.0 => %w[0 25 50 75 100 125],
      125.5 => %w[0 50 100 150],
      250.0 => %w[0 50 100 150 200 250],
      410.0 => %w[0 100 200 300 400 500],
      700.5 => %w[0 200 400 600 800],
      1250.0 => %w[0 250 500 750 1000 1250],
      2500.0 => %w[0 500 1000 1500 2000 2500]
    }.each do |peak, expected|
      labels = wide(render_panels(curves: single(peak))).css(".value-labels text").map(&:text)

      assert_equal expected + [ "W" ], labels, "peak #{peak} W"
    end
  end

  test "tops the axis at the peak rounded up to the step, where the unit follows the top value" do
    chart = wide(render_panels(curves: single(110.0)))

    # 110 W of 125 W: the line ends 22.4 units under the top of the plot.
    assert_equal "40,33.6", chart.css("polyline.pv1").sole["points"]
    top = chart.css(".value-labels text:not(.unit)").last
    unit = chart.css(".value-labels text.unit").sole
    assert_equal [ "125", "12" ], [ top.text, top["y"] ]
    assert_equal [ "38", "12" ], [ unit["x"], unit["y"] ]
    assert_nil unit["text-anchor"], "the unit reads on from the number, rightwards"
  end

  test "rounds a peak beyond the round steps to whole five hundreds" do
    labels = wide(render_panels(curves: single(3000.0))).css(".value-labels text").map(&:text)

    assert_equal %w[0 1000 2000 3000 W], labels
  end

  test "keeps one step of axis even when every panel reported nothing" do
    zero = curves(pv1: [ [ 12, 0.0 ] ], pv2: [ [ 12, 0.0 ] ], pv3: [ [ 12, 0.0 ] ], pv4: [ [ 12, 0.0 ] ])

    chart = wide(render_panels(curves: zero))

    assert_equal %w[0 25 W], chart.css(".value-labels text").map(&:text)
    assert_equal "40,192", chart.css("polyline.pv1").sole["points"]
  end

  test "says nothing about a period before the first counted day" do
    rendered = render_panels(curves: curves(pv1: [ [ 12, 5.0 ] ]), days: 0, since: nil)

    assert_equal "Die vier Panels im Tagesverlauf", rendered.css(".card-title").sole.text.squish
    assert_empty rendered.css(".card-subtitle")
  end
end
