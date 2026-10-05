# energy_flow.js finds a channel's line and dots as efLine<key> and efDots<key>.
module EnergyFlowHelper
  WIDTH = 400
  HEIGHT = 320
  RADIUS = 40

  Ring = Data.define(:cx, :cy, :stroke)
  Channel = Data.define(:key, :tone, :d)

  RINGS = {
    pv: Ring.new(cx: 200, cy: 80, stroke: "--viz-solar"),
    grid: Ring.new(cx: 58, cy: 170, stroke: "--viz-grid"),
    consumer: Ring.new(cx: 342, cy: 170, stroke: "--ef-groove"),
    battery: Ring.new(cx: 200, cy: 260, stroke: "--viz-battery")
  }.freeze

  # Lines start inside their ring, so the dots enter from under it instead of waiting on top.
  CHANNELS = [
    Channel.new(key: "SolarHome", tone: "--viz-solar",
                d: "M 209.6,109.5 L 212.4,118 C 219.2,139 246.9,139.1 304,157.6 L 312.5,160.4"),
    Channel.new(key: "SolarGrid", tone: "--viz-solar",
                d: "M 190.4,109.5 L 187.6,118 C 180.8,139 153.1,139.1 96,157.6 L 87.5,160.4"),
    Channel.new(key: "SolarBattery", tone: "--viz-solar", d: "M 200,111 L 200,229"),
    Channel.new(key: "GridHome", tone: "--viz-grid", d: "M 89,170 L 311,170"),
    Channel.new(key: "GridBattery", tone: "--viz-grid",
                d: "M 87.5,179.6 L 96,182.4 C 153.1,200.9 180.8,201 187.6,222 L 190.4,230.5"),
    Channel.new(key: "BatteryHome", tone: "--viz-battery",
                d: "M 209.6,230.5 L 212.4,222 C 219.2,201 246.9,200.9 304,182.4 L 312.5,179.6")
  ].freeze

  def energy_flow_clip_path
    holes = RINGS.values.map do |ring|
      top = ring.cy - RADIUS
      arc = "A #{RADIUS},#{RADIUS} 0 1,0"
      "M #{ring.cx},#{top} #{arc} #{ring.cx},#{ring.cy + RADIUS} #{arc} #{ring.cx},#{top} Z"
    end
    "M 0,0 H #{WIDTH} V #{HEIGHT} H 0 Z #{holes.join(' ')}"
  end

  def energy_flow_ring(name, &)
    ring = RINGS.fetch(name)
    box = { left: energy_flow_percent(ring.cx, WIDTH), top: energy_flow_percent(ring.cy, HEIGHT),
            width: energy_flow_percent(2 * RADIUS, WIDTH), height: energy_flow_percent(2 * RADIUS, HEIGHT) }
    tag.div(class: "ef-ring", style: box.map { |side, value| "#{side}: #{value}" }.join("; "), data: { ring: name }, &)
  end

  private

  def energy_flow_percent(units, extent) = format("%g%%", units * 100.0 / extent)
end
