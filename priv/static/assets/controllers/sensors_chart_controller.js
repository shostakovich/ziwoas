import { Controller } from "@hotwired/stimulus"
import "chart.js"
import { chartTheme, vizToken, tonesByOrder, timeScale, timeTooltipTitle } from "lib/chart_theme"

const CO2_THRESHOLDS = [
  { value: 1000, name: "Lüften", tone: "--felt-warning", textTone: "--felt-warning-text" },
  { value: 1400, name: "Grenzwert", tone: "--felt-danger", textTone: "--felt-danger-text" },
]
// Room for the top threshold's label on a tick a phone's 500-step axis shares (1.400 × 1.1 rounds up to 2.000).
const CO2_AXIS_TOP = 1500
const DECIMALS = { "°C": 1, "%": 0, "ppm": 0 }
// A temperature has no natural zero: 0 °C would flatten the indoor swing.
const FROM_ZERO = { "°C": false, "%": true, "ppm": true }

export default class extends Controller {
  static targets = ["temperature", "humidity", "co2"]
  static values  = {
    url:             String,
    refreshInterval: { type: Number, default: 900_000 },
  }

  connect() {
    this.charts = {}
    this.load()
    this.refreshTimer = setInterval(() => this.load(), this.refreshIntervalValue)
    this._onVisibility = () => { if (document.visibilityState === "visible") this.load() }
    document.addEventListener("visibilitychange", this._onVisibility)
    this._onPageShow = (e) => { if (e.persisted) this.load() }
    window.addEventListener("pageshow", this._onPageShow)
  }

  disconnect() {
    clearInterval(this.refreshTimer)
    document.removeEventListener("visibilitychange", this._onVisibility)
    window.removeEventListener("pageshow", this._onPageShow)
    Object.values(this.charts).forEach(c => c?.destroy())
    this.charts = {}
  }

  async load() {
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!res.ok) return
      this._renderAll(await res.json())
    } catch (e) {
      console.error("sensors-chart load failed:", e)
    }
  }

  _renderAll(data) {
    const tones = tonesByOrder(data.temperature.map((s) => s.device_id))
    this._render("temperature", this.temperatureTarget, data.temperature, tones, "°C")
    this._render("humidity",    this.humidityTarget,    data.humidity,    tones, "%")
    this._render("co2",         this.co2Target,         data.co2,         tones, "ppm",
                 { thresholds: CO2_THRESHOLDS, suggestedMax: CO2_AXIS_TOP })
  }

  _render(key, canvas, series, tones, unit, { thresholds = [], suggestedMax } = {}) {
    if (!canvas) return
    const xBounds = this._xBounds(series)
    const datasets = [ ...this._datasets(series, tones), ...thresholds.map((line) => this._thresholdLine(xBounds, line)) ]
    const options = this._opts(unit, xBounds, series.length)
    if (suggestedMax !== undefined) options.scales.y.suggestedMax = suggestedMax
    this.charts[key]?.destroy()
    this.charts[key] = new Chart(canvas, {
      type: "line",
      data: { datasets },
      options,
      plugins: [ chartTheme ],
    })
  }

  _datasets(series, tones) {
    return series.map((s) => ({
      label: s.name,
      data:  s.points.map(([x, y]) => ({ x, y })),
      tone:  tones.get(s.device_id) ?? vizToken(0),
      fillAlpha: 0.15,
      tension: 0.25,
      borderWidth: 2,
      pointRadius: 0,
    }))
  }

  _thresholdLine(xBounds, { value, name, tone, textTone }) {
    const data = xBounds ? [ { x: xBounds.min, y: value }, { x: xBounds.max, y: value } ] : []
    return {
      label: name,
      endLabel: name,
      endLabelTone: textTone,
      data,
      tone,
      borderDash:    [ 4, 4 ],
      borderWidth:   1.5,
      pointRadius:   0,
      fill: false,
      tension: 0,
    }
  }

  // A single sensor needs no legend: the card's subtitle names its room.
  _opts(unit, xBounds, seriesCount) {
    const xScale = xBounds ? timeScale(xBounds.min, xBounds.max) : { type: "linear" }

    return {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      scales: {
        x: xScale,
        y: { beginAtZero: FROM_ZERO[unit] ?? true, unit, decimals: DECIMALS[unit] ?? 0 },
      },
      plugins: {
        legend: { display: seriesCount > 1, position: "bottom" },
        tooltip: { callbacks: { title: timeTooltipTitle({ weekday: "short", hour: "2-digit", minute: "2-digit" }) } },
      },
    }
  }

  _xBounds(series) {
    const xs = series.flatMap((s) => s.points.map((p) => p[0]))
    if (xs.length === 0) return null
    return { min: Math.min(...xs), max: Math.max(...xs) }
  }
}
