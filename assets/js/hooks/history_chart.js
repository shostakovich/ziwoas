import { renderChart, timeCategoryScale, localMidnight } from "../lib/chart_theme.js"

export default {
  mounted() {
    this.chart = null
    this.draw()
  },

  updated() {
    this.draw()
  },

  destroyed() {
    this.chart?.destroy()
  },

  draw() {
    const points = JSON.parse(this.el.dataset.payload)
    this.chart = renderChart(this.chart, this.el.querySelector("canvas"), config(points))
  },
}

function config(points) {
  const times = points.map(({ date }) => localMidnight(date))

  return {
    type: "bar",
    data: {
      labels: points.map(({ date }) => dayMonth(date)),
      datasets: [ { label: "Ertrag", data: points.map((point) => point.energy_wh / 1000), tone: "--color-solar" } ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: timeCategoryScale(times),
        y: { beginAtZero: true, unit: "kWh", decimals: 2 },
      },
      plugins: { legend: { display: false } },
      animation: false,
    },
  }
}

function dayMonth(isoDate) {
  const [ , month, day ] = isoDate.split("-")
  return `${day}.${month}.`
}
