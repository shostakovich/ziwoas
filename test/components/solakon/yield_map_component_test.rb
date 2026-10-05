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

  def wide(rendered) = rendered.css("svg.yield-map-wide").sole

  def narrow(rendered) = rendered.css("svg.yield-map-narrow").sole

  def sky(frame = :wide, bins: [ bin ], paths: [ path ])
    Solakon::YieldMapComponent::Sky.new(frame: Solakon::YieldMapComponent::FRAMES.find { |candidate| candidate.key == frame },
                                        map: Shading::Map.new(bins: bins, paths: paths, bin_size: 5))
  end

  test "draws one field per measured piece of sky" do
    rendered = render_map(bins: [ bin, bin(azimuth: 200, elevation: 30) ])

    assert_equal 2, wide(rendered).css(".fields rect").length
  end

  test "colours a field from the diverging ramp and clamps above the best hour" do
    full = wide(render_map(bins: [ bin(share: 1.4) ])).css(".fields rect").sole

    assert_equal "fill: #{Ramp.fetch(:diverging).color(1.0)}", full["style"]
    assert_equal "fill: #{Ramp.fetch(:diverging).color(0.8)}", wide(render_map).css(".fields rect").sole["style"]
  end

  test "says what a field holds" do
    title = wide(render_map).css(".fields rect title").sole.text

    assert_equal "Azimut 140–145° · Höhe 45–50° · Ausbeute 80 % · 12 Stunden · 11–13 Uhr", title
  end

  test "names the compass points on both densities and the degrees only on the wide one" do
    rendered = render_map

    dense = wide(rendered).css(".month-labels.label-dense text").map(&:text)
    sparse = narrow(rendered).css(".month-labels.label-sparse text").map(&:text)

    assert_includes dense, "Ost 90°"
    assert_includes dense, "120°"
    assert_equal [ "Ost", "Süd", "West" ], sparse
  end

  test "labels the sun's height up the side" do
    heights = wide(render_map).css(".hour-labels.label-dense text").map(&:text)

    assert_equal "0°", heights.first
    assert_includes heights, "60°"
  end

  test "steps the elevation grid by ten degrees, not by one" do
    rendered = render_map

    assert_equal 7, wide(rendered).css(".hour-labels.label-dense text").length
    assert_equal 7, wide(rendered).css("g.grid").first.css("line").length
  end

  test "labels every other elevation line on the phone" do
    assert_equal %w[0° 20° 40° 60°], narrow(render_map).css(".hour-labels.label-sparse text").map(&:text)
  end

  test "extends both axes to cover the widest field, not just the sun's own path" do
    wide = path(points: [ [ 100.0, 10.0 ], [ 150.0, 30.0 ], [ 200.0, 10.0 ] ])
    wide_bin = bin(azimuth: 20, elevation: 10)

    rendered = render_map(bins: [ wide_bin ], paths: [ wide ], bin_size: 250)

    field = wide(rendered).css(".fields rect").sole
    assert_equal %w[52 16 657.4 953.5], %w[x y width height].map { |name| field[name] }
  end

  test "rounds the azimuth labels' height to one decimal, even on a wide sky" do
    wide = path(points: [ [ 100.0, 10.0 ], [ 150.0, 30.0 ], [ 200.0, 10.0 ] ])
    wide_bin = bin(azimuth: 20, elevation: 10)

    rendered = render_map(bins: [ wide_bin ], paths: [ wide ], bin_size: 250)

    assert_equal "1013.3", wide(rendered).css(".month-labels text").first["y"]
  end

  test "rounds each elevation gridline's height and label height to one decimal, even on a wide sky" do
    wide = path(points: [ [ 100.0, 10.0 ], [ 150.0, 30.0 ], [ 200.0, 10.0 ] ])
    wide_bin = bin(azimuth: 20, elevation: 10)

    rendered = render_map(bins: [ wide_bin ], paths: [ wide ], bin_size: 250)

    line = wide(rendered).css("g.grid line").select { |node| node["y1"] == node["y2"] }[4]
    label = wide(rendered).css(".hour-labels.label-dense text")[4]

    assert_equal "855.6", line["y1"]
    assert_equal "855.6", label["y"]
  end

  test "leaves out a path with no points instead of drawing an empty line" do
    rendered = render_map(paths: [ path, path(label: "empty", points: []) ])

    assert_equal 1, wide(rendered).css("polyline.sun").length
  end

  test "draws every path once and writes its date at the apex, over it or, for the lowest arc, under it" do
    rendered = render_map(paths: [ path, path(label: "21.3. / 23.9.", points: [ [ 90.0, 1.0 ], [ 180.0, 38.0 ], [ 270.0, 1.0 ] ]),
                                   path(label: "21.12.", points: [ [ 130.0, 1.0 ], [ 180.0, 14.0 ], [ 230.0, 1.0 ] ]) ])

    [ wide(rendered), narrow(rendered) ].each do |svg|
      assert_equal 3, svg.css("polyline.sun").length

      labels = svg.css("text.path-label").to_h { |node| [ node.text, node ] }
      assert_equal [ "21.6.", "21.3. / 23.9.", "21.12." ], labels.keys
      # All sit at the arc's apex at 180°, which is the same x on every path.
      assert_equal [ "381" ], labels.values.map { |node| node["x"] }.uniq
      assert_equal %w[auto auto hanging], labels.values.map { |node| node["dominant-baseline"] }
      over_anchor = svg["class"].include?("narrow") ? "start" : "middle"
      assert_equal [ over_anchor, over_anchor, "middle" ], labels.values.map { |node| node["text-anchor"] },
                   "on the phone the dates over an apex start there, clear of noon's label left of it"

      apexes = svg.css("polyline.sun").map { |line| line["points"].split[1].split(",").last.to_f }
      over, middle, under = labels.values.map { |node| node["y"].to_f }
      assert_in_delta apexes[0] - 9, over, 0.05
      assert_in_delta apexes[1] - 9, middle, 0.05
      assert_in_delta apexes[2] + 9, under, 0.05, "the winter date hangs under its arc, where the sun never stands"
    end
  end

  test "hangs the date under the arc whose apex is lowest, wherever that arc comes in the list" do
    # The winter arc comes first and reaches further west than the summer arc.
    winter = path(label: "21.12.", points: [ [ 100.0, 8.0 ], [ 200.0, 10.0 ], [ 310.0, 1.0 ] ])
    labels = wide(render_map(paths: [ winter, path ])).css("text.path-label")

    assert_equal [ [ "21.12.", "hanging" ], [ "21.6.", "auto" ] ], labels.map { |node| [ node.text, node["dominant-baseline"] ] }
  end

  test "draws the sky wide from a small tablet up and taller on a phone" do
    rendered = render_map

    assert_equal %w[yield-map-wide d-none d-sm-block], wide(rendered)["class"].split
    assert_equal %w[yield-map-narrow d-sm-none], narrow(rendered)["class"].split
    assert_equal "0 0 720 290.5", wide(rendered)["viewBox"]
    # The same sky, its height stretched 2.1 instead of 1.45 times.
    assert_equal "0 0 720 397.5", narrow(rendered)["viewBox"]
    assert_equal 1, narrow(rendered).css(".fields rect").length
    assert_empty narrow(rendered).css(".label-dense")
    assert_empty wide(rendered).css(".label-sparse")
    assert_equal %w[Ost Süd West], narrow(rendered).css(".month-labels text").map(&:text)
    assert_equal 3, narrow(rendered).css(".grid").last.css("line").length, "the phone draws only the compass' lines"
  end

  test "names every marked hour on the wide sky and only noon on the phone's" do
    dots = [ Shading::Dot.new(hour: 9, azimuth: 120.0, elevation: 40.0), Shading::Dot.new(hour: 12, azimuth: 180.0, elevation: 60.0),
             Shading::Dot.new(hour: 15, azimuth: 240.0, elevation: 40.0) ]
    rendered = render_map(paths: [ path(dots: dots) ])

    assert_equal %w[09:00 12:00 15:00], wide(rendered).css("text.dot-label").map(&:text)
    assert_equal 3, narrow(rendered).css("circle.dot").length
    assert_equal %w[12:00], narrow(rendered).css("text.dot-label").map(&:text)
  end

  test "sets the phone's noon diagonally over its dot, on the side away from the apex" do
    [ [ 165.0, "end", -10 ], [ 180.0, "end", -10 ], [ 195.0, "start", 10 ] ].each do |azimuth, anchor, offset|
      dots = [ Shading::Dot.new(hour: 12, azimuth: azimuth, elevation: 58.0) ]
      svg = narrow(render_map(paths: [ path(dots: dots) ]))
      dot = svg.css("circle.dot").sole
      hour = svg.css("text.dot-label").sole

      assert_equal [ anchor, "auto" ], [ hour["text-anchor"], hour["dominant-baseline"] ], "noon at #{azimuth}°"
      assert_equal Plot.number(dot["cx"].to_f + offset), hour["x"].to_f
      assert_equal Plot.number(dot["cy"].to_f - 10), hour["y"].to_f
    end
  end

  test "centres the wide sky's hours on their place beside the dot" do
    dots = [ Shading::Dot.new(hour: 12, azimuth: 165.0, elevation: 58.0) ]

    assert_equal "central", wide(render_map(paths: [ path(dots: dots) ])).css("text.dot-label").sole["dominant-baseline"]
  end

  test "writes the hour outside its arc, away from the arc's middle, on the empty sky" do
    dots = [ Shading::Dot.new(hour: 9, azimuth: 120.0, elevation: 40.0), Shading::Dot.new(hour: 12, azimuth: 180.0, elevation: 60.0),
             Shading::Dot.new(hour: 15, azimuth: 240.0, elevation: 40.0) ]
    rendered = render_map(paths: [ path(dots: dots) ])

    circles = wide(rendered).css("circle.dot")
    hours = wide(rendered).css("text.dot-label")

    assert_equal %w[09:00 12:00 15:00], hours.map(&:text)
    assert_equal %w[end middle start], hours.map { |hour| hour["text-anchor"] }
    circles.zip(hours).each do |dot, hour|
      assert_operator hour["y"].to_f, :<, dot["cy"].to_f, "#{hour.text} stands above its dot"
    end
    assert_operator hours[0]["x"].to_f, :<, circles[0]["cx"].to_f
    assert_equal circles[1]["cx"], hours[1]["x"]
    assert_operator hours[2]["x"].to_f, :>, circles[2]["cx"].to_f
  end

  test "sets an hour off its dot by ten units, along the line from the arc's foot to the dot" do
    dots = [ Shading::Dot.new(hour: 15, azimuth: 240.0, elevation: 40.0) ]
    hour = wide(render_map(paths: [ path(dots: dots) ])).css("text.dot-label").sole

    # The dot sits at 545.5, 95.5; the arc's foot at 381, 254.5.
    assert_equal [ "552.7", "88.6", "start" ], [ hour["x"], hour["y"], hour["text-anchor"] ]
  end

  test "points outwards with a unit vector from the horizon under the arc's middle" do
    component = sky
    horizon = component.plot.y(0)

    assert_equal [ 0.6, -0.8 ], component.send(:outwards, 411.0, horizon - 40, 381.0).map { |value| value.round(6) }
    assert_equal [ 0, -1 ], component.send(:outwards, 381.0, horizon, 381.0)
  end

  test "keeps a sideways label beside its dot only while the plot leaves it the room" do
    component = sky

    # The plot runs from 52 to 710; a label needs 90 units beside its dot.
    assert_equal [ -0.9, -0.4 ], component.send(:room_for, 142.0, -0.9, -0.4)
    assert_equal [ 0, -1 ], component.send(:room_for, 141.9, -0.9, -0.4)
    assert_equal [ 0, -1 ], component.send(:room_for, 100.0, -0.9, -0.4)
    assert_equal [ 0.9, -0.4 ], component.send(:room_for, 620.0, 0.9, -0.4)
    assert_equal [ 0, -1 ], component.send(:room_for, 620.1, 0.9, -0.4)
    assert_equal [ -0.3, -0.95 ], component.send(:room_for, 60.0, -0.3, -0.95), "a label over its dot needs no room beside it"
  end

  test "stands an hour over its dot where the plot's edge leaves no room beside it" do
    dots = [ Shading::Dot.new(hour: 6, azimuth: 65.0, elevation: 8.0), Shading::Dot.new(hour: 18, azimuth: 295.0, elevation: 8.0) ]
    rendered = render_map(paths: [ path(dots: dots) ])

    circles = wide(rendered).css("circle.dot")
    hours = wide(rendered).css("text.dot-label")

    assert_equal %w[middle middle], hours.map { |hour| hour["text-anchor"] }
    assert_equal circles.map { |dot| dot["cx"] }, hours.map { |hour| hour["x"] }
    assert_equal circles.map { |dot| Plot.number(dot["cy"].to_f - 10) }, hours.map { |hour| hour["y"].to_f }
  end

  test "stands an hour over its dot when the dot sits at the arc's very foot" do
    dots = [ Shading::Dot.new(hour: 12, azimuth: 180.0, elevation: 0.0) ]

    hour = wide(render_map(paths: [ path(dots: dots) ])).css("text.dot-label").sole

    assert_equal [ "381", "244.5", "middle" ], [ hour["x"], hour["y"], hour["text-anchor"] ]
  end

  test "marks the hours on the first path only" do
    dots = [ Shading::Dot.new(hour: 9, azimuth: 120.0, elevation: 30.0) ]
    rendered = render_map(paths: [ path(dots: dots), path(label: "21.12.", dots: dots) ])

    assert_equal 2, wide(rendered).css("circle.dot").length
    assert_equal [ "09:00" ], wide(rendered).css("text.dot-label").map(&:text)
  end

  test "measures the fields, the grid and the paths against the same axes" do
    dots = [ Shading::Dot.new(hour: 12, azimuth: 180.0, elevation: 60.0) ]
    rendered = render_map(paths: [ path(dots: dots) ])

    assert_equal "0 0 720 290.5", wide(rendered)["viewBox"]

    rect = wide(rendered).css(".fields rect").sole
    assert_equal %w[271.3 55.8 13.1 19.2], %w[x y width height].map { |name| rect[name] }

    horizon = wide(rendered).css("g.grid").first.css("line").first
    assert_equal %w[52 710 254.5 254.5], %w[x1 x2 y1 y2].map { |name| horizon[name] }

    label = wide(rendered).css(".hour-labels.label-dense text").first
    assert_equal [ "0°", "47", "254.5" ], [ label.text, label["x"], label["y"] ]

    east = wide(rendered).css(".month-labels.label-dense text").find { |node| node.text == "Ost 90°" }
    assert_equal %w[134.3 259.5], [ east["x"], east["y"] ]

    assert_equal "52,234.6 381,16 710,238.6", wide(rendered).css("polyline.sun").sole["points"]

    dot = wide(rendered).css("circle.dot").sole
    assert_equal %w[381 16], [ dot["cx"], dot["cy"] ]
    assert_equal %w[381 6], [ wide(rendered).css("text.dot-label").sole["x"], wide(rendered).css("text.dot-label").sole["y"] ]
    assert_equal %w[381 7], [ wide(rendered).css("text.path-label").sole["x"], wide(rendered).css("text.path-label").sole["y"] ]
  end

  test "rounds the axes outwards to whole tens of degrees" do
    rough = path(points: [ [ 63.7, 5.0 ], [ 180.0, 57.3 ], [ 291.4, 4.0 ] ])
    rendered = render_map(paths: [ rough ])

    # 63.7° snaps down to 60°, 291.4° up to 300°, and 57.3° of height up to 60°.
    assert_equal "0 0 720 290.5", wide(rendered)["viewBox"]
    heights = wide(rendered).css(".hour-labels.label-dense text")
    assert_equal %w[0° 60°], [ heights.first.text, heights.last.text ]
    assert_equal %w[60° Ost\ 90°], wide(rendered).css(".month-labels.label-dense text").map(&:text).first(2)
    assert_equal %w[52 134.3], wide(rendered).css(".month-labels.label-dense text").map { |node| node["x"] }.first(2)
    assert_equal "62.1,234.6 381,26.7 686.4,238.6", wide(rendered).css("polyline.sun").sole["points"]
  end

  test "explains the map and shows the ramp its fields are coloured from" do
    rendered = render_map

    assert_equal "background: #{Ramp.fetch(:diverging).css_gradient}", rendered.css(".legend-ramp").sole["style"]
    assert_equal "Ausbeute 0 %100 %", rendered.css(".legend-item").first.text.squish
    assert_equal "Wie wird gerechnet?", rendered.css("details.solakon-details > summary").sole.text
    assert_equal rendered.css(".note").sole, rendered.css("details .note").sole, "the method waits behind its question"
    assert_equal "Ausbeute ist die PV-Leistung geteilt durch die Einstrahlung derselben Stunde, " \
                 "bezogen auf die beste je gemessene Stunde. Gezählt werden nur Stunden mit mindestens " \
                 "100 W/m²; ein Feld von 5° × 5° zeigt den Median seiner Stunden und bleibt unter " \
                 "3 Stunden leer.", rendered.css(".note").sole.text
  end

  test "waits for the first fields with a word instead of an empty sky" do
    rendered = render_map(bins: [])

    assert_empty rendered.css("svg")
    assert_match(/füllt sich/, rendered.css(".note").sole.text)
  end
end
