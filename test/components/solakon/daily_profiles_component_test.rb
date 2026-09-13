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

  test "fills the measured curve down to the baseline" do
    points = render_profiles.css("polygon.measured-area").sole["points"].split

    assert_equal points.first.split(",").last, points.last.split(",").last
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

  test "keeps the hits inside the drawing" do
    rendered = render_profiles
    right = rendered.css("line.axis").first["x2"].to_f
    hit = rendered.css(".hits rect").last

    assert_operator hit["x"].to_f + hit["width"].to_f, :<=, right
  end

  test "waits for the first month with a word" do
    rendered = render_profiles([])

    assert_empty rendered.css("svg")
    assert_match(/Tagesgang erscheint/, rendered.css(".note").sole.text)
  end
end
