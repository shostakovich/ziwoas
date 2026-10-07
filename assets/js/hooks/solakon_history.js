import { renderChart, timeCategoryScale, roundedFloor, dropOffStepBound, formatTime } from "../lib/chart_theme.js"

// A night's standby dips a few watts below zero: end on the next hundred, not a whole tick step.
const FLOOR_STEP_W = 100
const SERIES_TOKENS = { "PV": "--viz-solar", "Akku": "--viz-battery", "Außensteckdose": "--viz-grid", "0 W": "--viz-muted" }
const FLOW_WORDS = {
  "Akku": { positive: "lädt", negative: "entlädt" },
  "Außensteckdose": { positive: "liefert", negative: "zieht" },
}

// The Solakon-Verlauf: the LiveView re-renders the payload island on a range tab and on
// its minute refresh; the chart follows in place whenever the payload or range changed.
export default {
  mounted() {
    this.render()
  },

  updated() {
    this.render()
  },

  destroyed() {
    this.chart?.destroy()
  },

  render() {
    const payload = this.el.querySelector("script[data-chart-payload]")?.textContent ?? ""
    const range = this.el.dataset.range
    if (this.chart && payload === this.payload && range === this.range) return
    this.payload = payload
    this.range = range
    this.chart = renderChart(this.chart, this.el.querySelector("canvas"), config(parse(payload), range))
  },
}

function parse(text) {
  try {
    return JSON.parse(text)
  } catch {
    return { times: [], datasets: [] }
  }
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
