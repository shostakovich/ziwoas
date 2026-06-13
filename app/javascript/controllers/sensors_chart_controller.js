// app/javascript/controllers/sensors_chart_controller.js
import { Controller } from "@hotwired/stimulus"
import "chart.js"

// Connects to data-controller="sensors-chart"
// Builds three line charts (temperature, humidity, CO2) of the last 24h.
// Refreshes every 15 minutes; reloads on visibility change and bfcache restore.
export default class extends Controller {
  static targets = ["temperature", "humidity", "co2"]
  static values  = {
    url:             String,
    refreshInterval: { type: Number, default: 900_000 }, // 15 min
  }

  connect() {
    this.charts = {}
    this.load()
    this.refreshTimer = setInterval(() => this.load(), this.refreshIntervalValue)
    this._onVisibility = () => { if (document.visibilityState === "visible") this.load() }
    document.addEventListener("visibilitychange", this._onVisibility)
    this._onPageShow = (e) => { if (e.persisted) this.load() }
    window.addEventListener("pageshow", this._onPageShow)
  }

  disconnect() {
    clearInterval(this.refreshTimer)
    document.removeEventListener("visibilitychange", this._onVisibility)
    window.removeEventListener("pageshow", this._onPageShow)
    Object.values(this.charts).forEach(c => c?.destroy())
    this.charts = {}
  }

  async load() {
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!res.ok) return
      const data = await res.json()
      this._render("temperature", this.temperatureTarget, data.temperature, "°C")
      this._render("humidity",    this.humidityTarget,    data.humidity,    "%")
      this._renderCo2(this.co2Target, data.co2)
    } catch (e) {
      console.error("sensors-chart load failed:", e)
    }
  }

  _render(key, canvas, series, unit) {
    if (!canvas) return
    const xBounds = this._xBounds(series)
    const datasets = series.map((s, i) => ({
      label: s.name,
      data:  s.points.map(([x, y]) => ({ x, y })),
      borderColor:     this._color(i),
      backgroundColor: this._color(i, 0.15),
      tension: 0.25,
      borderWidth: 2,
      pointRadius: 0,
    }))
    this.charts[key]?.destroy()
    this.charts[key] = new Chart(canvas, {
      type: "line",
      data: { datasets },
      options: this._opts(unit, xBounds),
    })
  }

  _renderCo2(canvas, series) {
    if (!canvas) return
    const xBounds = this._xBounds(series)
    const datasets = series.map((s, i) => ({
      label: s.name,
      data:  s.points.map(([x, y]) => ({ x, y })),
      borderColor:     this._color(i),
      backgroundColor: this._color(i, 0.15),
      tension: 0.25,
      borderWidth: 2,
      pointRadius: 0,
    }))
    datasets.push(this._thresholdLine(xBounds, 1000, "#fbbf24"))
    datasets.push(this._thresholdLine(xBounds, 1400, "#ef4444"))
    this.charts.co2?.destroy()
    this.charts.co2 = new Chart(canvas, {
      type: "line",
      data: { datasets },
      options: this._opts("ppm", xBounds),
    })
  }

  _thresholdLine(xBounds, value, color) {
    const data = xBounds ? [ { x: xBounds.min, y: value }, { x: xBounds.max, y: value } ] : []
    return {
      label: `${value} ppm`,
      data,
      borderColor:   color,
      borderDash:    [ 4, 4 ],
      borderWidth:   1,
      pointRadius:   0,
      fill: false,
      tension: 0,
    }
  }

  _opts(unit, xBounds) {
    const xScale = {
      type: "linear",
      ticks: {
        maxTicksLimit: 8,
        callback: (value) => {
          const d = new Date(value)
          return d.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" })
        },
      },
    }
    if (xBounds) {
      xScale.min = xBounds.min
      xScale.max = xBounds.max
    }

    return {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      scales: {
        x: xScale,
        y: { title: { display: true, text: unit } },
      },
      plugins: {
        legend: { position: "bottom" },
        tooltip: {
          callbacks: {
            title: (items) => {
              if (!items.length) return ""
              const d = new Date(items[0].parsed.x)
              return d.toLocaleString("de-DE", {
                weekday: "short", hour: "2-digit", minute: "2-digit"
              })
            },
          },
        },
      },
    }
  }

  _xBounds(series) {
    const xs = series.flatMap((s) => s.points.map((p) => p[0]))
    if (xs.length === 0) return null
    return { min: Math.min(...xs), max: Math.max(...xs) }
  }

  _color(i, alpha = 1) {
    const palette = [
      `rgba(37, 99, 235, ${alpha})`,
      `rgba(16, 185, 129, ${alpha})`,
      `rgba(217, 70, 239, ${alpha})`,
    ]
    return palette[i % palette.length]
  }
}
