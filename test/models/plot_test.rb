require "test_helper"

class PlotTest < ActiveSupport::TestCase
  cover "Plot*"

  # Seventy pixels wide, seventy high, so a tenth of either scale is seven
  # pixels and every expected number below can be read off by hand.
  def plot(width: 100, height: 100, margins: { top: 10, right: 10, bottom: 20, left: 20 }, x: 0..10, y: 0..100)
    Plot.new(width: width, height: height, margins: margins, x: x, y: y)
  end

  test "names its box in the viewBox, a fractional height included" do
    assert_equal "0 0 100 100", plot.view_box
    assert_equal "0 0 720 289.6", plot(width: 720, height: 289.64).view_box
  end

  test "rounds the viewBox width too, not only its height" do
    assert_equal "0 0 720.1 100", plot(width: 720.14, height: 100).view_box
  end

  test "puts its edges where the margins leave off" do
    frame = plot

    assert_equal 20, frame.left
    assert_equal 90, frame.right
    assert_equal 10, frame.top
    assert_equal 80, frame.bottom
  end

  test "rounds every edge to one decimal, even where subtracting margins leaves more" do
    frame = plot(width: 301.23, height: 151.67, margins: { top: 11.17, right: 23.29, bottom: 21.53, left: 35.42 })

    assert_equal 35.4, frame.left
    assert_equal 277.9, frame.right
    assert_equal 11.2, frame.top
    assert_equal 130.1, frame.bottom
  end

  test "hands out the drawing area as one box" do
    assert_equal Plot::Rect.new(x: 20, y: 10, width: 70, height: 70), plot.box
  end

  test "rounds the drawing area's width and height too, not just its corner" do
    frame = plot(width: 301.23, height: 151.67, margins: { top: 11.17, right: 23.29, bottom: 21.53, left: 35.42 })

    assert_equal Plot::Rect.new(x: 35.4, y: 11.2, width: 242.5, height: 119), frame.box
  end

  test "spreads the x domain between the left and the right edge" do
    frame = plot

    assert_equal 20, frame.x(0)
    assert_equal 90, frame.x(10)
    assert_equal 55, frame.x(5)
  end

  test "puts the y domain's beginning at the foot and its end at the top" do
    frame = plot

    assert_equal 80, frame.y(0)
    assert_equal 10, frame.y(100)
    assert_equal 45, frame.y(50)
  end

  test "runs a reversed domain the other way, for hours read downwards" do
    frame = plot(y: 22..2)

    assert_equal 80, frame.y(22)
    assert_equal 10, frame.y(2)
    assert_equal 45, frame.y(12)
  end

  test "seats a domain of a single value at the beginning of its axis" do
    frame = plot(x: 7..7, y: 300..300)

    assert_equal 20, frame.x(7)
    assert_equal 80, frame.y(300)
  end

  test "extends past a single-value domain as if its span were one full unit" do
    frame = plot(x: 7..7, y: 300..300)

    assert_equal 160, frame.x(9)
  end

  test "rounds a coordinate to one decimal and keeps a whole number whole" do
    assert_equal 3, Plot.number(3.0)
    assert_kind_of Integer, Plot.number(3.0)
    assert_equal 3, Plot.number(3.04)
    assert_equal 3.1, Plot.number(3.06)
    assert_equal 3, plot.number(3.0)
  end

  test "rounds an axis maximum outwards to the next round step" do
    assert_equal 200, Plot.round_up(101, to: 100)
    assert_equal 100, Plot.round_up(100, to: 100)
    assert_equal 0, Plot.round_up(0, to: 100)
    assert_equal 60, Plot.round_down(63.7, to: 10)
    assert_equal 60, Plot.round_down(60, to: 10)
  end

  test "gives a tick the value it stands for and the coordinate it sits at" do
    assert_equal [ Plot::Tick.new(value: 3, at: 41) ], plot.x_ticks([ 3 ])
    assert_equal [ Plot::Tick.new(value: 0, at: 80), Plot::Tick.new(value: 50, at: 45) ], plot.y_ticks([ 0, 50 ])
  end

  test "rounds a tick's coordinate to one decimal on both axes" do
    frame = plot(width: 301.23, height: 151.67, margins: { top: 11.17, right: 23.29, bottom: 21.53, left: 35.42 },
                x: 0..3, y: 0..7)

    assert_equal [ Plot::Tick.new(value: 1, at: 116.3), Plot::Tick.new(value: 2, at: 197.1) ], frame.x_ticks([ 1, 2 ])
    assert_equal [ Plot::Tick.new(value: 3, at: 79.2) ], frame.y_ticks([ 3 ])
  end

  test "writes a run of points as one line of corners" do
    assert_equal "20,80 27,73 34,66", plot.line([ [ 0, 0 ], [ 1, 10 ], [ 2, 20 ] ])
  end

  test "draws one polyline while the points keep step" do
    assert_equal [ "20,80 27,73 34,66" ], plot.polylines([ [ 0, 0 ], [ 1, 10 ], [ 2, 20 ] ])
  end

  test "breaks a polyline where the x values skip a step" do
    lines = plot.polylines([ [ 0, 0 ], [ 1, 0 ], [ 3, 0 ] ])

    assert_equal 2, lines.length
    assert_equal "20,80 27,80", lines.first
    assert_equal "41,80", lines.last
  end

  test "keeps a repeated x value inside its run, the way a doubled hour repeats a day" do
    assert_equal 1, plot.polylines([ [ 0, 0 ], [ 0, 10 ], [ 1, 20 ] ]).length
  end

  test "breaks only where the step is wider than the gap it was given" do
    assert_equal 1, plot.polylines([ [ 0, 0 ], [ 2, 0 ] ], gap: 2).length
    assert_equal 2, plot.polylines([ [ 0, 0 ], [ 3, 0 ] ], gap: 2).length
  end

  test "closes an area down to the foot of the y scale, under the run's own ends" do
    assert_equal [ "27,80 27,73 34,66 34,80" ], plot.areas([ [ 1, 10 ], [ 2, 20 ] ])
  end

  test "closes an area on the foot the domain starts at, not on zero" do
    assert_equal [ "27,80 27,45 34,10 34,80" ], plot(y: 50..100).areas([ [ 1, 75 ], [ 2, 100 ] ])
  end

  test "breaks an area where the line breaks instead of closing over the gap" do
    areas = plot.areas([ [ 0, 10 ], [ 1, 20 ], [ 3, 30 ] ])

    assert_equal 2, areas.length
    assert_equal "20,80 20,73 27,66 27,80", areas.first
    assert_equal "41,80 41,59 41,80", areas.last
  end

  test "gives every column the full height of the plot and the width to the next value" do
    columns = plot.columns([ 0, 1 ])

    assert_equal Plot::Rect.new(x: 20, y: 10, width: 7, height: 70), columns.first
    assert_equal 27, columns.last.x
  end

  test "stops the last column at the right edge instead of running past it" do
    assert_equal 0, plot.columns([ 10 ]).sole.width
    assert_equal 7, plot.columns([ 9 ]).sole.width
  end

  test "rounds every column to one decimal, not just its width" do
    frame = plot(width: 301.23, height: 151.67, margins: { top: 11.17, right: 23.29, bottom: 21.53, left: 35.42 },
                x: 0..3, y: 0..7)

    assert_equal [
      Plot::Rect.new(x: 116.3, y: 11.2, width: 80.8, height: 119),
      Plot::Rect.new(x: 197.1, y: 11.2, width: 80.8, height: 119)
    ], frame.columns([ 1, 2 ])
  end

  test "cuts a box out of the plot from a pair of ranges" do
    assert_equal Plot::Rect.new(x: 27, y: 45, width: 14, height: 35), plot.rect(1..3, 0..50)
  end

  test "takes the inset off the box's width and height, not off its corner" do
    assert_equal Plot::Rect.new(x: 27, y: 45, width: 13.4, height: 34.4), plot.rect(1..3, 0..50, inset: 0.6)
  end

  test "keeps a box's corner at its smaller coordinates when a scale runs the other way" do
    assert_equal Plot::Rect.new(x: 27, y: 10, width: 14, height: 17.5), plot(y: 22..2).rect(1..3, 2..7)
  end

  test "keeps a box's corner at its smaller x coordinate too, when the x scale runs the other way, every field rounded" do
    frame = plot(width: 301.23, height: 151.67, margins: { top: 11.17, right: 23.29, bottom: 21.53, left: 35.42 },
                x: 22..2, y: 0..100)

    assert_equal Plot::Rect.new(x: 217.3, y: 23.1, width: 60.6, height: 95.2), frame.rect(2..7, 10..90)
  end
end
