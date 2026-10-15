import { renderChart, AREA_ALPHA, timeScale, timeCategoryScale, timeTooltipTitle, formatTime, lineElements } from "../lib/chart_theme.js"
import { consumerSeries } from "../lib/consumer_series.js"

const GAP_THRESHOLD_MS = 120_000
const WINDOW_MS = 86_400_000

export default {
  mounted() {
    this.chart = null
    this.datasetIndex = {}
    if (this.isPower()) this.handleEvent("today_chart:deltas", ({ deltas }) => this.applyDeltas(deltas))
    this.draw()
  },

  updated() {
    this.draw()
  },

  destroyed() {
    this.chart?.destroy()
  },

  isPower() {
    return this.el.dataset.chart === "power"
  },

  draw() {
    const data = JSON.parse(this.el.dataset.payload)
    const config = this.isPower() ? this.powerConfig(data) : energyConfig(data)
    this.chart = renderChart(this.chart, this.el.querySelector("canvas"), config)
  },

  applyDeltas(updates) {
    if (!this.chart) return

    let changed = false
    for (const plug of updates) changed = this.appendDelta(plug) || changed

    if (changed) {
      this.replaceTotalConsumption()
      const now = Date.now()
      Object.assign(this.chart.options.scales.x, { min: now - WINDOW_MS, max: now })
      this.chart.update("none")
    }
  },

  appendDelta(data) {
    const idx = this.datasetIndex[data.id]
    if (idx === undefined) return false

    const dataset = this.chart.data.datasets[idx]
    const last = dataset.data.at(-1)
    const x = data.bucket_ts * 1000
    const y = data.avg_power_w

    if (!last) {
      dataset.data.push({ x, y })
    } else if (x - last.x > GAP_THRESHOLD_MS) {
      // The plug was silent: a null point breaks the line instead of bridging the gap.
      dataset.data.push({ x: last.x + 1, y: null }, { x, y })
    } else if (last.x === x) {
      last.y = y
    } else {
      dataset.data.push({ x, y })
      const cutoff = Date.now() - 25 * 3_600_000
      while (dataset.data.length > 0 && dataset.data[0].x < cutoff) dataset.data.shift()
    }
    return true
  },

  powerConfig(data) {
    this.datasetIndex = {}

    const datasets = data.series.map((series, index) => {
      this.datasetIndex[series.plug_id] = index
      const producer = series.role === "producer"
      return {
        label: series.name,
        data: series.points.map(([ ts, watts ]) => ({ x: ts * 1000, y: watts })),
        role: series.role,
        tension: 0.2,
        fill: producer,
        pointRadius: 0,
        hidden: !producer,
        tone: producer ? "--color-solar" : undefined,
        ...(producer ? { fillAlpha: AREA_ALPHA } : {}),
      }
    })
    const total = totalConsumption(datasets)
    if (total) datasets.push(total)

    return {
      type: "line",
      data: { datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        elements: lineElements(),
        scales: {
          x: timeScale(Date.now() - WINDOW_MS, Date.now()),
          y: { beginAtZero: true, unit: "W" },
        },
        plugins: {
          legend: { display: false },
          tooltip: { callbacks: { title: timeTooltipTitle({ hour: "2-digit", minute: "2-digit" }) } },
        },
        animation: false,
      },
    }
  },

  replaceTotalConsumption() {
    const datasets = this.chart.data.datasets
    const existing = datasets.find((dataset) => dataset.isTotalConsumption)
    const fresh = totalConsumption(datasets.filter((dataset) => !dataset.isTotalConsumption))

    if (existing && fresh) existing.data = fresh.data
    else if (fresh) datasets.push(fresh)
    else if (existing) datasets.splice(datasets.indexOf(existing), 1)
  },
}

function energyConfig(data) {
  const consumed = consumerSeries(data.consumers, (consumer) => consumer.kwh, data.consumer_order)
    .map((series) => ({ ...series, stack: "consumed" }))

  return {
    type: "bar",
    data: {
      labels: data.hours.map((ms) => formatTime(ms, { hour: "2-digit", minute: "2-digit" })),
      datasets: [ { label: "Erzeugt", data: data.produced_kwh, tone: "--color-solar", stack: "produced" }, ...consumed ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: { stacked: true, ...timeCategoryScale(data.hours) },
        y: { stacked: true, beginAtZero: true, unit: "kWh", decimals: 2 },
      },
      plugins: { legend: { display: false } },
      animation: false,
    },
  }
}

function totalConsumption(datasets) {
  const consumers = datasets.filter((dataset) => dataset.role === "consumer")
  if (consumers.length === 0) return null

  const pointsByTs = new Map()
  for (const dataset of consumers) {
    for (const point of dataset.data) {
      if (point.y !== null) pointsByTs.set(point.x, (pointsByTs.get(point.x) || 0) + point.y)
    }
  }

  return {
    label: "Gesamtverbrauch",
    data: Array.from(pointsByTs.entries()).sort(([ a ], [ b ]) => a - b).map(([ x, y ]) => ({ x, y })),
    tone: "--color-chart-total",
    fill: false,
    pointRadius: 0,
    tension: 0.2,
    role: "consumer_total",
    isTotalConsumption: true,
  }
}
