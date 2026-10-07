import { renderChart, timeCategoryScale, localMidnight } from "../lib/chart_theme.js"
import { RESYNC_EVENT } from "./live_freshness.js"

// The dashboard's 14-day yield: loaded from /api/history, again on a resync.
export default {
  mounted() {
    this.chart = null
    this.load()
    this.onResync = () => this.load()
    document.addEventListener(RESYNC_EVENT, this.onResync)
  },

  destroyed() {
    document.removeEventListener(RESYNC_EVENT, this.onResync)
    this.chart?.destroy()
  },

  async load() {
    try {
      const response = await fetch("/api/history?days=14")
      if (!response.ok) return
      const producer = (await response.json()).series.find((s) => s.role === "producer")
      if (!producer) return
      this.chart = renderChart(this.chart, this.el.querySelector("canvas"), config(producer))
    } catch (e) {
      console.error("history chart load failed:", e)
    }
  },
}

function config(producer) {
  const labels = producer.points.map(({ date }) => {
    const [, mm, dd] = date.split("-")
    return `${dd}.${mm}.`
  })

  return {
    type: "bar",
    data: {
      labels,
      datasets: [{ label: "Ertrag", data: producer.points.map((p) => p.energy_wh / 1000), tone: "--viz-solar" }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: timeCategoryScale(producer.points.map(({ date }) => localMidnight(date))),
        y: { beginAtZero: true, unit: "kWh", decimals: 2 },
      },
      plugins: { legend: { display: false } },
      animation: false,
    },
  }
}
