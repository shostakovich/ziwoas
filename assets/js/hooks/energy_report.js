import { renderChart, vizToken, tonesByOrder, timeCategoryScale, localMidnight, isPhone, snugTop, lineElements } from "../lib/chart_theme.js"

const DAILY_ICONS_PADDING = 44
const DETAIL_ICONS_PADDING = 38

// The Berichte page's three charts from the payload island, with the weather icons from
// the asset island. The "Wetter einblenden" switches (data-weather-toggle) show the weather
// series in place; a new payload redraws every chart.
export default {
  mounted() {
    this.charts = {}
    this.imageCache = {}
    this.onChange = (event) => {
      const toggle = event.target.closest("[data-weather-toggle]")
      if (toggle) this.toggleWeather(toggle.dataset.weatherToggle, toggle.checked)
    }
    this.el.addEventListener("change", this.onChange)
    this.load()
  },

  updated() {
    if (this.island("payload") !== this.payloadText) this.load()
  },

  destroyed() {
    this.gone = true
    this.el.removeEventListener("change", this.onChange)
    Object.values(this.charts).forEach((chart) => chart.destroy())
    this.charts = {}
  },

  island(name) {
    return this.el.querySelector(`script[data-island="${name}"]`)?.textContent
  },

  readIsland(name, fallback) {
    const text = this.island(name)
    if (text === undefined) return fallback
    try {
      return JSON.parse(text)
    } catch (error) {
      console.error(`energy report ${name} parse failed:`, error)
      return fallback
    }
  },

  canvas(name) {
    return this.el.querySelector(`canvas[data-chart="${name}"]`)
  },

  weatherEnabled(name) {
    const toggle = this.el.querySelector(`[data-weather-toggle="${name}"]`)
    return !toggle || toggle.checked
  },

  async load() {
    this.payloadText = this.island("payload")
    this.payload = this.readIsland("payload", { daily: {}, detail: {} })
    this.consumerTones = tonesByOrder((this.payload.daily?.consumer_series || []).map((series) => series.plug_id))
    await this.preloadIcons(this.readIsland("weather-assets", {}))
    if (this.gone) return
    this.draw("daily", this.dailyConfig())
    this.draw("ratios", this.ratiosConfig())
    this.draw("detail", this.detailConfig())
  },

  draw(name, config) {
    const canvas = this.canvas(name)
    if (!canvas) {
      this.charts[name]?.destroy()
      delete this.charts[name]
      return
    }
    // A new payload may bring a new canvas, when the report was empty before.
    const chart = this.charts[name]?.canvas === canvas ? this.charts[name] : null
    if (!chart) this.charts[name]?.destroy()
    this.charts[name] = renderChart(chart, canvas, config)
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

  toggleWeather(name, visible) {
    const chart = this.charts[name]
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

  dailyConfig() {
    const daily = this.payload.daily || {}
    const enabled = this.weatherEnabled("daily")
    const consumerDatasets = this.consumerBarDatasets(daily.consumer_series || [], { top: 5 })
    const datasets = [
      { label: "Ertrag", data: daily.produced_kwh || [], tone: "--viz-solar", stack: "produced" },
      ...(consumerDatasets.length > 0 ? consumerDatasets : [
        { label: "Verbrauch", data: daily.consumed_kwh || [], tone: "--viz-total", stack: "consumed" },
      ]),
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
        label: "Sonnenstrahlung",
        data: w.solar_kwh_per_m2,
        yAxisID: "ySolar",
        tone: "--felt-warning-emphasis",
        pointRadius: 3,
        tension: 0.2,
        spanGaps: true,
        order: 0,
        hidden: !enabled,
        _isSolar: true,
      })
      scales.ySolar = {
        position: "right",
        beginAtZero: true,
        grid: { drawOnChartArea: false },
        title: { display: true, text: "kWh/m²" },
        unit: "kWh/m²",
        decimals: 2,
        display: enabled,
      }
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
        plugins: { legend: { position: "bottom" } },
        animation: false,
        _weatherIcons: { enabled, icons, size: 32, gap: 8, paddingOn: DAILY_ICONS_PADDING },
      },
      plugins: [ this.weatherIconsPlugin() ],
    }
  },

  ratiosConfig() {
    const ratios = (this.payload.daily || {}).ratios || []
    const labels = ratios.map((r) => {
      const [, m, d] = r.date.split("-")
      return `${d}.${m}.`
    })

    return {
      type: "bar",
      data: {
        labels,
        datasets: [
          { label: "Autarkie", data: ratios.map((r) => r.autarky_pct), tone: "--viz-2" },
          { label: "Eigenverbrauch", data: ratios.map((r) => r.self_consumption_pct), tone: "--viz-solar" },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: timeCategoryScale(ratios.map((r) => localMidnight(r.date))),
          y: { min: 0, max: 100, unit: "%" },
        },
        plugins: { legend: { position: "bottom" } },
        animation: false,
      },
    }
  },

  detailConfig() {
    const detail = this.payload.detail || {}
    return detail.chart_type === "bar" ? this.dailyPowerBarConfig(detail) : this.powerLineConfig(detail)
  },

  powerLineConfig(detail) {
    const enabled = this.weatherEnabled("detail")
    const datasets = (detail.series || []).map((series) => {
      const producer = series.role === "producer"
      return {
        label: series.name,
        data: series.data,
        tone: producer ? "--viz-solar" : this.consumerTone(series),
        fill: producer,
        fillAlpha: producer ? 0.12 : undefined,
        tension: 0.2,
        pointRadius: 0,
        hidden: series.role === "consumer",
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
      y: { beginAtZero: true, unit: "W", ...(isPhone() ? snugTop(datasets.flatMap((dataset) => dataset.data || [])) : {}) },
    }

    if (w && Array.isArray(w.solar_w_per_m2)) {
      datasets.push({
        label: "Sonnenstrahlung",
        data: w.solar_w_per_m2,
        yAxisID: "ySolar",
        tone: "--felt-warning-emphasis",
        fillAlpha: 0.18,
        stepped: "before",
        fill: true,
        pointRadius: 0,
        spanGaps: true,
        hidden: !enabled,
        _isSolar: true,
      })
      scales.ySolar = {
        position: "right",
        beginAtZero: true,
        grid: { drawOnChartArea: false },
        title: { display: true, text: "W/m²" },
        unit: "W/m²",
        display: enabled,
      }
    }

    return {
      type: "line",
      data: { labels: detail.labels || [], datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        elements: lineElements(),
        scales,
        plugins: { legend: { position: "bottom" } },
        animation: false,
        _weatherIcons: { enabled, icons: hasIcons ? w.icons : [], size: 28, gap: 8, paddingOn: DETAIL_ICONS_PADDING },
      },
      plugins: [ this.weatherIconsPlugin() ],
    }
  },

  dailyPowerBarConfig(detail) {
    const producers = (detail.series || [])
      .filter((series) => series.role === "producer")
      .map((series) => ({ label: series.name, data: series.data || [], tone: "--viz-solar", stack: "produced" }))
    const consumers = this.consumerBarDatasets((detail.series || []).filter((series) => series.role === "consumer"))

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
        plugins: { legend: { position: "bottom" } },
        animation: false,
      },
    }
  },

  consumerTone(series) {
    return this.consumerTones.get(series.plug_id) ?? vizToken(this.consumerTones.size)
  },

  consumerBarDatasets(series, { top } = {}) {
    const rows = series.map((row) => ({
      ...row,
      total: (row.data || []).reduce((sum, value) => sum + Number(value || 0), 0),
    })).sort((a, b) => b.total - a.total)

    const limit = top || rows.length
    const datasets = rows.slice(0, limit).map((row) => ({
      label: row.name, data: row.data || [], tone: this.consumerTone(row), stack: "consumed",
    }))

    const rest = rows.slice(limit)
    if (rest.length > 0) {
      const length = Math.max(...rest.map((row) => (row.data || []).length))
      datasets.push({
        label: "Weitere Verbraucher",
        data: Array.from({ length }, (_, index) => +rest.reduce((sum, row) => sum + Number(row.data?.[index] || 0), 0).toFixed(3)),
        tone: "--viz-muted",
        stack: "consumed",
      })
    }
    return datasets
  },
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
    tone: "--viz-total",
    fill: false,
    tension: 0.2,
    pointRadius: 0,
  }
}
