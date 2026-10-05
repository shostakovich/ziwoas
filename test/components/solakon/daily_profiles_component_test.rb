require "test_helper"

class Solakon::DailyProfilesComponentTest < ViewComponent::TestCase
  cover "Solakon::DailyProfilesComponent*"

  def curve(key, points) = Shading::Curve.new(key: key, points: points)

  def profile(month: 6, days: 20, measured: [ [ 10, 300.0 ], [ 11, 400.0 ], [ 12, 500.0 ] ],
              expected: [ [ 10, 350.0 ], [ 11, 450.0 ], [ 12, 600.0 ] ],
              theory: [ [ 10, 500.0 ], [ 11, 600.0 ], [ 12, 700.0 ] ])
    Shading::Profile.new(month: month, days: days,
                         curves: [ curve(:measured, measured), curve(:expected, expected), curve(:theory, theory) ])
  end

  def render_profiles(profiles = [ profile ])
    render_inline(Solakon::DailyProfilesComponent.new(profiles: profiles))
  end

  test "gives every month its own picture, named and counted" do
    rendered = render_profiles([ profile(month: 6), profile(month: 9, days: 3) ])

    assert_equal %w[6 9], rendered.css(".multiple").map { |node| node["data-month"] }
    assert_equal [ "Jun 20 Tage", "Sep 3 Tage" ], rendered.css("figcaption").map { |node| node.text.squish }
    assert_equal "Mittlere Leistung je Stunde in W", rendered.css(".card-subtitle").sole.text.squish
  end

  test "counts a single day in the singular" do
    assert_equal "Jun 1 Tag", render_profiles([ profile(days: 1) ]).css("figcaption").sole.text.squish
  end

  test "draws a month that is not yet whole quieter than the others" do
    rendered = render_profiles([ profile(month: 6, days: 30), profile(month: 7, days: 30), profile(month: 2, days: 28) ])

    partial = rendered.css(".multiple.partial").map { |node| node["data-month"] }
    assert_equal %w[7], partial
    assert_includes rendered.css(".multiple[data-month='7'] svg").sole["class"].split, "opacity-50"
    assert_nil rendered.css(".multiple[data-month='6'] svg").sole["class"]
    assert_includes rendered.css(".multiple[data-month='7'] figcaption").sole["class"].split, "text-body-secondary"
  end

  test "puts the legend under the title, ahead of the months" do
    rendered = render_profiles

    assert_equal [ "PV gemessen", "Erwartet aus Einstrahlung", "Wolkenloser Himmel" ], rendered.css(".legend-item").map(&:text)
    assert_operator rendered.to_html.index("legend-item"), :<, rendered.to_html.index("multiple")
  end

  test "draws the three curves, the measured one over the two it is read against" do
    keys = render_profiles.css("polyline").map { |node| node["class"] }

    assert_equal [ "curve theory", "curve expected", "curve measured" ], keys
  end

  test "breaks a curve where an hour is missing" do
    rendered = render_profiles([ profile(measured: [ [ 8, 100.0 ], [ 9, 200.0 ], [ 14, 300.0 ] ]) ])

    assert_equal 2, rendered.css("polyline.measured").length
  end

  test "fills only the measured curve, and breaks the fill where the curve breaks" do
    rendered = render_profiles([ profile(measured: [ [ 8, 100.0 ], [ 9, 200.0 ], [ 14, 300.0 ] ]) ])

    assert_equal 2, rendered.css("polygon.measured-area").length
    assert_equal 1, rendered.css("polygon").map { |node| node["class"] }.uniq.length
  end

  test "puts every month on the same scale" do
    rendered = render_profiles([ profile(month: 6), profile(month: 12, measured: [ [ 12, 50.0 ] ], expected: [], theory: [ [ 12, 90.0 ] ]) ])

    december = rendered.css(".multiple[data-month='12'] polyline.measured").sole["points"]
    june = rendered.css(".multiple[data-month='6'] polyline.measured").sole["points"]

    assert_operator december.split(",").last.to_f, :>, june.split(",").last.to_f
  end

  test "labels the watt grid under the highest curve, each line at its own height" do
    labels = render_profiles.css(".multiple").first.css(".value-labels text")

    assert_equal %w[0 250 500 750], labels.map(&:text)
    assert_operator labels.last["y"].to_f, :<, labels.first["y"].to_f
  end

  test "stands the zero on the axis, clear of the first hour below" do
    labels = render_profiles.css(".multiple").first.css(".value-labels text")

    assert_equal [ "0", %w[zero] ], [ labels.first.text, labels.first["class"].split ]
    assert_equal [ nil ], labels.drop(1).map { |label| label["class"] }.uniq
  end

  test "tops the plot with the last step when the maximum lands exactly on it" do
    rendered = render_profiles([ profile(measured: [ [ 10, 300.0 ] ], expected: [ [ 10, 100.0 ] ], theory: [ [ 10, 50.0 ] ]) ])

    assert_equal %w[0 100 200 300], rendered.css(".value-labels text").map(&:text)
    assert_equal "10", rendered.css(".value-labels text").last["y"], "no headroom above the top value"
  end

  test "steps the grid in round watts that reach the peak in three steps at most" do
    {
      90.0 => %w[0 100],
      300.5 => %w[0 200 400],
      301.0 => %w[0 200 400],
      620.0 => %w[0 250 500 750],
      1400.0 => %w[0 500 1000 1500],
      2400.0 => %w[0 1000 2000 3000],
      3100.0 => %w[0 2000 4000]
    }.each do |peak, expected|
      rendered = render_profiles([ profile(measured: [ [ 10, peak ] ], expected: [], theory: []) ])

      assert_equal expected, rendered.css(".value-labels text").map(&:text), "peak #{peak} W"
    end
  end

  test "draws a grid line at each labeled height, spanning the full width" do
    lines = render_profiles.css(".grid line")

    assert_equal %w[90 50 10], lines.map { |line| line["y1"] }, "the axis stands for zero"
    assert_equal lines.map { |line| line["y1"] }, lines.map { |line| line["y2"] }
    assert_equal %w[48 48 48], lines.map { |line| line["x1"] }
    assert_equal %w[286 286 286], lines.map { |line| line["x2"] }
  end

  test "tells every hour's three numbers" do
    title = render_profiles.css(".hits rect title").first.text

    assert_equal "Jun · 10–11 Uhr · PV gemessen Ø 300 W · Erwartet aus Einstrahlung Ø 350 W · " \
                 "Wolkenloser Himmel Ø 500 W", title
  end

  test "tells every distinct hour once, in ascending order, even when a curve's hours run out of step" do
    rendered = render_profiles([ profile(
      measured: [ [ 10, 300.0 ], [ 11, 400.0 ] ],
      expected: [ [ 10, 350.0 ], [ 11, 450.0 ] ],
      theory: [ [ 8, 200.0 ], [ 9, 250.0 ], [ 10, 500.0 ], [ 11, 600.0 ] ]
    ) ])

    titles = rendered.css(".hits rect title").map(&:text)

    assert_equal 4, titles.length
    assert_equal [ 8, 9, 10, 11 ], titles.map { |title| title[/(\d+)–\d+ Uhr/, 1].to_i }
  end

  test "takes the largest of every month's maximum, not the first or the last, and never truncates picking it" do
    low   = profile(month: 1, measured: [ [ 6, 350.7 ] ], expected: [], theory: [])
    empty = profile(month: 2, measured: [], expected: [], theory: [])
    high  = profile(month: 3, measured: [ [ 6, 700.5 ] ], expected: [], theory: [])
    mid   = profile(month: 4, measured: [ [ 6, 210.5 ] ], expected: [], theory: [])

    rendered = render_profiles([ low, empty, high, mid ])

    labels = rendered.css(".multiple").first.css(".value-labels text")
    assert_equal %w[0 250 500 750], labels.map(&:text)
    assert_equal %w[130 90 50 10], labels.map { |label| label["y"] }
  end

  test "keeps one step of axis when every month produced nothing" do
    rendered = render_profiles([ profile(measured: [ [ 10, 0.0 ] ], expected: [], theory: []) ])

    assert_equal %w[0 100], rendered.css(".value-labels text").map(&:text)
  end

  test "says so where the station measured nothing" do
    title = render_profiles([ profile(expected: []) ]).css(".hits rect title").first.text

    assert_includes title, "Erwartet aus Einstrahlung keine Daten"
  end

  test "measures the curves, the grid and the hits against the same axes" do
    rendered = render_profiles

    assert_equal "0 0 300 160", rendered.css("svg").sole["viewBox"]

    axis = rendered.css("line.axis").sole
    assert_equal %w[48 286 130 130], %w[x1 x2 y1 y2].map { |name| axis[name] }

    assert_equal [ %w[0 44 130], %w[250 44 90], %w[500 44 50], %w[750 44 10] ],
                 rendered.css(".value-labels text").map { |node| [ node.text, node["x"], node["y"] ] }

    assert_equal "48,130 48,82 167,66 286,50 286,130", rendered.css("polygon.measured-area").sole["points"]
    assert_equal "48,82 167,66 286,50", rendered.css("polyline.measured").sole["points"]
    assert_equal "48,50 167,34 286,18", rendered.css("polyline.theory").sole["points"]

    hit = rendered.css(".hits rect").first
    assert_equal %w[48 10 119 120], %w[x y width height].map { |name| hit[name] }
    assert_equal %w[286 0], %w[x width].map { |name| rendered.css(".hits rect").last[name] }

    hour = rendered.css(".hour-labels.label-dense text").sole
    assert_equal %w[12 286 138], [ hour.text, hour["x"], hour["y"] ]
  end

  test "names every third hour on the wide axis and every sixth on the narrow one" do
    wide = [ profile(measured: (6..18).map { |hour| [ hour, 100.0 * hour ] }, expected: [], theory: []) ]
    rendered = render_profiles(wide)

    assert_equal %w[06 09 12 15 18], rendered.css(".hour-labels.label-dense text").map(&:text)
    assert_equal %w[06 12 18], rendered.css(".hour-labels.label-sparse text").map(&:text)
  end

  test "explains what the distance between the lines means" do
    assert_equal "Einstrahlung und wolkenloser Himmel sind mit dem Wirkungsgrad der besten Stunde auf " \
                 "Anlagenleistung umgerechnet. Der Abstand zwischen der gemessenen und der erwarteten Linie " \
                 "ist der Anteil, den Abschattung, Ausrichtung oder Drosselung kosten.",
                 render_profiles.css(".note").sole.text
  end

  test "spans the shared axis from the earliest to the latest hour of any month" do
    early = profile(month: 3, measured: [ [ 6, 100.0 ], [ 7, 200.0 ] ], expected: [], theory: [])
    rendered = render_profiles([ profile, early ])

    dense = rendered.css(".multiple[data-month='6'] .hour-labels.label-dense text")

    # June has no hour six of its own; the axis it is drawn on starts there
    # because March does.
    assert_equal %w[06 09 12], dense.map(&:text)
  end

  test "keeps an axis for a month whose curves are all empty" do
    rendered = render_profiles([ profile(measured: [], expected: [], theory: []) ])

    assert_equal %w[00], rendered.css(".hour-labels.label-dense text").map(&:text)
    assert_empty rendered.css("polyline")
    assert_empty rendered.css(".hits rect")
  end

  test "waits for the first month with a word" do
    rendered = render_profiles([])

    assert_empty rendered.css("svg")
    assert_match(/Tagesgang erscheint/, rendered.css(".note").sole.text)
  end
end
