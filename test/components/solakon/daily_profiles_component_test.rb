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
    assert_equal [ "Jun 20 Tage · W", "Sep 3 Tage · W" ], rendered.css("figcaption").map { |node| node.text.squish }
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

    assert_equal [ "300", "600" ], labels.map(&:text)
    assert_operator labels.last["y"].to_f, :<, labels.first["y"].to_f
  end

  test "tells every hour's three numbers" do
    title = render_profiles.css(".hits rect title").first.text

    assert_equal "Jun · 10–11 Uhr · PV gemessen Ø 300 W · Erwartet aus Einstrahlung Ø 350 W · " \
                 "Wolkenloser Himmel Ø 500 W", title
  end

  test "says so where the station measured nothing" do
    title = render_profiles([ profile(expected: []) ]).css(".hits rect title").first.text

    assert_includes title, "Erwartet aus Einstrahlung keine Daten"
  end

  test "measures the curves, the grid and the hits against the same axes" do
    rendered = render_profiles

    assert_equal "0 0 300 150", rendered.css("svg").sole["viewBox"]

    axis = rendered.css("line.axis").sole
    assert_equal %w[40 286 128 128], %w[x1 x2 y1 y2].map { |name| axis[name] }

    assert_equal [ [ "300", "36", "80.9" ], [ "600", "36", "30.4" ] ],
                 rendered.css(".value-labels text").map { |node| [ node.text, node["x"], node["y"] ] }

    assert_equal "40,128 40,77.4 163,60.6 286,43.7 286,128", rendered.css("polygon.measured-area").sole["points"]
    assert_equal "40,77.4 163,60.6 286,43.7", rendered.css("polyline.measured").sole["points"]
    assert_equal "40,43.7 163,26.9 286,10", rendered.css("polyline.theory").sole["points"]

    hit = rendered.css(".hits rect").first
    assert_equal %w[40 10 123 118], %w[x y width height].map { |name| hit[name] }
    assert_equal %w[286 0], %w[x width].map { |name| rendered.css(".hits rect").last[name] }

    hour = rendered.css(".hour-labels.label-dense text").sole
    assert_equal %w[10 40 144], [ hour.text, hour["x"], hour["y"] ]
  end

  test "names every third hour on the wide axis and every sixth on the narrow one" do
    wide = [ profile(measured: (6..18).map { |hour| [ hour, 100.0 * hour ] }, expected: [], theory: []) ]
    rendered = render_profiles(wide)

    assert_equal %w[6 9 12 15 18], rendered.css(".hour-labels.label-dense text").map(&:text)
    assert_equal %w[6 12 18], rendered.css(".hour-labels.label-sparse text").map(&:text)
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
    assert_equal %w[6 9 12], dense.map(&:text)
  end

  test "keeps an axis for a month whose curves are all empty" do
    rendered = render_profiles([ profile(measured: [], expected: [], theory: []) ])

    assert_equal %w[0], rendered.css(".hour-labels.label-dense text").map(&:text)
    assert_empty rendered.css("polyline")
    assert_empty rendered.css(".hits rect")
  end

  test "waits for the first month with a word" do
    rendered = render_profiles([])

    assert_empty rendered.css("svg")
    assert_match(/Tagesgang erscheint/, rendered.css(".note").sole.text)
  end
end
