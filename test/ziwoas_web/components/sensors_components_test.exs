defmodule ZiwoasWeb.SensorsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias ZiwoasWeb.SensorsComponents

  defp gauge(ppm),
    do:
      render_component(&SensorsComponents.co2_gauge/1, ppm: ppm)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("svg.co2-gauge")

  defp attrs(node, selector, name),
    do: node |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp needle_angle(ppm) do
    [transform] = attrs(gauge(ppm), "g.co2-gauge-needle", "transform")
    [_, angle] = Regex.run(~r/rotate\((-?[\d.]+)/, transform)
    String.to_float(angle)
  end

  test "the gauge names the value and its level for screen readers" do
    svg = gauge(850)

    assert LazyHTML.attribute(svg, "role") == ["img"]
    assert LazyHTML.attribute(svg, "aria-label") == ["CO₂ 850 ppm, gut"]
    assert LazyHTML.attribute(gauge(1200), "aria-label") == ["CO₂ 1.200 ppm, erhöht"]
    assert LazyHTML.attribute(gauge(1600), "aria-label") == ["CO₂ 1.600 ppm, hoch"]
  end

  test "three zones split the arc at the presenter's thresholds" do
    svg = gauge(850)

    assert attrs(svg, "path.co2-gauge-zone", "data-level") == ~w[good warn bad]

    assert attrs(svg, "path.co2-gauge-zone", "d") == [
             "M 14.0 60.0 A 46 46 0 0 1 42.4 17.5",
             "M 42.4 17.5 A 46 46 0 0 1 77.6 17.5",
             "M 77.6 17.5 A 46 46 0 0 1 106.0 60.0"
           ]
  end

  test "only the zone the value falls in is lit" do
    lit = &attrs(gauge(&1), "path.co2-gauge-zone.is-current", "data-level")

    assert lit.(850) == ["good"]
    assert lit.(1000) == ["warn"]
    assert lit.(1401) == ["bad"]
  end

  test "felt-css's felt covers each zone, and its stitch runs along the arc" do
    svg = gauge(850)

    assert attrs(svg, "path.co2-gauge-zone", "d") == attrs(svg, "path.co2-gauge-texture", "d")
    assert attrs(svg, "pattern image", "href") == ["https://felt-css.rocu.de/img/felt.svg"]

    seam = svg |> LazyHTML.query("g.co2-gauge-stitches") |> Enum.at(0) |> LazyHTML.query("use")
    transforms = LazyHTML.attribute(seam, "transform")

    assert length(transforms) == 13
    assert hd(transforms) == "translate(14.3 54.5) rotate(-83.1) scale(1.15)"
    assert List.last(transforms) == "translate(105.7 54.5) rotate(83.1) scale(1.15)"
  end

  test "two gauges on a page keep their own ids" do
    [first, second] = Enum.map([850, 1200], &attrs(gauge(&1), "defs [id]", "id"))

    assert MapSet.disjoint?(MapSet.new(first), MapSet.new(second))
  end

  test "the parts of one gauge keep ids apart and every reference finds its target" do
    html = render_component(&SensorsComponents.co2_gauge/1, ppm: 850)

    ids =
      html |> LazyHTML.from_fragment() |> LazyHTML.query("defs [id]") |> LazyHTML.attribute("id")

    assert length(ids) == 5
    assert ids == Enum.uniq(ids)

    references =
      Regex.scan(~r/(?:url\(#|href="#)([^")]+)/, html, capture: :all_but_first) |> List.flatten()

    assert Enum.reject(references, &(&1 in ids)) == []
    assert references != []
  end

  test "the needle turns from the left end by the value's share of the scale" do
    assert needle_angle(400) == 0.0
    assert needle_angle(1000) == 67.5
    assert needle_angle(1200) == 90.0
    assert needle_angle(2000) == 180.0
  end

  test "values beyond the scale pin the needle to its ends" do
    assert needle_angle(300) == 0.0
    assert needle_angle(5000) == 180.0
    assert LazyHTML.attribute(gauge(5000), "aria-label") == ["CO₂ 5.000 ppm, hoch"]
  end
end
