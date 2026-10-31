import { renderChart, AREA_ALPHA, timeCategoryScale, localMidnight, isPhone, snugTop, lineElements } from "../lib/chart_theme.js"
import { consumerSeries } from "../lib/consumer_series.js"

const DAILY_ICONS_PADDING = 44
const DETAIL_ICONS_PADDING = 38
const IRRADIANCE_DASH = [ 4, 3 ]
// Thinner than the measured lines, so the weather stays the backdrop.
const IRRADIANCE_WIDTH = 1.25

export default {
  mounted() {
    this.chart = null
    this.imageCache = {}
    this.card = this.el.closest("section")
    this.onChange = (event) => {
      if (event.target.matches("[data-weather-toggle]")) this.toggleWeather(event.target.checked)
    }
    this.card?.addEventListener("change", this.onChange)
    this.load()
  },

  updated() {
    this.load()
  },

  destroyed() {
    this.gone = true
    this.card?.removeEventListener("change", this.onChange)
    this.chart?.destroy()
  },

  weatherEnabled() {
    return !!this.card?.querySelector("[data-weather-toggle]")?.checked
  },

  async load() {
    const payload = JSON.parse(this.el.dataset.payload)
    this.payload = payload
    await this.preloadIcons(payload.weather_assets || {})
    if (this.gone || this.payload !== payload) return

    const config = { daily: () => this.dailyConfig(payload), detail: () => this.detailConfig(payload), ratios: () => ratiosConfig(payload) }
    this.chart = renderChart(this.chart, this.el.querySelector("canvas"), config[this.el.dataset.chart]())
  },

  preloadIcons(assets) {
    const names = Object.keys(assets).filter((name) => !this.imageCache[name])
    return Promise.all(names.map((name) => new Promise((resolve) => {
      const img = new Image()
      img.onload = () => { this.imageCache[name] = img; resolve() }
      img.onerror = () => resolve()
      img.src = assets[name]
    })))
  },

  toggleWeather(visible) {
    const chart = this.chart
    if (!chart) return
    chart.data.datasets.forEach((dataset, index) => {
      if (dataset._isSolar) chart.setDatasetVisibility(index, visible)
    })
    const icons = chart.options._weatherIcons
    if (icons) {
      icons.enabled = visible
      if (chart.options.scales?.x?.ticks) chart.options.scales.x.ticks.padding = visible ? icons.paddingOn ?? 0 : 0
    }
    if (chart.options.scales?.ySolar) chart.options.scales.ySolar.display = visible
    chart.update()
  },

  weatherIconsPlugin() {
    const cache = this.imageCache
    return {
      id: "weatherIcons",
      afterDatasetsDraw(chart) {
        const cfg = chart.options._weatherIcons
        if (!cfg || !cfg.enabled) return
        const icons = cfg.icons || []
        const xScale = chart.scales.x
        if (icons.length === 0 || !xScale) return
        const { ctx, chartArea } = chart
        const size = cfg.size || 22
        // The icons sit in the gap opened by scales.x.ticks.padding.
        const y = chartArea.bottom + (cfg.gap ?? 14) + (size / 2)
        ctx.save()
        icons.forEach((icon) => {
          const img = cache[icon.asset_name]
          const x = xScale.getPixelForValue(icon.label_index)
          if (img && x != null) ctx.drawImage(img, x - size / 2, y - size / 2, size, size)
        })
        ctx.restore()
      },
    }
  },

  dailyConfig(daily) {
    const enabled = this.weatherEnabled()
    const consumers = daily.consumer_series || []
    const datasets = [
      { label: "Ertrag", data: daily.produced_kwh || [], tone: "--color-solar", stack: "produced" },
      ...(consumers.length > 0
        ? consumerSeries(consumers, (series) => series.data || [], daily.consumer_order).map((series) => ({ ...series, stack: "consumed" }))
        : [ { label: "Verbrauch", data: daily.consumed_kwh || [], tone: "--color-consumption", stack: "consumed" } ]),
    ]

    const w = daily.weather
    const hasIcons = w && Array.isArray(w.icons) && w.icons.length > 0
    const timeAxis = timeCategoryScale((daily.ratios || []).map((r) => localMidnight(r.date)))
    const scales = {
      x: {
        stacked: true,
        ...timeAxis,
        ticks: { ...timeAxis.ticks, padding: hasIcons && enabled ? DAILY_ICONS_PADDING : 0 },
        afterFit: trimXScale,
      },
      y: { stacked: true, beginAtZero: true, unit: "kWh", decimals: 2 },
    }

    if (w && Array.isArray(w.solar_kwh_per_m2)) {
      datasets.push({
        type: "line",
        label: "Einstrahlung",
        data: w.solar_kwh_per_m2,
        yAxisID: "ySolar",
        tone: "--color-solar",
        borderDash: IRRADIANCE_DASH,
        borderWidth: IRRADIANCE_WIDTH,
        pointRadius: 3,
        tension: 0.2,
        spanGaps: true,
        order: 0,
        hidden: !enabled,
        _isSolar: true,
      })
      scales.ySolar = solarScale("kWh/m²", enabled, { decimals: 2 })
    }

    const icons = hasIcons
      ? w.icons.map((icon, idx) => icon ? { label_index: idx, asset_name: icon.asset_name } : null).filter(Boolean)
      : []

    return {
      type: "bar",
      data: { labels: daily.labels || [], datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales,
        plugins: { legend: { display: false } },
        animation: false,
        _weatherIcons: { enabled, icons, size: 32, gap: 8, paddingOn: DAILY_ICONS_PADDING },
      },
      plugins: [ this.weatherIconsPlugin() ],
    }
  },

  detailConfig(detail) {
    return detail.chart_type === "bar" ? dailyPowerBarConfig(detail) : this.powerLineConfig(detail)
  },

  powerLineConfig(detail) {
    const enabled = this.weatherEnabled()
    const datasets = (detail.series || []).map((series) => {
      const producer = series.role === "producer"
      return {
        label: series.name,
        data: series.data,
        tone: producer ? "--color-solar" : undefined,
        fill: producer,
        fillAlpha: producer ? AREA_ALPHA : undefined,
        tension: 0.2,
        pointRadius: 0,
        hidden: !producer,
      }
    })
    const total = totalConsumption(detail.series || [])
    if (total) datasets.push(total)

    const w = detail.weather
    const hasIcons = w && Array.isArray(w.icons) && w.icons.length > 0
    const timeAxis = timeCategoryScale(detail.times || [])
    const scales = {
      x: { ...timeAxis, ticks: { ...timeAxis.ticks, padding: hasIcons && enabled ? DETAIL_ICONS_PADDING : 0 }, afterFit: trimXScale },
      // A phone's few value ticks would leave a third of the plot empty.
      y: { beginAtZero: true, unit: "W", ...(isPhone() ? snugTop(datasets.flatMap((dataset) => dataset.data || []), 3) : {}) },
    }

    if (w && Array.isArray(w.solar_w_per_m2)) {
      datasets.push({
        label: "Einstrahlung",
        data: w.solar_w_per_m2,
        yAxisID: "ySolar",
        tone: "--color-solar",
        borderDash: IRRADIANCE_DASH,
        borderWidth: IRRADIANCE_WIDTH,
        stepped: "before",
        fill: false,
        pointRadius: 0,
        spanGaps: true,
        hidden: !enabled,
        _isSolar: true,
      })
      scales.ySolar = solarScale("W/m²", enabled)
    }

    return {
      type: "line",
      data: { labels: detail.labels || [], datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        elements: lineElements(),
        scales,
        plugins: { legend: { display: false } },
        animation: false,
        _weatherIcons: { enabled, icons: hasIcons ? w.icons : [], size: 28, gap: 8, paddingOn: DETAIL_ICONS_PADDING },
      },
      plugins: [ this.weatherIconsPlugin() ],
    }
  },
}

function solarScale(unit, display, extra = {}) {
  return { position: "right", beginAtZero: true, grid: { drawOnChartArea: false }, unit, display, ...extra }
}

function ratiosConfig({ ratios }) {
  const labels = ratios.map((r) => {
    const [ , m, d ] = r.date.split("-")
    return `${d}.${m}.`
  })

  return {
    type: "bar",
    data: {
      labels,
      datasets: [
        { label: "Autarkie", data: ratios.map((r) => r.autarky_pct), tone: "--color-chart-3", order: 1 },
        {
          type: "line",
          label: "Eigenverbrauchsquote",
          data: ratios.map((r) => r.self_consumption_pct),
          tone: "--color-solar",
          order: 0,
          borderWidth: 2,
          pointRadius: 3.5,
          pointHoverRadius: 5,
          tension: 0,
          clip: false,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: timeCategoryScale(ratios.map((r) => localMidnight(r.date))),
        y: { min: 0, max: 100, unit: "%", decimals: 1 },
      },
      plugins: { legend: { display: false } },
      animation: false,
    },
  }
}

function dailyPowerBarConfig(detail) {
  const series = detail.series || []
  const producers = series
    .filter((row) => row.role === "producer")
    .map((row) => ({ label: row.name, data: row.data || [], tone: "--color-solar", stack: "produced" }))
  const consumers = consumerSeries(series.filter((row) => row.role === "consumer"), (row) => row.data || [], detail.consumer_order)
    .map((row) => ({ ...row, stack: "consumed" }))

  return {
    type: "bar",
    data: { labels: detail.labels || [], datasets: [ ...producers, ...consumers ] },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: { stacked: true, ...timeCategoryScale(detail.times || []) },
        y: { stacked: true, beginAtZero: true, unit: "W" },
      },
      plugins: { legend: { display: false } },
      animation: false,
    },
  }
}

// The icons' gap below the axis is padding, not axis height.
function trimXScale(scale) {
  const pad = scale.options.ticks?.padding || 0
  if (pad > 0 && scale.height > pad) {
    scale.height -= pad
    scale.bottom -= pad
    if (scale.paddingBottom != null) scale.paddingBottom = Math.max(0, scale.paddingBottom - pad)
  }
}

function totalConsumption(series) {
  const consumers = series.filter((row) => row.role === "consumer")
  if (consumers.length === 0) return null

  const length = Math.max(...consumers.map((row) => (row.data || []).length))
  return {
    label: "Gesamtverbrauch",
    data: Array.from({ length }, (_, index) => consumers.reduce((sum, row) => sum + Number(row.data?.[index] || 0), 0)),
    tone: "--color-chart-total",
    fill: false,
    tension: 0.2,
    pointRadius: 0,
  }
}
