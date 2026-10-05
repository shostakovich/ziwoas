import { Controller } from "@hotwired/stimulus"
import "chart.js"
import { chartTheme, vizToken, timeCategoryScale, localMidnight, isPhone, snugTop } from "lib/chart_theme"

// Connects to data-controller="energy-report"
// Renders bar/line charts plus an in-canvas weather-icon plugin that draws
// icons inside the chart, just below the bars/lines (above the tick labels).
export default class extends Controller {
  static targets = [
    "payload", "weatherAssets",
    "dailyCanvas", "ratiosCanvas", "detailCanvas",
    "dailyWeatherCheckbox", "detailWeatherCheckbox",
  ]

  connect() {
    this.dailyChart = null
    this.ratiosChart = null
    this.detailChart = null
    this.payload = this._readPayload()
    // Every consumer in config order: colours stay with the plug across charts.
    this.consumerIndex = new Map(
      (this.payload.daily?.consumer_series || []).map((series, index) => [ series.plug_id, index ])
    )
    this.assetMap = this._readAssetMap()
    this.imageCache = {}
    this.dailyWeatherEnabled = !this.hasDailyWeatherCheckboxTarget || this.dailyWeatherCheckboxTarget.checked
    this.detailWeatherEnabled = !this.hasDetailWeatherCheckboxTarget || this.detailWeatherCheckboxTarget.checked
    this._preloadIconImages().then(() => {
      this._buildDailyChart()
      this._buildRatiosChart()
      this._buildDetailChart()
    })
  }

  disconnect() {
    this.dailyChart?.destroy()
    this.ratiosChart?.destroy()
    this.detailChart?.destroy()
  }

  toggleDailyWeather(event) {
    this.dailyWeatherEnabled = event.target.checked
    this._setSolarVisibility(this.dailyChart, this.dailyWeatherEnabled)
    this.dailyChart?.update()
  }

  toggleDetailWeather(event) {
    this.detailWeatherEnabled = event.target.checked
    this._setSolarVisibility(this.detailChart, this.detailWeatherEnabled)
    this.detailChart?.update()
  }

  _setSolarVisibility(chart, visible) {
    if (!chart) return
    chart.data.datasets.forEach((ds, idx) => {
      if (ds._isSolar) chart.setDatasetVisibility(idx, visible)
    })
    if (chart.options._weatherIcons) {
      chart.options._weatherIcons.enabled = visible
      const padOn = chart.options._weatherIcons.paddingOn ?? 0
      if (chart.options.scales?.x?.ticks) {
        chart.options.scales.x.ticks.padding = visible ? padOn : 0
      }
    }
    if (chart.options.scales?.ySolar) {
      chart.options.scales.ySolar.display = visible
    }
  }

  _readPayload() {
    if (!this.hasPayloadTarget) return { daily: {}, detail: {} }
    try {
      return JSON.parse(this.payloadTarget.textContent)
    } catch (error) {
      console.error("energy report payload parse failed:", error)
      return { daily: {}, detail: {} }
    }
  }

  _readAssetMap() {
    if (!this.hasWeatherAssetsTarget) return {}
    try {
      return JSON.parse(this.weatherAssetsTarget.textContent)
    } catch (error) {
      console.error("weather asset map parse failed:", error)
      return {}
    }
  }

  _preloadIconImages() {
    const names = Object.keys(this.assetMap)
    if (names.length === 0) return Promise.resolve()
    return Promise.all(names.map((name) => {
      return new Promise((resolve) => {
        const img = new Image()
        img.onload = () => { this.imageCache[name] = img; resolve() }
        img.onerror = () => { resolve() }
        img.src = this.assetMap[name]
      })
    }))
  }

  _weatherIconsPlugin() {
    const cache = this.imageCache
    return {
      id: "weatherIcons",
      afterDatasetsDraw(chart, _args, _opts) {
        const cfg = chart.options._weatherIcons
        if (!cfg || !cfg.enabled) return
        const icons = cfg.icons || []
        if (icons.length === 0) return
        const xScale = chart.scales.x
        if (!xScale) return
        const { ctx, chartArea } = chart
        const size = cfg.size || 22
        // Draw icons in the gap between the chart area and the tick labels.
        // We open that gap via scales.x.ticks.padding. Extra breathing room
        // between the axis line and the icons keeps things from feeling cramped.
        const gap = cfg.gap ?? 14
        const y = chartArea.bottom + gap + (size / 2)
        ctx.save()
        icons.forEach((icon) => {
          const img = cache[icon.asset_name]
          if (!img) return
          const x = xScale.getPixelForValue(icon.label_index)
          if (x === undefined || x === null) return
          ctx.drawImage(img, x - size / 2, y - size / 2, size, size)
        })
        ctx.restore()
      }
    }
  }

  _buildDailyChart() {
    if (!this.hasDailyCanvasTarget) return

    const daily = this.payload.daily || {}
    const labels = daily.labels || []
    const consumerDatasets = this._consumerBarDatasets(daily.consumer_series || [], { top: 5 })
    const consumedDatasets = consumerDatasets.length > 0 ? consumerDatasets : [
      { label: "Verbrauch", data: daily.consumed_kwh || [], tone: "--viz-total", stack: "consumed" },
    ]

    const datasets = [
      { label: "Ertrag", data: daily.produced_kwh || [], tone: "--viz-solar", stack: "produced" },
      ...consumedDatasets,
    ]

    const w = daily.weather
    const hasIcons = w && Array.isArray(w.icons) && w.icons.length > 0
    const hasSolar = w && Array.isArray(w.solar_kwh_per_m2)

    const dailyIconsPadding = 44
    const trimXScale = function(scale) {
      const pad = scale.options.ticks?.padding || 0
      if (pad > 0 && scale.height > pad) {
        scale.height -= pad
        scale.bottom -= pad
        if (scale.paddingBottom != null) scale.paddingBottom = Math.max(0, scale.paddingBottom - pad)
      }
    }
    const timeAxis = timeCategoryScale((daily.ratios || []).map((r) => localMidnight(r.date)))
    const scales = {
      x: {
        stacked: true,
        ...timeAxis,
        ticks: { ...timeAxis.ticks, padding: hasIcons && this.dailyWeatherEnabled ? dailyIconsPadding : 0 },
        afterFit: trimXScale,
      },
      y: { stacked: true, beginAtZero: true, unit: "kWh", decimals: 2 },
    }

    if (hasSolar) {
      datasets.push({
        type: "line",
        label: "Sonnenstrahlung",
        data: w.solar_kwh_per_m2,
        yAxisID: "ySolar",
        tone: "--warning-emphasis",
        pointRadius: 3,
        tension: 0.2,
        spanGaps: true,
        order: 0,
        hidden: !this.dailyWeatherEnabled,
        _isSolar: true,
      })
      scales.ySolar = {
        position: "right",
        beginAtZero: true,
        grid: { drawOnChartArea: false },
        title: { display: true, text: "kWh/m²" },
        unit: "kWh/m²",
        decimals: 2,
        display: this.dailyWeatherEnabled,
      }
    }

    const iconList = hasIcons
      ? w.icons.map((icon, idx) => icon ? { label_index: idx, asset_name: icon.asset_name } : null).filter(Boolean)
      : []

    this.dailyChart = this._replaceChart(this.dailyCanvasTarget, {
      type: "bar",
      data: { labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales,
        plugins: { legend: { position: "bottom" } },
        animation: false,
        _weatherIcons: { enabled: this.dailyWeatherEnabled, icons: iconList, size: 32, gap: 8, paddingOn: dailyIconsPadding },
      },
      plugins: [this._weatherIconsPlugin()],
    })
  }

  _buildRatiosChart() {
    if (!this.hasRatiosCanvasTarget) return

    const daily = this.payload.daily || {}
    const ratios = daily.ratios || []
    const labels = ratios.map((r) => {
      const [, m, d] = r.date.split("-")
      return `${d}.${m}.`
    })
    const autarky = ratios.map((r) => (r.autarky_pct === null ? null : r.autarky_pct))
    const selfCons = ratios.map((r) => (r.self_consumption_pct === null ? null : r.self_consumption_pct))

    this.ratiosChart = this._replaceChart(this.ratiosCanvasTarget, {
      type: "bar",
      data: {
        labels,
        datasets: [
          { label: "Autarkie", data: autarky, tone: "--viz-2" },
          { label: "Eigenverbrauch", data: selfCons, tone: "--viz-solar" },
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
    })
  }

  _buildDetailChart() {
    if (!this.hasDetailCanvasTarget) return

    const detail = this.payload.detail || {}
    if (detail.chart_type === "bar") {
      this._buildDailyPowerBarChart(detail)
      return
    }

    this._buildPowerLineChart(detail)
  }

  _buildPowerLineChart(detail) {
    const labels = detail.labels || []

    // As on the dashboard: PV filled, consumers and their total as plain lines.
    const datasets = (detail.series || []).map((series) => {
      const producer = series.role === "producer"
      return {
        label: series.name,
        data: series.data,
        tone: producer ? "--viz-solar" : this._consumerTone(series),
        fill: producer,
        fillAlpha: producer ? 0.12 : undefined,
        tension: 0.2,
        pointRadius: 0,
        hidden: series.role === "consumer",
      }
    })
    const totalConsumption = this._totalConsumptionDataset(detail.series || [])
    if (totalConsumption) datasets.push(totalConsumption)

    const w = detail.weather
    const hasIcons = w && Array.isArray(w.icons) && w.icons.length > 0
    const hasSolar = w && Array.isArray(w.solar_w_per_m2)

    const timeAxis = timeCategoryScale(detail.times || [])
    const detailIconsPadding = 38
    const trimXScale = function(scale) {
      const pad = scale.options.ticks?.padding || 0
      if (pad > 0 && scale.height > pad) {
        scale.height -= pad
        scale.bottom -= pad
        if (scale.paddingBottom != null) scale.paddingBottom = Math.max(0, scale.paddingBottom - pad)
      }
    }
    const scales = {
      x: { ...timeAxis, ticks: { ...timeAxis.ticks, padding: hasIcons && this.detailWeatherEnabled ? detailIconsPadding : 0 }, afterFit: trimXScale },
      // A phone's few value ticks would leave a third of the plot empty.
      y: { beginAtZero: true, unit: "W", ...(isPhone() ? snugTop(datasets.flatMap((dataset) => dataset.data || [])) : {}) },
    }

    if (hasSolar) {
      datasets.push({
        label: "Sonnenstrahlung",
        data: w.solar_w_per_m2,
        yAxisID: "ySolar",
        tone: "--warning-emphasis",
        fillAlpha: 0.18,
        stepped: "before",
        fill: true,
        pointRadius: 0,
        spanGaps: true,
        hidden: !this.detailWeatherEnabled,
        _isSolar: true,
      })
      scales.ySolar = {
        position: "right",
        beginAtZero: true,
        grid: { drawOnChartArea: false },
        title: { display: true, text: "W/m²" },
        unit: "W/m²",
        display: this.detailWeatherEnabled,
      }
    }

    this.detailChart = this._replaceChart(this.detailCanvasTarget, {
      type: "line",
      data: { labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        // Five-minute samples: thin lines keep the series apart, thinner on a phone.
        elements: { line: { borderWidth: isPhone() ? 0.75 : 1.25 } },
        scales,
        plugins: { legend: { position: "bottom" } },
        animation: false,
        _weatherIcons: { enabled: this.detailWeatherEnabled, icons: hasIcons ? w.icons : [], size: 28, gap: 8, paddingOn: detailIconsPadding },
      },
      plugins: [this._weatherIconsPlugin()],
    })
  }

  _buildDailyPowerBarChart(detail) {
    const labels = detail.labels || []
    const producerDatasets = (detail.series || [])
      .filter((series) => series.role === "producer")
      .map((series) => ({
        label: series.name, data: series.data || [],
        tone: "--viz-solar", stack: "produced",
      }))
    const consumerDatasets = this._consumerBarDatasets(
      (detail.series || []).filter((series) => series.role === "consumer")
    )

    this.detailChart = this._replaceChart(this.detailCanvasTarget, {
      type: "bar",
      data: { labels, datasets: [ ...producerDatasets, ...consumerDatasets ] },
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
    })
  }

  _replaceChart(canvas, config) {
    Chart.getChart(canvas)?.destroy()
    return new Chart(canvas, { ...config, plugins: [ ...(config.plugins || []), chartTheme ] })
  }

  _consumerTone(series) {
    return vizToken(this.consumerIndex.get(series.plug_id) ?? this.consumerIndex.size)
  }

  _consumerBarDatasets(series, options = {}) {
    const rows = series.map((row) => ({
      ...row,
      total: (row.data || []).reduce((sum, value) => sum + Number(value || 0), 0),
    })).sort((a, b) => b.total - a.total)

    const limit = options.top || rows.length
    const visible = rows.slice(0, limit)
    const rest = rows.slice(limit)
    const datasets = visible.map((row) => ({
      label: row.name, data: row.data || [],
      tone: this._consumerTone(row), stack: "consumed",
    }))

    if (rest.length > 0) {
      const length = Math.max(...rest.map((row) => (row.data || []).length))
      datasets.push({
        label: "Weitere Verbraucher",
        data: Array.from({ length }, (_, index) => {
          return +rest.reduce((sum, row) => sum + Number(row.data?.[index] || 0), 0).toFixed(3)
        }),
        tone: "--viz-muted",
        stack: "consumed",
      })
    }

    return datasets
  }

  _totalConsumptionDataset(series) {
    const consumers = series.filter((row) => row.role === "consumer")
    if (consumers.length === 0) return null

    const length = Math.max(...consumers.map((row) => (row.data || []).length))
    const data = Array.from({ length }, (_, index) => {
      return consumers.reduce((sum, row) => sum + Number(row.data?.[index] || 0), 0)
    })

    return {
      label: "Gesamtverbrauch", data,
      tone: "--viz-total",
      fill: false, tension: 0.2, pointRadius: 0,
    }
  }
}
