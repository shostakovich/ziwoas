import { Controller } from "@hotwired/stimulus"
import "chart.js"
import liveFeed from "controllers/live_feed"

export default class extends Controller {
  static targets = ["canvas"]

  connect() {
    this.chart = null
    this.loadChart()
    this.unsubscribe = liveFeed.subscribe({ onResync: () => this.loadChart() })
  }

  disconnect() {
    this.unsubscribe?.()
    this.chart?.destroy()
  }

  async loadChart() {
    try {
      const response = await fetch("/api/history?days=14")
      if (!response.ok) return
      const data = await response.json()
      this._buildChart(data)
    } catch (e) {
      console.error("history chart load failed:", e)
    }
  }

  _buildChart(data) {
    const producer = data.series.find(s => s.role === "producer")
    if (!producer) return

    const labels = producer.points.map(({ date }) => {
      const [, mm, dd] = date.split("-")
      return `${dd}.${mm}.`
    })
    const values = producer.points.map(p => p.energy_wh / 1000)

    this.chart?.destroy()
    if (!this.hasCanvasTarget) return
    this.chart = new Chart(this.canvasTarget, {
      type: "bar",
      data: {
        labels,
        datasets: [{ label: "kWh/Tag", data: values, backgroundColor: "#f59f00" }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: { y: { beginAtZero: true, title: { display: true, text: "kWh" } } },
        plugins: { legend: { display: false } },
        animation: false,
      },
    })
  }
}
