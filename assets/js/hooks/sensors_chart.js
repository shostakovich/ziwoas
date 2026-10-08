import { renderChart, vizToken, tonesByOrder, timeScale, timeTooltipTitle, thresholdLine } from "../lib/chart_theme.js"

const CO2_LINES = [
  { name: "Lüften", tone: "--felt-warning", textTone: "--felt-warning-text" },
  { name: "Grenzwert", tone: "--felt-danger", textTone: "--felt-danger-text" },
]
// Room for the top threshold's label on a tick a phone's 500-step axis shares (1.400 × 1.1 rounds up to 2.000).
const CO2_AXIS_TOP = 1500
const DECIMALS = { "°C": 1, "%": 0, "ppm": 0 }
// A temperature has no natural zero: 0 °C would flatten the indoor swing.
const FROM_ZERO = { "°C": false, "%": true, "ppm": true }

export default {
  mounted() {
    this.charts = {}
    this.handleEvent("sensors_chart:data", (data) => this.renderAll(data))
  },

  destroyed() {
    Object.values(this.charts).forEach((chart) => chart.destroy())
    this.charts = {}
  },

  renderAll(data) {
    const tones = tonesByOrder(data.temperature.map((s) => s.device_id))
    this.render("temperature", data.temperature, tones, "°C")
    this.render("humidity", data.humidity, tones, "%")
    const thresholds = data.co2_thresholds.map((value, i) => ({ ...CO2_LINES[i], value }))
    this.render("co2", data.co2, tones, "ppm", { thresholds, suggestedMax: CO2_AXIS_TOP })
  },

  render(key, series, tones, unit, { thresholds = [], suggestedMax } = {}) {
    const canvas = this.el.querySelector(`canvas[data-series="${key}"]`)
    if (!canvas) return
    const xBounds = bounds(series)
    const options = chartOptions(unit, xBounds, series.length)
    if (suggestedMax !== undefined) options.scales.y.suggestedMax = suggestedMax
    this.charts[key] = renderChart(this.charts[key], canvas, {
      type: "line",
      data: { datasets: [ ...datasets(series, tones), ...thresholds.map((line) => thresholdLine(xBounds, line)) ] },
      options,
    })
  },
}

function datasets(series, tones) {
  return series.map((s) => ({
    label: s.name,
    data: s.points.map(([x, y]) => ({ x, y })),
    tone: tones.get(s.device_id) ?? vizToken(0),
    fillAlpha: 0.15,
    tension: 0.25,
    borderWidth: 2,
    pointRadius: 0,
  }))
}

function chartOptions(unit, xBounds, seriesCount) {
  return {
    responsive: true,
    maintainAspectRatio: false,
    animation: false,
    scales: {
      x: xBounds ? timeScale(xBounds.min, xBounds.max) : { type: "linear" },
      y: { beginAtZero: FROM_ZERO[unit] ?? true, unit, decimals: DECIMALS[unit] ?? 0 },
    },
    plugins: {
      legend: { display: seriesCount > 1, position: "bottom" },
      tooltip: { callbacks: { title: timeTooltipTitle({ weekday: "short", hour: "2-digit", minute: "2-digit" }) } },
    },
  }
}

function bounds(series) {
  const xs = series.flatMap((s) => s.points.map((p) => p[0]))
  if (xs.length === 0) return null
  return { min: Math.min(...xs), max: Math.max(...xs) }
}
