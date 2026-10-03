import { Controller } from "@hotwired/stimulus"
import "chart.js"
import { themeColor, withAlpha, onThemeChange } from "lib/theme_colors"

const REFRESH_MS = 60_000
const SERIES_TOKENS = { "PV": "--viz-solar", "Akku": "--viz-battery", "Außensteckdose": "--viz-grid", "0 W": "--viz-muted" }

// Draws the chart from the payload the server rendered into the frame. Turbo
// swaps the frame content on every range change, which reconnects this
// controller with a fresh payload; the periodic refresh reloads the frame the
// same way, so the selected range never has to be tracked on the client.
export default class extends Controller {
  static targets = ["canvas", "payload"]
  static values = { url: String }

  connect() {
    this.chart = this._buildChart(this._readPayload())
    this._onResync = () => this.reload()
    document.addEventListener("live-freshness:resync", this._onResync)
    this.timer = setInterval(() => this.reload(), REFRESH_MS)
    this._offTheme = onThemeChange(() => this._rebuild())
  }

  disconnect() {
    this._offTheme?.()
    document.removeEventListener("live-freshness:resync", this._onResync)
    clearInterval(this.timer)
    this.chart?.destroy()
  }

  reload() {
    const frame = this.element.closest("turbo-frame")
    if (frame) frame.src = this.urlValue
  }

  _readPayload() {
    try {
      return JSON.parse(this.payloadTarget.textContent)
    } catch (error) {
      return { labels: [], datasets: [] }
    }
  }

  // Colours are resolved once per build; a theme change rebuilds the chart.
  _buildChart(chart) {
    const text = themeColor("--muted")
    const grid = withAlpha(themeColor("--border"), 0.6)
    const axis = () => ({ ticks: { color: text }, grid: { color: grid }, border: { color: grid } })

    const datasets = (chart.datasets || []).map((dataset) => {
      const color = themeColor(SERIES_TOKENS[dataset.label] || "--viz-muted")
      const fill = dataset.label === "PV"
      return {
        label: dataset.label,
        data: dataset.data,
        borderColor: color,
        backgroundColor: fill ? withAlpha(color, 0.14) : "transparent",
        borderDash: dataset.label === "0 W" ? [4, 4] : [],
        fill,
        pointRadius: 0,
        tension: 0.2,
      }
    })

    return new Chart(this.canvasTarget, {
      type: "line",
      data: { labels: chart.labels || [], datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: { x: axis(), y: { ...axis(), title: { display: true, text: "Watt", color: text } } },
        plugins: {
          legend: { position: "bottom", labels: { color: text, boxWidth: 12, boxHeight: 12, padding: 10, font: { size: 12 } } },
          tooltip: {
            backgroundColor: themeColor("--surface-raised"),
            titleColor: themeColor("--text"),
            bodyColor: themeColor("--text"),
            borderColor: themeColor("--border"),
            borderWidth: 1,
          },
        },
        animation: false,
      },
    })
  }

  _rebuild() {
    this.chart?.destroy()
    this.chart = this._buildChart(this._readPayload())
  }
}
