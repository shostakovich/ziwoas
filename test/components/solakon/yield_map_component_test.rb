require "test_helper"

class Solakon::YieldMapComponentTest < ViewComponent::TestCase
  cover "Solakon::YieldMapComponent*"

  def bin(azimuth: 140, elevation: 45, share: 0.8, hours: 12, first_hour: 11, last_hour: 13)
    Shading::Bin.new(azimuth: azimuth, elevation: elevation, share: share,
                     hours: hours, first_hour: first_hour, last_hour: last_hour)
  end

  def path(label: "21.6.", points: [ [ 60.0, 5.0 ], [ 180.0, 60.0 ], [ 300.0, 4.0 ] ], dots: [])
    Shading::Path.new(label: label, points: points, dots: dots)
  end

  def render_map(bins: [ bin ], paths: [ path ], bin_size: 5)
    render_inline(Solakon::YieldMapComponent.new(map: Shading::Map.new(bins: bins, paths: paths, bin_size: bin_size)))
  end

  test "draws one field per measured piece of sky" do
    rendered = render_map(bins: [ bin, bin(azimuth: 200, elevation: 30) ])

    assert_equal 2, rendered.css(".fields rect").length
  end

  test "colours a field from the diverging ramp and clamps above the best hour" do
    full = render_map(bins: [ bin(share: 1.4) ]).css(".fields rect").sole

    assert_equal Ramp.fetch(:diverging).color(1.0), full["fill"]
    assert_equal Ramp.fetch(:diverging).color(0.8), render_map.css(".fields rect").sole["fill"]
  end

  test "says what a field holds" do
    title = render_map.css(".fields rect title").sole.text

    assert_equal "Azimut 140–145° · Höhe 45–50° · Ausbeute 80 % · 12 Stunden · 11–13 Uhr", title
  end

  test "names the compass points on both densities and the degrees only on the wide one" do
    rendered = render_map

    dense = rendered.css(".label-dense text").map(&:text)
    sparse = rendered.css(".label-sparse text").map(&:text)

    assert_includes dense, "Ost 90°"
    assert_includes dense, "120°"
    assert_equal [ "Ost", "Süd", "West" ], sparse
  end

  test "labels the sun's height up the side" do
    heights = render_map.css(".hour-labels text").map(&:text)

    assert_equal "0°", heights.first
    assert_includes heights, "60°"
  end

  test "draws every path once and writes its date over the highest point" do
    rendered = render_map(paths: [ path, path(label: "21.12.", points: [ [ 130.0, 1.0 ], [ 180.0, 14.0 ] ]) ])

    assert_equal 2, rendered.css("polyline.sun").length

    labels = rendered.css("text.path-label").to_h { |node| [ node.text, node["x"].to_f ] }
    assert_equal [ "21.6.", "21.12." ], labels.keys
    # Both sit over the arc's apex at 180°, which is the same x on both paths.
    assert_equal labels.fetch("21.6."), labels.fetch("21.12.")
  end

  test "writes the hour under its dot, where the date cannot reach it" do
    dots = [ Shading::Dot.new(hour: 12, azimuth: 180.0, elevation: 60.0) ]
    rendered = render_map(paths: [ path(dots: dots) ])

    dot = rendered.css("circle.dot").sole
    hour = rendered.css("text.dot-label").sole
    date = rendered.css("text.path-label").sole

    assert_operator hour["y"].to_f, :>, dot["cy"].to_f
    assert_operator date["y"].to_f, :<, dot["cy"].to_f
  end

  test "marks the hours on the first path only" do
    dots = [ Shading::Dot.new(hour: 9, azimuth: 120.0, elevation: 30.0) ]
    rendered = render_map(paths: [ path(dots: dots), path(label: "21.12.", dots: dots) ])

    assert_equal 2, rendered.css("circle.dot").length
    assert_equal [ "9" ], rendered.css("text.dot-label").map(&:text)
  end

  test "keeps the fields and the paths inside the drawing" do
    rendered = render_map
    width, height = rendered.css("svg").sole["viewBox"].split.last(2).map(&:to_f)
    xs = rendered.css(".fields rect, polyline.sun").map { |node| node["x"] || node["points"] }

    assert_equal 720.0, width
    assert_operator height, :>, 200
    assert xs.all?(&:present?)
    axis = rendered.css(".hour-labels text").first["x"].to_f
    assert_operator rendered.css(".fields rect").sole["x"].to_f, :>, axis
  end

  test "waits for the first fields with a word instead of an empty sky" do
    rendered = render_map(bins: [])

    assert_empty rendered.css("svg")
    assert_match(/füllt sich/, rendered.css(".note").sole.text)
  end
end
