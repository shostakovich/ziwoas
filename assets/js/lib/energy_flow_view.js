import { formatWatts, formatPercent } from "./format.js"

// Keys match the SVG's data-ef names efLine<key> and efDots<key>.
const CHANNELS = [
  { key: "SolarHome",    flow: "solar_to_home_w" },
  { key: "SolarGrid",    flow: "solar_to_grid_w" },
  { key: "SolarBattery", flow: "solar_to_battery_w" },
  { key: "GridHome",     flow: "grid_to_home_w" },
  { key: "GridBattery",  flow: "grid_to_battery_w" },
  { key: "BatteryHome",  flow: "battery_to_home_w" },
]

const CONSUMER_SOURCES = [
  { flow: "solar_to_home_w",   color: "var(--viz-solar)" },
  { flow: "grid_to_home_w",    color: "var(--viz-grid)" },
  { flow: "battery_to_home_w", color: "var(--viz-battery)" },
]

const IDLE_W = 1

const SVG_NS = "http://www.w3.org/2000/svg"

const BASE_S = 1

function duration(w, len) {
  return w < IDLE_W ? null : Math.max(0.5, Math.min(8, len / w))
}

export class EnergyFlowView {
  constructor(element) {
    this.element = element
    this.lastDur = {}
  }

  render(flow) {
    const online = !!flow?.solakon_online
    const pvW = online ? Math.max(0, flow.solar_w || 0) : null

    this.setText("efPvW", formatWatts(pvW))
    this.setText("efConsumerW", formatWatts(flow?.home_w))
    this.setText("efGridW", magnitude(flow?.grid_w))
    this.setText("efGridName", direction(flow?.grid_w, "Netzbezug", "Einspeisung", "Stromnetz"))
    this.setText("efBatteryW", magnitude(flow?.battery_w))
    this.setText("efBatteryName", direction(flow?.battery_w, "Batterie lädt", "Batterie entlädt", "Batterie"))
    this.setText("efBatterySoc", flow?.battery_soc_pct == null ? "" : ` · ${formatPercent(flow.battery_soc_pct)}`)
    setBatteryImage(this.find("efBatteryImage"), flow?.battery_state)

    const flows = flow?.flows || {}
    for (const channel of CHANNELS) {
      const w = Number(flows[channel.flow] || 0)
      this.find(`efLine${channel.key}`)?.toggleAttribute("data-flowing", w >= IDLE_W)
      this.setDots(channel, w)
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

  // A flowing channel keeps its circles and only changes playbackRate, so dots don't snap back on a new reading.
  setDots({ key }, w) {
    const target = this.find(`efDots${key}`)
    const path = this.find(`efLine${key}`)
    if (!target || !path) return

    this.lengths ??= {}
    const dur = duration(w, this.lengths[key] ??= path.getTotalLength())

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
      if (reduceMotion) {
        dot.style.cssText = `offset-path:path("${path.getAttribute("d")}");offset-distance:${25 + i * 25}%`
        target.appendChild(dot)
      } else {
        dot.style.cssText = `offset-path:path("${path.getAttribute("d")}")`
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

    const base = this.element.querySelector('circle[data-ring="consumer"]')
    let acc = 0
    for (const segment of segments) {
      const pct = (segment.w / total) * 100
      const arc = document.createElementNS(SVG_NS, "circle")
      for (const attribute of ["cx", "cy", "r"]) arc.setAttribute(attribute, base.getAttribute(attribute))
      arc.setAttribute("fill", "none")
      arc.style.stroke = segment.color
      arc.setAttribute("stroke-width", "3")
      arc.setAttribute("pathLength", "100")
      arc.setAttribute("stroke-dasharray", `${pct} ${100 - pct}`)
      arc.setAttribute("stroke-dashoffset", `${-acc}`)
      ring.appendChild(arc)
      acc += pct
    }
  }
}

function magnitude(w) {
  return w == null ? formatWatts(null) : formatWatts(Math.abs(w))
}

function direction(w, positive, negative, idle) {
  if (w == null || Math.abs(w) < IDLE_W) return idle
  return w > 0 ? positive : negative
}

export function setBatteryImage(image, state) {
  if (!image) return
  const key = state || "normal"
  const src = image.dataset[`batteryState${key.charAt(0).toUpperCase()}${key.slice(1)}`]
  if (src) image.src = src
}
