import { renderChart, AREA_ALPHA, timeCategoryScale, roundedFloor, dropOffStepBound, formatTime } from "../lib/chart_theme.js"

// A night's standby dips a few watts below zero: end on the next hundred, not a whole tick step.
const FLOOR_STEP_W = 100
const SERIES = {
  pv: { tone: "--color-solar", fillAlpha: AREA_ALPHA, fill: "origin" },
  battery: { tone: "--color-battery", flowWords: { positive: "lädt", negative: "entlädt" } },
  outlet: { tone: "--color-grid", flowWords: { positive: "liefert", negative: "zieht" } },
}

export default {
  mounted() {
    this.draw()
  },

  updated() {
    this.draw()
  },

  destroyed() {
    this.chart?.destroy()
  },

  draw() {
    const { chart, range } = this.el.dataset
    if (!chart || (chart === this.drawn && range === this.range)) return
    this.drawn = chart
    this.range = range
    this.chart = renderChart(this.chart, this.el.querySelector("canvas"), config(JSON.parse(chart), range))
  },
}

function config(chart, range) {
  const times = chart.times || []
  const series = (chart.datasets || []).map((dataset) => ({
    label: dataset.label,
    data: dataset.data,
    fillAlpha: 0,
    fill: false,
    ...SERIES[dataset.key],
    borderWidth: 2,
    pointRadius: 0,
    tension: 0.2,
  }))
  const zero = {
    label: "0 W",
    data: times.map(() => 0),
    tone: "--color-chart-muted",
    fillAlpha: 0,
    borderDash: [ 4, 4 ],
    borderWidth: 1,
    pointRadius: 0,
    legend: false,
  }

  return {
    type: "line",
    data: { labels: times, datasets: [ ...series, zero ] },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: timeCategoryScale(times),
        y: { unit: "W", min: roundedFloor(series.flatMap((dataset) => dataset.data), FLOOR_STEP_W), afterBuildTicks: dropOffStepBound },
      },
      plugins: {
        legend: { display: false },
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
