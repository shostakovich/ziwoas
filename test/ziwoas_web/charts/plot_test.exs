defmodule ZiwoasWeb.Charts.PlotTest do
  use ExUnit.Case, async: true

  alias ZiwoasWeb.Charts.Plot
  alias ZiwoasWeb.Charts.Plot.{Hit, Label, Rect, Scale, Tick}

  # A 70 × 70 plot: a tenth of either scale is seven pixels, so results read off by hand.
  defp plot(opts \\ []) do
    Plot.new(
      width: Keyword.get(opts, :width, 100),
      height: Keyword.get(opts, :height, 100),
      margins: Keyword.get(opts, :margins, top: 10, right: 10, bottom: 20, left: 20),
      x: Keyword.get(opts, :x, {0, 10}),
      y: Keyword.get(opts, :y, {0, 100})
    )
  end

  defp odd_plot(opts),
    do:
      plot(
        [
          width: 301.23,
          height: 151.67,
          margins: [top: 11.17, right: 23.29, bottom: 21.53, left: 35.42]
        ] ++ opts
      )

  test "names its box in the viewBox, a fractional height included" do
    assert Plot.view_box(plot()) == "0 0 100 100"
    assert Plot.view_box(plot(width: 720, height: 289.64)) == "0 0 720 289.6"
  end

  test "rounds the viewBox width too, not only its height" do
    assert Plot.view_box(plot(width: 720.14, height: 100)) == "0 0 720.1 100"
  end

  test "puts its edges where the margins leave off" do
    frame = plot()

    assert Plot.left(frame) === 20
    assert Plot.right(frame) === 90
    assert Plot.top(frame) === 10
    assert Plot.bottom(frame) === 80
  end

  test "rounds every edge to one decimal, even where subtracting margins leaves more" do
    frame = odd_plot([])

    assert Plot.left(frame) == 35.4
    assert Plot.right(frame) == 277.9
    assert Plot.top(frame) == 11.2
    assert Plot.bottom(frame) == 130.1
  end

  test "spreads the x domain between the left and the right edge" do
    assert Plot.x(plot(), 0) == 20
    assert Plot.x(plot(), 10) == 90
    assert Plot.x(plot(), 5) == 55
  end

  test "puts the y domain's beginning at the foot and its end at the top" do
    assert Plot.y(plot(), 0) == 80
    assert Plot.y(plot(), 100) == 10
    assert Plot.y(plot(), 50) == 45
  end

  test "runs a reversed domain the other way, for hours read downwards" do
    frame = plot(y: {22, 2})

    assert Plot.y(frame, 22) == 80
    assert Plot.y(frame, 2) == 10
    assert Plot.y(frame, 12) == 45
  end

  test "seats a domain of a single value at the beginning of its axis, as if its span were one unit" do
    frame = plot(x: {7, 7}, y: {300, 300})

    assert Plot.x(frame, 7) == 20
    assert Plot.y(frame, 300) == 80
    assert Plot.x(frame, 9) == 160
  end

  test "rounds a coordinate to one decimal and keeps a whole number whole" do
    assert Plot.number(3.0) === 3
    assert Plot.number(3.04) === 3
    assert Plot.number(3.06) === 3.1
    assert Plot.number(-0.0) === 0
  end

  test "rounds an axis maximum outwards to the next round step" do
    assert Plot.round_up(101, 100) === 200
    assert Plot.round_up(100, 100) === 100
    assert Plot.round_up(0, 100) === 0
    assert Plot.round_down(63.7, 10) === 60
    assert Plot.round_down(60, 10) === 60
  end

  test "steps a value axis in the first round step that reaches the peak in few enough steps" do
    steps = [100, 200, 250, 500]

    assert Plot.nice_scale(90.0, steps, 3) == %Scale{step: 100, top: 100}
    assert Plot.nice_scale(300.0, steps, 3) == %Scale{step: 100, top: 300}
    assert Plot.nice_scale(300.5, steps, 3) == %Scale{step: 200, top: 400}
    assert Plot.nice_scale(620.0, steps, 3) == %Scale{step: 250, top: 750}
  end

  test "steps beyond the round steps in multiples of the largest, dividing the peak exactly" do
    assert Plot.nice_scale(3000, [100, 500], 2) == %Scale{step: 1500, top: 3000}
    assert Plot.nice_scale(3001, [100, 500], 2) == %Scale{step: 2000, top: 4000}
  end

  test "keeps one step of axis for a peak of nothing" do
    assert Plot.nice_scale(0.0, [25, 50], 5) == %Scale{step: 25, top: 25}
  end

  test "spans the values from the smallest to the largest, and nothing as zero" do
    assert Plot.extent([12, 6, 18, 9]) == {6, 18}
    assert Plot.extent([7]) == {7, 7}
    assert Plot.extent([]) == {0, 0}
  end

  test "draws a grid line at every value but zero, where the axis stands" do
    assert Plot.grid_lines(plot(), [0, 50, 100]) == [45, 10]
    assert Plot.grid_lines(plot(), [50]) == [45]
  end

  test "labels every value left of the plot, the zero standing on its axis" do
    assert Plot.value_labels(plot(), [0, 50], 4) == [
             %Label{x: 16, y: 80, text: "0", zero: true},
             %Label{x: 16, y: 45, text: "50", zero: false}
           ]

    assert %Label{x: 1, y: 2, text: "Jan"}.zero == false
  end

  test "lays a tooltip over each value's column" do
    assert Plot.hits(plot(), [0, 1], ~w[null eins]) == [
             %Hit{rect: %Rect{x: 20, y: 10, width: 7, height: 70}, title: "null"},
             %Hit{rect: %Rect{x: 27, y: 10, width: 7, height: 70}, title: "eins"}
           ]
  end

  test "gives a tick the value it stands for and the coordinate it sits at, rounded" do
    assert Plot.x_ticks(plot(), [3]) == [%Tick{value: 3, at: 41}]
    assert Plot.y_ticks(plot(), [0, 50]) == [%Tick{value: 0, at: 80}, %Tick{value: 50, at: 45}]

    frame = odd_plot(x: {0, 3}, y: {0, 7})

    assert Plot.x_ticks(frame, [1, 2]) == [%Tick{value: 1, at: 116.3}, %Tick{value: 2, at: 197.1}]
    assert Plot.y_ticks(frame, [3]) == [%Tick{value: 3, at: 79.2}]
  end

  test "writes a run of points as one line of corners" do
    assert Plot.line(plot(), [{0, 0}, {1, 10}, {2, 20}]) == "20,80 27,73 34,66"
    assert Plot.polylines(plot(), [{0, 0}, {1, 10}, {2, 20}]) == ["20,80 27,73 34,66"]
  end

  test "breaks a polyline where the x values skip a step, keeping a repeated x" do
    assert Plot.polylines(plot(), [{0, 0}, {1, 0}, {3, 0}]) == ["20,80 27,80", "41,80"]
    assert length(Plot.polylines(plot(), [{0, 0}, {0, 10}, {1, 20}])) == 1
    assert length(Plot.polylines(plot(), [{0, 0}, {2, 0}], 2)) == 1
    assert length(Plot.polylines(plot(), [{0, 0}, {3, 0}], 2)) == 2
    assert Plot.polylines(plot(), []) == []
  end

  test "closes an area down to the foot the y domain starts at, per run" do
    assert Plot.areas(plot(), [{1, 10}, {2, 20}]) == ["27,80 27,73 34,66 34,80"]
    assert Plot.areas(plot(y: {50, 100}), [{1, 75}, {2, 100}]) == ["27,80 27,45 34,10 34,80"]

    assert Plot.areas(plot(), [{0, 10}, {1, 20}, {3, 30}]) ==
             ["20,80 20,73 27,66 27,80", "41,80 41,59 41,80"]
  end

  test "gives every column the full height and the width to the next value, up to the right edge" do
    assert [%Rect{x: 20, y: 10, width: 7, height: 70}, %Rect{x: 27}] =
             Plot.columns(plot(), [0, 1])

    assert [%Rect{width: 0}] = Plot.columns(plot(), [10])
    assert [%Rect{width: 7}] = Plot.columns(plot(), [9])

    assert Plot.columns(odd_plot(x: {0, 3}, y: {0, 7}), [1, 2]) == [
             %Rect{x: 116.3, y: 11.2, width: 80.8, height: 119},
             %Rect{x: 197.1, y: 11.2, width: 80.8, height: 119}
           ]
  end

  test "cuts a box out of the plot, the inset off its size, its corner at the smaller coordinates" do
    assert Plot.rect(plot(), {1, 3}, {0, 50}) == %Rect{x: 27, y: 45, width: 14, height: 35}

    assert Plot.rect(plot(), {1, 3}, {0, 50}, 0.6) == %Rect{
             x: 27,
             y: 45,
             width: 13.4,
             height: 34.4
           }

    assert Plot.rect(plot(y: {22, 2}), {1, 3}, {2, 7}) == %Rect{
             x: 27,
             y: 10,
             width: 14,
             height: 17.5
           }

    assert Plot.rect(odd_plot(x: {22, 2}, y: {0, 100}), {2, 7}, {10, 90}) ==
             %Rect{x: 217.3, y: 23.1, width: 60.6, height: 95.1}

    # 80 - 79.3 is 0.7000000000000028 in floating point.
    assert Plot.rect(plot(), {0, 1}, {0, 1}) == %Rect{x: 20, y: 79.3, width: 7, height: 0.7}
  end

  test "lets two neighbouring boxes share their rounded edge" do
    frame =
      plot(
        width: 720,
        margins: [top: 10, right: 4, bottom: 20, left: 40],
        x: {1, 366},
        y: {0, 10}
      )

    first = Plot.rect(frame, {25, 27}, {0, 1})
    second = Plot.rect(frame, {27, 29}, {0, 1})

    assert first.x == 84.4
    assert second.x == Plot.number(first.x + first.width), "no slit between the two"
  end
end
