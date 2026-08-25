const PATHS = {
  solarHome: "M 200,122 C 205,150 250,166 306,170",
  solarGrid: "M 200,122 C 195,150 150,166 94,170",
  solarBattery: "M 200,122 L 200,218",
  gridHome: "M 94,170 L 306,170",
  gridBattery: "M 94,170 C 150,174 195,190 200,218",
  batteryHome: "M 200,218 C 205,190 250,174 306,170",
}

const LENS = {
  solarHome: 123,
  solarGrid: 123,
  solarBattery: 96,
  gridHome: 212,
  gridBattery: 123,
  batteryHome: 123,
}

const CHANNELS = [
  { key: "solarHome",    flow: "solar_to_home_w",    dots: "efDotsSolarHome",    color: "#f59f00" },
  { key: "solarGrid",    flow: "solar_to_grid_w",    dots: "efDotsSolarGrid",    color: "#8b5cf6" },
  { key: "solarBattery", flow: "solar_to_battery_w", dots: "efDotsSolarBattery", color: "#ec4899" },
  { key: "gridHome",     flow: "grid_to_home_w",     dots: "efDotsGridHome",     color: "#3b82f6" },
  { key: "gridBattery",  flow: "grid_to_battery_w",  dots: "efDotsGridBattery",  color: "#94a3b8" },
  { key: "batteryHome",  flow: "battery_to_home_w",  dots: "efDotsBatteryHome",  color: "#14b8a6" },
]

const CONSUMER_SOURCES = [
  { flow: "solar_to_home_w",   color: "#f59f00" },
  { flow: "grid_to_home_w",    color: "#3b82f6" },
  { flow: "battery_to_home_w", color: "#14b8a6" },
]

const SVG_NS = "http://www.w3.org/2000/svg"

// Every dot animation runs one second per lap; the channel's real pace comes
// from playbackRate, which can change without restarting the animation.
const BASE_S = 1

function duration(w, len) {
  return w < 1 ? null : Math.max(0.5, Math.min(8, len / w))
}

export class EnergyFlowView {
  constructor(element) {
    this.element = element
    this.lastDur = {}
  }

  render(flow) {
    const online = !!flow?.solakon_online
    const pvW = online ? Math.max(0, flow.solar_w || 0) : null

    this.setText("efPvW", this.watts(pvW))
    this.setText("efConsumerW", this.watts(flow?.home_w))
    this.setText("efGridW", this.signedWatts(flow?.grid_w))
    this.setText("efBatterySoc", flow?.battery_soc_pct == null ? "— %" : `${flow.battery_soc_pct.toFixed(0)}%`)
    this.setText("efBatteryW", this.chargeWatts(flow?.battery_w))
    setBatteryImage(this.find("efBatteryImage"), flow?.battery_state)

    const flows = flow?.flows || {}
    for (const channel of CHANNELS) {
      this.setDots(channel, Number(flows[channel.flow] || 0))
    }
    this.setConsumerRing(
      CONSUMER_SOURCES.map((source) => ({ w: Number(flows[source.flow] || 0), color: source.color }))
    )
  }

  find(name) { return this.element?.querySelector(`[data-ef="${name}"]`) }

  setText(name, text) {
    const node = this.find(name)
    if (node) node.textContent = text
  }

  watts(w) { return w == null ? "— W" : `${w.toFixed(0)} W` }

  signedWatts(w) {
    if (w == null) return "— W"
    if (w > 0) return `+${w.toFixed(0)} W`
    if (w < 0) return `−${Math.abs(w).toFixed(0)} W`
    return "0 W"
  }

  chargeWatts(w) {
    if (w == null) return "— W"
    if (w > 0) return `−${w.toFixed(0)} W`
    if (w < 0) return `${Math.abs(w).toFixed(0)} W`
    return "0 W"
  }

  // Watts set the pace, not the dots' identity. A channel that keeps flowing
  // keeps its circles and only changes playback rate, so a dot mid-path speeds
  // up where it is instead of snapping back to the start on every new reading.
  setDots({ key, dots, color }, w) {
    const target = this.find(dots)
    if (!target) return

    const dur = duration(w, LENS[key])

    if (!dur) {
      if (this.lastDur[key] == null) return
      this.lastDur[key] = null
      target.innerHTML = ""
      return
    }

    if (this.lastDur[key] != null && target.childElementCount > 0) {
      if (Math.abs(dur - this.lastDur[key]) / this.lastDur[key] <= 0.05) return
      this.lastDur[key] = dur
      for (const dot of target.children) dot.getAnimations()[0]?.updatePlaybackRate(BASE_S / dur)
      return
    }

    this.lastDur[key] = dur
    target.innerHTML = ""

    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    for (let i = 0; i < 3; i++) {
      const dot = document.createElementNS(SVG_NS, "circle")
      dot.setAttribute("r", "4.5")
      dot.setAttribute("fill", color)
      if (reduceMotion) {
        dot.style.cssText = `offset-path:path("${PATHS[key]}");offset-distance:${25 + i * 25}%`
        target.appendChild(dot)
      } else {
        dot.style.cssText = `offset-path:path("${PATHS[key]}")`
        target.appendChild(dot)
        const animation = dot.animate(
          [ { offsetDistance: "0%" }, { offsetDistance: "100%" } ],
          { duration: BASE_S * 1000, delay: -(i * BASE_S / 3) * 1000, iterations: Infinity, easing: "linear" }
        )
        animation.playbackRate = BASE_S / dur
      }
    }
  }

  setConsumerRing(sources) {
    const ring = this.find("efConsumerRing")
    if (!ring) return

    const segments = sources.filter((s) => s.w > 0.5)
    const total = segments.reduce((sum, s) => sum + s.w, 0)
    ring.innerHTML = ""
    if (total <= 0) return

    let acc = 0
    for (const segment of segments) {
      const pct = (segment.w / total) * 100
      const arc = document.createElementNS(SVG_NS, "circle")
      arc.setAttribute("cx", "342")
      arc.setAttribute("cy", "170")
      arc.setAttribute("r", "40")
      arc.setAttribute("fill", "none")
      arc.setAttribute("stroke", segment.color)
      arc.setAttribute("stroke-width", "2.5")
      arc.setAttribute("pathLength", "100")
      arc.setAttribute("stroke-dasharray", `${pct} ${100 - pct}`)
      arc.setAttribute("stroke-dashoffset", `${-acc}`)
      ring.appendChild(arc)
      acc += pct
    }
  }
}

export function setBatteryImage(image, state) {
  if (!image) return
  const key = state || "normal"
  const src = image.dataset[`batteryState${key.charAt(0).toUpperCase()}${key.slice(1)}`]
  if (!src) return
  if (image.tagName.toLowerCase() === "img") image.src = src
  else image.setAttribute("href", src)
}
