require "test_helper"

class Sensors::Co2GaugeComponentTest < ViewComponent::TestCase
  cover "Sensors::Co2GaugeComponent*"

  def gauge(ppm) = render_inline(Sensors::Co2GaugeComponent.new(ppm: ppm)).css("svg.co2-gauge").sole

  def needle_angle(ppm) = gauge(ppm).css("g.co2-gauge-needle").sole["transform"][/rotate\((-?[\d.]+)/, 1].to_f

  test "the gauge names the value and its level for screen readers" do
    svg = gauge(850)

    assert_equal "img", svg["role"]
    assert_equal "CO₂ 850 ppm, gut", svg["aria-label"]
    assert_equal "CO₂ 1.200 ppm, erhöht", gauge(1200)["aria-label"]
    assert_equal "CO₂ 1.600 ppm, schlecht", gauge(1600)["aria-label"]
  end

  test "three zones split the arc at the presenter's thresholds" do
    zones = gauge(850).css("path.co2-gauge-zone")

    assert_equal %w[good warn bad], zones.map { |z| z["data-level"] }
    # 400–2000 ppm over 180°: 1000 ppm sits at 67.5°, 1400 ppm at 112.5°.
    assert_equal "M 14.0 60.0 A 46 46 0 0 1 42.4 17.5", zones[0]["d"]
    assert_equal "M 42.4 17.5 A 46 46 0 0 1 77.6 17.5", zones[1]["d"]
    assert_equal "M 77.6 17.5 A 46 46 0 0 1 106.0 60.0", zones[2]["d"]
  end

  test "only the zone the value falls in is lit" do
    assert_equal %w[good], gauge(850).css("path.co2-gauge-zone.is-current").map { |z| z["data-level"] }
    assert_equal %w[warn], gauge(1000).css("path.co2-gauge-zone.is-current").map { |z| z["data-level"] }
    assert_equal %w[bad],  gauge(1401).css("path.co2-gauge-zone.is-current").map { |z| z["data-level"] }
  end

  test "felt-css's felt covers each zone, and its stitch runs along the arc" do
    svg = gauge(850)

    assert_equal svg.css("path.co2-gauge-zone").map { |z| z["d"] },
                 svg.css("path.co2-gauge-texture").map { |t| t["d"] }
    assert_equal Sensors::Co2GaugeComponent::FELT_TEXTURE, svg.css("pattern image").sole["href"]

    seam = svg.css("g.co2-gauge-stitches").first.css("use")
    assert_equal 13, seam.size
    assert_equal "translate(14.3 54.5) rotate(-83.1) scale(1.15)", seam.first["transform"]
    assert_equal "translate(105.7 54.5) rotate(83.1) scale(1.15)", seam.last["transform"]
  end

  test "two gauges on a page keep their own ids" do
    ids = [ gauge(850), gauge(1200) ].map { |svg| svg.css("defs [id]").map { |e| e["id"] } }

    assert_empty ids.first & ids.last
  end

  test "the parts of one gauge keep ids apart and every reference finds its target" do
    svg = gauge(850)
    ids = svg.css("defs [id]").map { |e| e["id"] }

    assert_equal 5, ids.size
    assert_equal ids, ids.uniq
    references = svg.to_html.scan(/(?:url\(#|href="#)([^")]+)/).flatten
    assert_empty references - ids
  end

  test "the needle turns from the left end by the value's share of the scale" do
    assert_in_delta 0.0,   needle_angle(400)
    assert_in_delta 67.5,  needle_angle(1000)
    assert_in_delta 90.0,  needle_angle(1200)
    assert_in_delta 180.0, needle_angle(2000)
  end

  test "values beyond the scale pin the needle to its ends" do
    assert_in_delta 0.0,   needle_angle(300)
    assert_in_delta 180.0, needle_angle(5000)
    assert_equal "CO₂ 5.000 ppm, schlecht", gauge(5000)["aria-label"]
  end
end
