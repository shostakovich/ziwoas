require "test_helper"

class EnergyFlowHelperTest < ActionView::TestCase
  cover "EnergyFlowHelper*"

  include EnergyFlowHelper

  test "the clip path cuts every ring out of the whole drawing" do
    assert_equal "M 0,0 H 400 V 320 H 0 Z " \
                 "M 200,40 A 40,40 0 1,0 200,120 A 40,40 0 1,0 200,40 Z " \
                 "M 58,130 A 40,40 0 1,0 58,210 A 40,40 0 1,0 58,130 Z " \
                 "M 342,130 A 40,40 0 1,0 342,210 A 40,40 0 1,0 342,130 Z " \
                 "M 200,220 A 40,40 0 1,0 200,300 A 40,40 0 1,0 200,220 Z",
                 energy_flow_clip_path
  end

  test "a ring's HTML box is the ring's bounding square in percent of the drawing" do
    styles = %i[pv grid consumer battery].to_h { |name| [ name, ring_box(name)["style"] ] }

    assert_equal({ pv: "left: 50%; top: 25%; width: 20%; height: 25%",
                   grid: "left: 14.5%; top: 53.125%; width: 20%; height: 25%",
                   consumer: "left: 85.5%; top: 53.125%; width: 20%; height: 25%",
                   battery: "left: 50%; top: 81.25%; width: 20%; height: 25%" }, styles)
  end

  test "a ring's HTML box carries its name and the content" do
    box = ring_box(:battery) { tag.span("180 W") }

    assert_equal "ef-ring", box["class"]
    assert_equal "battery", box["data-ring"]
    assert_equal "<span>180 W</span>", box.inner_html
  end

  test "an unknown ring is an error, not an unplaced box" do
    assert_raises(KeyError) { energy_flow_ring(:moon) { "" } }
  end

  test "every channel takes its source's colour" do
    tones = EnergyFlowHelper::CHANNELS.to_h { |channel| [ channel.key, channel.tone ] }

    assert_equal({ "SolarHome" => "--viz-solar", "SolarGrid" => "--viz-solar", "SolarBattery" => "--viz-solar",
                   "GridHome" => "--viz-grid", "GridBattery" => "--viz-grid", "BatteryHome" => "--viz-battery" }, tones)
  end

  private

  def ring_box(name, &content)
    Nokogiri::HTML5.fragment(energy_flow_ring(name, &content)).at_css("div")
  end
end
