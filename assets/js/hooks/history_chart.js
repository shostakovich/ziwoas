import { renderChart, timeCategoryScale, localMidnight } from "../lib/chart_theme.js"

// The dashboard's 14-day yield, pushed as "history_chart:data" once connected, after the
// nightly aggregation and at midnight. Without a producer there is nothing to draw.
export default {
  mounted() {
    this.chart = null
    this.handleEvent("history_chart:data", ({ points }) => {
      if (points) this.chart = renderChart(this.chart, this.el.querySelector("canvas"), config(points))
    })
  },

  destroyed() {
    this.chart?.destroy()
  },
}

function config(points) {
  const labels = points.map(({ date }) => {
    const [, mm, dd] = date.split("-")
    return `${dd}.${mm}.`
  })

  return {
    type: "bar",
    data: {
      labels,
      datasets: [{ label: "Ertrag", data: points.map((p) => p.energy_wh / 1000), tone: "--viz-solar" }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: timeCategoryScale(points.map(({ date }) => localMidnight(date))),
        y: { beginAtZero: true, unit: "kWh", decimals: 2 },
      },
      plugins: { legend: { display: false } },
      animation: false,
    },
  }
}
