// app/javascript/controllers/sensors_chart_controller.js
import { Controller } from "@hotwired/stimulus"
import "chart.js"
import { chartTheme, vizToken, timeScale, formatTime } from "lib/chart_theme"

// CO₂ thresholds drawn as dashed lines, coloured like the traffic light and
// named at their end.
const CO2_THRESHOLDS = [
  { value: 1000, name: "Lüften", tone: "--warning", textTone: "--warning-text" },
  { value: 1400, name: "Grenzwert", tone: "--danger", textTone: "--danger-text" },
]
// Room above the top threshold for its label, on a tick a phone's coarse
// axis (steps of 500) shares: 1.400 × 1.1 would round up to 2.000 there.
const CO2_AXIS_TOP = 1500
const DECIMALS = { "°C": 1, "%": 0, "ppm": 0 }
// Amounts start at zero on every width; a temperature has no natural zero
// (0 °C would squash the day's swing indoors into a flat line).
const FROM_ZERO = { "°C": false, "%": true, "ppm": true }

// Connects to data-controller="sensors-chart"
// Builds three line charts (temperature, humidity, CO2) of the last 24h.
// Refreshes every 15 minutes; reloads on visibility change and bfcache restore.
// Each sensor keeps one --viz-* colour across all charts (config order);
// chartTheme resolves the tokens and repaints on theme or look changes.
export default class extends Controller {
  static targets = ["temperature", "humidity", "co2"]
  static values  = {
    url:             String,
    refreshInterval: { type: Number, default: 900_000 }, // 15 min
  }

  connect() {
    this.charts = {}
    this.series = null
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
      this.series = await res.json()
      this._renderAll()
    } catch (e) {
      console.error("sensors-chart load failed:", e)
    }
  }

  _renderAll() {
    const data = this.series
    if (!data) return
    this.deviceOrder = data.temperature.map((s) => s.device_id)
    this._render("temperature", this.temperatureTarget, data.temperature, "°C")
    this._render("humidity",    this.humidityTarget,    data.humidity,    "%")
    this._renderCo2(this.co2Target, data.co2)
  }

  _render(key, canvas, series, unit) {
    if (!canvas) return
    const xBounds = this._xBounds(series)
    const datasets = this._datasets(series)
    this.charts[key]?.destroy()
    this.charts[key] = new Chart(canvas, {
      type: "line",
      data: { datasets },
      options: this._opts(unit, xBounds, series.length),
      plugins: [ chartTheme ],
    })
  }

  _renderCo2(canvas, series) {
    if (!canvas) return
    const xBounds = this._xBounds(series)
    const datasets = this._datasets(series)
    CO2_THRESHOLDS.forEach((threshold) => datasets.push(this._thresholdLine(xBounds, threshold)))
    const options = this._opts("ppm", xBounds, series.length)
    options.scales.y.suggestedMax = CO2_AXIS_TOP
    this.charts.co2?.destroy()
    this.charts.co2 = new Chart(canvas, {
      type: "line",
      data: { datasets },
      options,
      plugins: [ chartTheme ],
    })
  }

  _datasets(series) {
    return series.map((s) => ({
      label: s.name,
      data:  s.points.map(([x, y]) => ({ x, y })),
      tone:  this._tone(s.device_id),
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
        tooltip: {
          callbacks: {
            title: (items) => {
              if (!items.length) return ""
              return formatTime(items[0].parsed.x, { weekday: "short", hour: "2-digit", minute: "2-digit" })
            },
          },
        },
      },
    }
  }

  _xBounds(series) {
    const xs = series.flatMap((s) => s.points.map((p) => p[0]))
    if (xs.length === 0) return null
    return { min: Math.min(...xs), max: Math.max(...xs) }
  }

  _tone(deviceId) {
    return vizToken(Math.max(this.deviceOrder.indexOf(deviceId), 0))
  }
}
