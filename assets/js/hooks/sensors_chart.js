import { renderChart, tonesByOrder, OTHER_TONE, timeScale, timeTooltipTitle, thresholdLine } from "../lib/chart_theme.js"

const CO2_LINES = [
  { name: "Lüften", tone: "--color-chart-2", textTone: "--color-warning-ink" },
  { name: "Grenzwert", tone: "--color-chart-4", textTone: "--color-error-ink" },
]
// Room for the top threshold's label on a tick a phone's 500-step axis shares (1.400 × 1.1 rounds up to 2.000).
const CO2_AXIS_TOP = 1500
const UNITS = { temperature: "°C", humidity: "%", co2: "ppm" }
const DECIMALS = { temperature: 1, humidity: 0, co2: 0 }
// A temperature has no natural zero: 0 °C would flatten the indoor swing.
const FROM_ZERO = { temperature: false, humidity: true, co2: true }

// One instance per chart card; data-series names the quantity it draws.
export default {
  mounted() {
    this.handleEvent("sensors_chart:data", (data) => this.render(data))
  },

  destroyed() {
    this.chart?.destroy()
    this.chart = null
  },

  render(data) {
    const key = this.el.dataset.series
    const series = data[key]
    const canvas = this.el.querySelector("canvas")
    if (!series || !canvas) return
    // The order of all sensors, so each keeps its colour on every chart.
    const tones = tonesByOrder(data.temperature.map((s) => s.device_id), [ "warning", "danger" ])
    const xBounds = bounds(series)
    const thresholds = key === "co2" ? data.co2_thresholds.map((value, i) => thresholdLine(xBounds, { ...CO2_LINES[i], value })) : []
    const options = chartOptions(key, xBounds)
    if (key === "co2") options.scales.y.suggestedMax = CO2_AXIS_TOP
    this.chart = renderChart(this.chart, canvas, {
      type: "line",
      data: { datasets: [ ...datasets(series, tones), ...thresholds ] },
      options,
    })
  },
}

function datasets(series, tones) {
  return series.map((s) => ({
    label: s.name,
    data: s.points.map(([ x, y ]) => ({ x, y })),
    tone: tones.get(s.device_id) ?? OTHER_TONE,
    tension: 0.25,
    borderWidth: 2,
    pointRadius: 0,
  }))
}

function chartOptions(key, xBounds) {
  return {
    responsive: true,
    maintainAspectRatio: false,
    animation: false,
    interaction: { mode: "nearest", axis: "x", intersect: false },
    scales: {
      x: xBounds ? timeScale(xBounds.min, xBounds.max) : { type: "linear" },
      y: { beginAtZero: FROM_ZERO[key], unit: UNITS[key], decimals: DECIMALS[key] },
    },
    plugins: {
      legend: { display: false },
      tooltip: {
        filter: (item) => !item.dataset.endLabel,
        callbacks: { title: timeTooltipTitle({ weekday: "short", hour: "2-digit", minute: "2-digit" }) },
      },
    },
  }
}

function bounds(series) {
  const xs = series.flatMap((s) => s.points.map((p) => p[0]))
  if (xs.length === 0) return null
  return { min: Math.min(...xs), max: Math.max(...xs) }
}
