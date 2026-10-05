import { Controller } from "@hotwired/stimulus"
import "chart.js"
import { chartTheme, timeCategoryScale, roundedFloor, dropOffStepBound, formatTime } from "lib/chart_theme"

const REFRESH_MS = 60_000
// A night's standby dips a few watts below zero: end on the next hundred, not a whole tick step.
const FLOOR_STEP_W = 100
const SERIES_TOKENS = { "PV": "--viz-solar", "Akku": "--viz-battery", "Außensteckdose": "--viz-grid", "0 W": "--viz-muted" }
const FLOW_WORDS = {
  "Akku": { positive: "lädt", negative: "entlädt" },
  "Außensteckdose": { positive: "liefert", negative: "zieht" },
}

// Every range change and refresh reloads the Turbo frame, so the range is never tracked here.
export default class extends Controller {
  static targets = ["canvas", "payload"]
  static values = { url: String, range: String }

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
      return { times: [], datasets: [] }
    }
  }

  _buildChart(chart) {
    const times = chart.times || []
    const datasets = (chart.datasets || []).map((dataset) => {
      const fill = dataset.label === "PV"
      const reference = dataset.label === "0 W"
      return {
        label: dataset.label,
        data: dataset.data,
        tone: SERIES_TOKENS[dataset.label] || "--viz-muted",
        fillAlpha: fill ? 0.14 : 0,
        borderDash: reference ? [4, 4] : [],
        borderWidth: reference ? 1 : 2,
        legend: !reference,
        flowWords: FLOW_WORDS[dataset.label],
        fill,
        pointRadius: 0,
        tension: 0.2,
      }
    })

    return new Chart(this.canvasTarget, {
      type: "line",
      data: { labels: times, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: timeCategoryScale(times),
          y: { unit: "W", min: this._floor(datasets), afterBuildTicks: dropOffStepBound },
        },
        plugins: {
          legend: { position: "bottom" },
          tooltip: {
            filter: (item) => item.dataset.legend !== false,
            callbacks: { title: (items) => (items.length ? this._title(times[items[0].dataIndex]) : "") },
          },
        },
        animation: false,
      },
      plugins: [ chartTheme ],
    })
  }

  _title(ms) {
    const time = formatTime(ms, { hour: "2-digit", minute: "2-digit" })
    return this.rangeValue === "24h" ? time : `${formatTime(ms, { day: "2-digit", month: "2-digit" })} ${time}`
  }

  _floor(datasets) {
    const readings = datasets.filter((dataset) => dataset.legend).flatMap((dataset) => dataset.data)
    return roundedFloor(readings, FLOOR_STEP_W)
  }
}

