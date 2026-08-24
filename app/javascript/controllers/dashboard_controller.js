import { Controller } from "@hotwired/stimulus"
import liveFeed from "controllers/live_feed"
import { EnergyFlowView, setBatteryImage } from "controllers/energy_flow"

export default class extends Controller {
  static targets = [
    "heroValue", "heroBattery", "heroBatteryImage", "heroBatterySoc",
    "tileConsumption", "tileNetbalance",
    "tileProduced", "tileConsumed", "tileSavings", "tileNettoday",
    "tileAutarky", "tileSelfConsumption",
    "plugList", "energyFlow",
  ]

  connect() {
    this.plugColors = {}
    this.flowView = this.hasEnergyFlowTarget ? new EnergyFlowView(this.energyFlowTarget) : null

    this.unsubscribe = liveFeed.subscribe({
      onState: (state) => this.render(state),
      onResync: () => this.fetchSummary(),
    })

    this.fetchSummary()
    this.summaryInterval = setInterval(() => this.fetchSummary(), 30_000)
  }

  disconnect() {
    this.unsubscribe?.()
    clearInterval(this.summaryInterval)
  }

  render({ plugs, energyFlow, stale }) {
    this.energyFlow = energyFlow
    this.element.classList.toggle("live-stale", stale)

    this.updateHero(plugs)
    this.updateLiveTiles(plugs)
    this.updatePlugBar(plugs)
    this.flowView?.render(energyFlow)
  }

  updateHero(plugs) {
    if (!this.hasHeroValueTarget) return
    const flow = this.energyFlow
    const producer = plugs.find(p => p.role === "producer")
    const fallbackW = producer?.online ? Math.abs(producer.apower_w).toFixed(0) : "—"
    const w = flow?.solakon_online ? Math.max(0, flow.solar_w || 0).toFixed(0) : fallbackW
    this.heroValueTarget.innerHTML = `<span class="hero-number">${w}</span> <span class="hero-unit">W</span>`

    if (this.hasHeroBatteryTarget) {
      const online = !!flow?.solakon_online
      this.heroBatteryTarget.hidden = !online
      if (online) {
        const soc = flow.battery_soc_pct
        const s = soc == null ? "—" : soc.toFixed(0)
        this.heroBatterySocTarget.innerHTML = `<span class="hero-number">${s}</span> <span class="hero-unit">%</span>`
        if (this.hasHeroBatteryImageTarget) setBatteryImage(this.heroBatteryImageTarget, flow.battery_state)
      }
    }
  }

  updateLiveTiles(plugs) {
    const flow = this.energyFlow
    const consumers = plugs.filter(p => p.role === "consumer")
    const conW = flow ? flow.home_w : consumers.reduce((s, p) => s + (p.online ? p.apower_w : 0), 0)
    const gridW = flow?.grid_w

    const anyOnline = flow?.solakon_online || plugs.some(p => p.online)

    if (this.hasTileConsumptionTarget)
      this.tileConsumptionTarget.textContent = anyOnline && conW != null ? conW.toFixed(0) + " W" : "—"
    if (this.hasTileNetbalanceTarget)
      this.tileNetbalanceTarget.textContent = gridW == null ? "—" : (gridW <= 0 ? "+" : "−") + Math.abs(gridW).toFixed(0) + " W"
  }

  static PLUG_COLORS = [
    "#3b82f6", "#10b981", "#8b5cf6", "#ef4444", "#06b6d4",
    "#ec4899", "#84cc16", "#6366f1", "#14b8a6", "#f43f5e",
  ]
  static PRODUCER_COLOR = "#f59f00"

  _plugColor(plugId) {
    if (this.plugColors[plugId]) return this.plugColors[plugId]
    const palette = this.constructor.PLUG_COLORS
    const color = palette[this.plugColorIdx++ % palette.length] || palette[0]
    this.plugColors[plugId] = color
    return color
  }

  updatePlugBar(plugs) {
    if (!this.hasPlugListTarget) return
    this.plugColorIdx ??= 0

    const producers = plugs.filter(p => p.role === "producer" && p.online)
    const consumers = plugs
      .filter(p => p.role === "consumer" && p.online && p.apower_w > 0)
      .sort((a, b) => b.apower_w - a.apower_w)

    const total = consumers.reduce((s, p) => s + p.apower_w, 0)

    this.plugListTarget.textContent = ""

    const bar = document.createElement("div")
    bar.className = "plug-bar"
    for (const p of consumers) {
      const seg = document.createElement("span")
      seg.className = "plug-seg"
      seg.style.width = `${(p.apower_w / total) * 100}%`
      seg.style.background = this._plugColor(p.id)
      seg.title = `${p.name} · ${p.apower_w.toFixed(0)} W`
      bar.appendChild(seg)
    }
    this.plugListTarget.appendChild(bar)

    const meta = document.createElement("div")
    meta.className = "plug-bar-meta"
    const label = document.createElement("span")
    label.textContent = "Verbrauch gesamt"
    const value = document.createElement("b")
    value.textContent = `${total.toFixed(0)} W`
    meta.append(label, value)
    this.plugListTarget.appendChild(meta)

    const legend = document.createElement("div")
    legend.className = "plug-legend"
    for (const p of producers) {
      legend.appendChild(
        this._legendItem(p.name, `-${Math.abs(p.apower_w).toFixed(0)} W`,
                         this.constructor.PRODUCER_COLOR))
    }
    for (const p of consumers) {
      legend.appendChild(
        this._legendItem(p.name, `${p.apower_w.toFixed(0)} W`,
                         this._plugColor(p.id)))
    }
    this.plugListTarget.appendChild(legend)
  }

  _legendItem(name, value, color) {
    const item = document.createElement("span")
    item.className = "plug-legend-item"

    const swatch = document.createElement("span")
    swatch.className = "plug-legend-swatch"
    swatch.style.background = color
    item.appendChild(swatch)

    const nameEl = document.createElement("span")
    nameEl.className = "plug-name"
    nameEl.textContent = name
    item.appendChild(nameEl)

    const valueEl = document.createElement("span")
    valueEl.className = "plug-value"
    valueEl.textContent = value
    item.appendChild(valueEl)

    return item
  }

  async fetchSummary() {
    try {
      const response = await fetch("/api/today/summary")
      if (!response.ok) return
      const data = await response.json()
      const fmt = (n, d = 2) => n.toFixed(d).replace(".", ",")

      if (this.hasTileProducedTarget)
        this.tileProducedTarget.textContent  = fmt(data.produced_wh_today / 1000) + " kWh"
      if (this.hasTileConsumedTarget)
        this.tileConsumedTarget.textContent  = fmt(data.consumed_wh_today / 1000) + " kWh"
      if (this.hasTileSavingsTarget)
        this.tileSavingsTarget.textContent   = fmt(data.savings_eur_today) + " €"
      if (this.hasTileNettodayTarget) {
        const net = (data.produced_wh_today - data.consumed_wh_today) / 1000
        this.tileNettodayTarget.textContent  = (net >= 0 ? "+" : "") + fmt(net) + " kWh"
      }
      const fmtPct = (ratio) => fmt(ratio * 100, 1) + " %"
      if (this.hasTileAutarkyTarget)
        this.tileAutarkyTarget.textContent = fmtPct(data.autarky_ratio || 0)
      if (this.hasTileSelfConsumptionTarget)
        this.tileSelfConsumptionTarget.textContent = fmtPct(data.self_consumption_ratio || 0)
    } catch (e) {
      console.error("fetchSummary failed:", e)
    }
  }
}
