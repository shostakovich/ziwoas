import { renderChart, timeCategoryScale, roundedFloor, dropOffStepBound, formatTime } from "../lib/chart_theme.js"

// A night's standby dips a few watts below zero: end on the next hundred, not a whole tick step.
const FLOOR_STEP_W = 100
const SERIES_TOKENS = { "PV": "--viz-solar", "Akku": "--viz-battery", "Außensteckdose": "--viz-grid", "0 W": "--viz-muted" }
const FLOW_WORDS = {
  "Akku": { positive: "lädt", negative: "entlädt" },
  "Außensteckdose": { positive: "liefert", negative: "zieht" },
}

// The Solakon-Verlauf: ZiwoasWeb.SolakonHistoryComponent pushes "solakon_history:data"
// ({range, times, datasets}) once connected, on a range tab and on every stored snapshot;
// the chart is redrawn in place.
export default {
  mounted() {
    this.handleEvent("solakon_history:data", (payload) => this.draw(payload))
  },

  destroyed() {
    this.chart?.destroy()
  },

  draw(payload) {
    this.chart = renderChart(this.chart, this.el.querySelector("canvas"), config(payload, payload.range))
  },
}

function config(chart, range) {
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

  return {
    type: "line",
    data: { labels: times, datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: timeCategoryScale(times),
        y: { unit: "W", min: floor(datasets), afterBuildTicks: dropOffStepBound },
      },
      plugins: {
        legend: { position: "bottom" },
        tooltip: {
          filter: (item) => item.dataset.legend !== false,
          callbacks: { title: (items) => (items.length ? title(times[items[0].dataIndex], range) : "") },
        },
      },
      animation: false,
    },
  }
}

function title(ms, range) {
  const time = formatTime(ms, { hour: "2-digit", minute: "2-digit" })
  return range === "24h" ? time : `${formatTime(ms, { day: "2-digit", month: "2-digit" })} ${time}`
}

function floor(datasets) {
  const readings = datasets.filter((dataset) => dataset.legend).flatMap((dataset) => dataset.data)
  return roundedFloor(readings, FLOOR_STEP_W)
}
