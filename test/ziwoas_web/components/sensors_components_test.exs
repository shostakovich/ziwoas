defmodule ZiwoasWeb.SensorsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias ZiwoasWeb.SensorsComponents

  defp gauge(ppm),
    do:
      render_component(&SensorsComponents.co2_gauge/1, ppm: ppm)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(".co2-gauge")

  defp attrs(node, selector, name),
    do: node |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp needle_angle(ppm) do
    [transform] = attrs(gauge(ppm), "g.co2-gauge-needle", "transform")
    [_, angle] = Regex.run(~r/rotate\((-?[\d.]+)/, transform)
    String.to_float(angle)
  end

  defp label(ppm), do: attrs(gauge(ppm), "svg[role=img]", "aria-label")

  test "the gauge names the value and its level for screen readers, its thread stays silent" do
    assert label(850) == ["CO₂ 850 ppm, gut"]
    assert label(1200) == ["CO₂ 1.200 ppm, erhöht"]
    assert label(1600) == ["CO₂ 1.600 ppm, hoch"]
    assert attrs(gauge(850), "svg.stitches", "aria-hidden") == ["true"]
  end

  test "three zones split the arc at the presenter's thresholds" do
    svg = gauge(850)

    assert attrs(svg, "path.co2-gauge-zone", "data-level") == ~w[good warn bad]

    assert attrs(svg, "path.co2-gauge-zone", "d") == [
             "M 12.0 52.0 A 40 40 0 0 1 36.7 15.0",
             "M 36.7 15.0 A 40 40 0 0 1 67.3 15.0",
             "M 67.3 15.0 A 40 40 0 0 1 92.0 52.0"
           ]
  end

  test "only the zone the value falls in is lit" do
    lit = &attrs(gauge(&1), "path.co2-gauge-zone.is-current", "data-level")

    assert lit.(850) == ["good"]
    assert lit.(1000) == ["warn"]
    assert lit.(1401) == ["bad"]
  end

  test "felt-css's felt covers each zone, and its stitch runs along the arc and crosses the hub" do
    gauge = gauge(850)

    assert attrs(gauge, "path.co2-gauge-zone", "d") ==
             attrs(gauge, "path.co2-gauge-texture.felt-texture", "d")

    assert attrs(gauge, "pattern image", "href") == ["https://felt-css.rocu.de/img/felt.svg"]
    assert attrs(gauge, "pattern", "width") == ["256"]

    stitches = attrs(gauge, "svg.stitches.stitches-patch use", "href")
    assert length(stitches) == 15
    assert Enum.uniq(stitches) == ["/images/felt_stitch.svg#stitch"]

    transforms = attrs(gauge, "svg.stitches use", "transform")
    assert hd(transforms) == "rotate(-83.1) translate(0 -40)"
    assert Enum.at(transforms, 12) == "rotate(83.1) translate(0 -40)"
    assert Enum.take(transforms, -2) == ["rotate(45) scale(.7)", "rotate(-45) scale(.7)"]
  end

  test "two gauges on a page keep their own ids" do
    [first, second] = Enum.map([850, 1200], &attrs(gauge(&1), "defs [id]", "id"))

    assert MapSet.disjoint?(MapSet.new(first), MapSet.new(second))
  end

  test "the parts of one gauge keep ids apart and every reference finds its target" do
    html = render_component(&SensorsComponents.co2_gauge/1, ppm: 850)

    ids =
      html |> LazyHTML.from_fragment() |> LazyHTML.query("defs [id]") |> LazyHTML.attribute("id")

    assert length(ids) == 2
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
    assert label(5000) == ["CO₂ 5.000 ppm, hoch"]
  end
end
