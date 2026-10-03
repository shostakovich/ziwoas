import { Controller } from "@hotwired/stimulus"
import "chart.js"
import { chartTheme } from "lib/chart_theme"

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
  }

  disconnect() {
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

  _buildChart(chart) {
    const datasets = (chart.datasets || []).map((dataset) => {
      const fill = dataset.label === "PV"
      return {
        label: dataset.label,
        data: dataset.data,
        tone: SERIES_TOKENS[dataset.label] || "--viz-muted",
        fillAlpha: fill ? 0.14 : 0,
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
        scales: { y: { title: { display: true, text: "Watt" } } },
        plugins: {
          legend: { position: "bottom", labels: { boxWidth: 12, boxHeight: 12, padding: 10, font: { size: 12 } } },
        },
        animation: false,
      },
      plugins: [ chartTheme ],
    })
  }
}
