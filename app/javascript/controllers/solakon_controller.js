import { Controller } from "@hotwired/stimulus"
import "chart.js"
import liveFeed from "controllers/live_feed"
import { EnergyFlowView } from "controllers/energy_flow"

export default class extends Controller {
  static targets = [
    "historyCanvas", "historyPayload", "balanceRows", "energyFlow",
    "epsToggle", "epsState", "epsPower", "epsVoltage", "epsError",
    "autoRegulationToggle", "autoRegulationState", "autoRegulationHelp", "autoRegulationError",
  ]

  connect() {
    this.chart = null
    this.currentRange = "24h"
    this._buildChart(this._readPayload())
    this.flowView = this.hasEnergyFlowTarget ? new EnergyFlowView(this.energyFlowTarget) : null

    this.unsubscribe = liveFeed.subscribe({
      onState: ({ energyFlow, stale }) => {
        this.element.classList.toggle("live-stale", stale)
        this.flowView?.render(energyFlow)
      },
      onResync: () => this.refreshHistory(),
    })

    this.historyInterval = setInterval(() => this.refreshHistory(), 60_000)
  }

  disconnect() {
    this.unsubscribe?.()
    clearInterval(this.historyInterval)
    this.chart?.destroy()
  }

  async selectRange(event) {
    const range = event.currentTarget.dataset.solakonRangeParam
    this.currentRange = range
    try {
      const response = await fetch(`/solakon/history.json?range=${encodeURIComponent(range)}`)
      if (!response.ok) return
      const payload = await response.json()
      this.element.querySelectorAll(".preset-link").forEach((button) => button.classList.toggle("active", button === event.currentTarget))
      this._buildChart(payload)
      this._renderBalanceRows(payload.balance_rows || [])
    } catch (error) {
      console.error("solakon history load failed:", error)
    }
  }

  async refreshHistory() {
    const activeButton = this.element.querySelector(".preset-link.active")
    const range = activeButton?.dataset.solakonRangeParam || this.currentRange || "24h"
    try {
      const response = await fetch(`/solakon/history.json?range=${encodeURIComponent(range)}`)
      if (!response.ok) return
      const payload = await response.json()
      this._buildChart(payload)
      this._renderBalanceRows(payload.balance_rows || [])
    } catch (error) {
      console.error("solakon history refresh failed:", error)
    }
  }

  async toggleEps(event) {
    const desired = event.target.checked
    this._hideError(this.epsErrorTarget)
    try {
      const response = await fetch("/solakon/eps", {
        method: "PATCH",
        headers: this._jsonHeaders(),
        body: JSON.stringify({ enabled: desired }),
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Schalten fehlgeschlagen")
      this.epsStateTarget.textContent = data.enabled ? "An" : "Aus"
      event.target.checked = data.enabled
    } catch (error) {
      event.target.checked = !desired
      this._showError(this.epsErrorTarget, error.message)
    }
  }

  async toggleAutoRegulation(event) {
    const desired = event.target.checked
    this._hideError(this.autoRegulationErrorTarget)
    try {
      const response = await fetch("/solakon/auto_regulation", {
        method: "PATCH",
        headers: this._jsonHeaders(),
        body: JSON.stringify({ active: desired }),
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Umschalten fehlgeschlagen")
      event.target.checked = data.active
      this.autoRegulationStateTarget.textContent = data.active ? "Aktiv" : "Pausiert"
      this.autoRegulationHelpTarget.textContent = data.active ? "hält Einspeisung nahe 0 W" : "pausiert"
    } catch (error) {
      event.target.checked = !desired
      this._showError(this.autoRegulationErrorTarget, error.message)
    }
  }

  _readPayload() {
    try {
      return JSON.parse(this.historyPayloadTarget.textContent)
    } catch (error) {
      return { chart: { labels: [], datasets: [] }, balance_rows: [] }
    }
  }

  _buildChart(payload) {
    if (!this.hasHistoryCanvasTarget) return
    const chart = payload?.chart || { labels: [], datasets: [] }
    const colors = { "PV": "#f59f00", "Akku": "#14b8a6", "Außensteckdose": "#3b82f6", "0 W": "#6c757d" }
    const datasets = (chart.datasets || []).map((dataset) => ({
      label: dataset.label,
      data: dataset.data,
      borderColor: colors[dataset.label] || "#6c757d",
      backgroundColor: dataset.label === "PV" ? "rgba(245,159,0,0.14)" : "transparent",
      borderDash: dataset.label === "0 W" ? [4, 4] : [],
      fill: dataset.label === "PV",
      pointRadius: 0,
      tension: 0.2,
    }))

    this.chart?.destroy()
    this.chart = new Chart(this.historyCanvasTarget, {
      type: "line",
      data: { labels: chart.labels || [], datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: { y: { title: { display: true, text: "Watt" } } },
        plugins: { legend: { position: "bottom", labels: { boxWidth: 12, boxHeight: 12, padding: 10, font: { size: 12 } } } },
        animation: false,
      },
    })
  }

  _renderBalanceRows(rows) {
    if (!this.hasBalanceRowsTarget) return
    this.balanceRowsTarget.innerHTML = rows.map((row) => `
      <div class="solakon-balance-row ${row.role}">
        <span class="solakon-balance-label">${row.label}</span>
        <span class="report-ranking-bar" aria-hidden="true"><span style="width: ${row.share}%"></span></span>
        <span class="report-ranking-value">${row.value}</span>
      </div>
    `).join("")
  }

  _jsonHeaders() {
    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content,
    }
  }

  _showError(target, message) {
    target.textContent = message
    target.hidden = false
  }

  _hideError(target) {
    target.textContent = ""
    target.hidden = true
  }
}
