import { renderChart, tonesByOrder, timeScale, timeCategoryScale, timeTooltipTitle, formatTime, lineElements } from "../lib/chart_theme.js"

// Below this an hour's yield is the inverter's night-time noise, not production.
const MIN_PRODUCED_KWH = 0.02
const GAP_THRESHOLD_MS = 120_000

// The dashboard's 24 h charts. The LiveView pushes "today_chart:data" once connected and
// every hour, as the window slides; in between "today_chart:deltas" extend the power chart
// in place.
export default {
  mounted() {
    this.powerChart = null
    this.energyChart = null
    this.datasetIndex = {}

    this.handleEvent("today_chart:data", (data) => this.draw(data))
    this.handleEvent("today_chart:deltas", ({ deltas }) => this.applyDeltas(deltas))
  },

  destroyed() {
    this.powerChart?.destroy()
    this.energyChart?.destroy()
  },

  canvas(name) {
    return this.el.querySelector(`canvas[data-chart="${name}"]`)
  },

  draw(data) {
    const tones = tonesByOrder(data.series.filter((s) => s.role === "consumer").map((s) => s.plug_id))
    this.powerChart = renderChart(this.powerChart, this.canvas("power"), this.powerConfig(data, tones))
    this.energyChart = renderChart(this.energyChart, this.canvas("energy"), this.energyConfig(data, tones))
  },

  applyDeltas(updates) {
    if (!this.powerChart) return

    let changed = false
    for (const plug of updates) changed = this.appendDelta(plug) || changed

    if (changed) {
      this.replaceTotalConsumption()
      this.powerChart.update("none")
    }
  },

  appendDelta(data) {
    const idx = this.datasetIndex[data.id]
    if (idx === undefined) return false

    const dataset = this.powerChart.data.datasets[idx]
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

  powerConfig(data, tones) {
    this.datasetIndex = {}

    const datasets = data.series.map((s, i) => {
      this.datasetIndex[s.plug_id] = i
      const isProducer = s.role === "producer"
      return {
        label: s.name,
        data: s.points.map((pt) => ({ x: pt.ts * 1000, y: pt.avg_power_w })),
        role: s.role,
        tension: 0.2,
        fill: isProducer,
        pointRadius: 0,
        hidden: !isProducer,
        tone: isProducer ? "--viz-solar" : tones.get(s.plug_id),
        ...(isProducer ? { fillAlpha: 0.12 } : {}),
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
          x: timeScale(Date.now() - 86_400_000, Date.now()),
          y: { beginAtZero: true, unit: "W" },
        },
        plugins: {
          legend: { position: "bottom" },
          tooltip: { callbacks: { title: timeTooltipTitle({ hour: "2-digit", minute: "2-digit" }) } },
        },
        animation: false,
      },
    }
  },

  energyConfig(data, tones) {
    const consumers = data.series.filter((series) => series.role === "consumer")
    const buckets = {}
    for (const series of data.series) {
      for (const pt of series.points) {
        const hourKey = Math.floor(pt.ts / 3600) * 3600
        const wh = pt.avg_power_w / 60
        buckets[hourKey] ||= { produced: 0, consumers: {} }
        if (series.role === "producer") {
          buckets[hourKey].produced += wh
        } else {
          buckets[hourKey].consumers[series.plug_id] ||= 0
          buckets[hourKey].consumers[series.plug_id] += wh
        }
      }
    }
    const sorted = Object.keys(buckets).map(Number).sort((a, b) => a - b)
    const labels = sorted.map((ts) => formatTime(ts * 1000, { hour: "2-digit", minute: "2-digit" }))
    const produced = sorted.map((ts) => {
      const kwh = buckets[ts].produced / 1000
      return kwh < MIN_PRODUCED_KWH ? 0 : +kwh.toFixed(3)
    })

    return {
      type: "bar",
      data: {
        labels,
        datasets: [
          { label: "Erzeugt", data: produced, tone: "--viz-solar", stack: "produced" },
          ...topConsumerDatasets(consumers, sorted, buckets, tones, 5),
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: { stacked: true, ...timeCategoryScale(sorted.map((ts) => ts * 1000)) },
          y: { stacked: true, beginAtZero: true, unit: "kWh", decimals: 2 },
        },
        plugins: { legend: { position: "bottom" } },
        animation: false,
      },
    }
  },

  replaceTotalConsumption() {
    const datasets = this.powerChart.data.datasets
    const existing = datasets.find((d) => d.isTotalConsumption)
    const fresh = totalConsumption(datasets.filter((d) => !d.isTotalConsumption))

    if (existing && fresh) existing.data = fresh.data
    else if (fresh) datasets.push(fresh)
    else if (existing) datasets.splice(datasets.indexOf(existing), 1)
  },
}

function topConsumerDatasets(consumers, sorted, buckets, tones, limit) {
  const rows = consumers.map((series) => {
    const data = sorted.map((ts) => +((buckets[ts].consumers[series.plug_id] || 0) / 1000).toFixed(3))
    return { label: series.name, data, tone: tones.get(series.plug_id), total: data.reduce((sum, value) => sum + value, 0) }
  }).sort((a, b) => b.total - a.total)

  const datasets = rows.slice(0, limit).map((row) => ({ label: row.label, data: row.data, tone: row.tone, stack: "consumed" }))
  const rest = rows.slice(limit)
  if (rest.length > 0) {
    datasets.push({
      label: "Weitere Verbraucher",
      data: sorted.map((_, index) => +rest.reduce((sum, row) => sum + row.data[index], 0).toFixed(3)),
      tone: "--viz-muted",
      stack: "consumed",
    })
  }
  return datasets
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
    data: Array.from(pointsByTs.entries()).sort(([a], [b]) => a - b).map(([x, y]) => ({ x, y })),
    tone: "--viz-total",
    fill: false,
    pointRadius: 0,
    tension: 0.2,
    role: "consumer_total",
    isTotalConsumption: true,
  }
}
