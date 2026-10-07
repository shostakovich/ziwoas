// The one Chart.js plugin every chart uses. Dataset options: tone, fillAlpha, unit, decimals,
// flowWords, legend: false, endLabel/endLabelTone; a value scale may set unit and decimals.

import Chart from "../../vendor/chart.umd.js"
import { themeColor, withAlpha, onThemeChange } from "./theme_colors.js"
import { formatNumber, formatFlow } from "./format.js"

const VIZ_SIZE = 10
// Chart.js draws a point style at boxHeight·√2/2.
const LEGEND_KEY_PX = 9
const LEGEND_FONT_PX = 12
const PHONE_VALUE_TICKS = 5
const HALO_WIDTH = 5

const PHONE = window.matchMedia("(max-width: 575.98px)")
export function isPhone() {
  return PHONE.matches
}

// Hours and days are the household's (ziwoas-time-zone meta), not the browser's:
// a traveller sees the same axis as at home.
const HOUR_MS = 3_600_000
const WEEKDAYS = [ "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" ]
const pad2 = (n) => String(n).padStart(2, "0")

function householdZone() {
  const zone = document.querySelector("meta[name='ziwoas-time-zone']")?.content
  try {
    return new Intl.DateTimeFormat("en-US", { timeZone: zone || undefined }).resolvedOptions().timeZone
  } catch {
    return undefined
  }
}

export const timeZone = householdZone()

const WALL_CLOCK = new Intl.DateTimeFormat("en-US", {
  timeZone, hourCycle: "h23",
  year: "numeric", month: "numeric", day: "numeric", hour: "numeric", minute: "numeric", second: "numeric",
})

// Encoded as if it were UTC: read its fields with getUTC*().
function wallClock(ms) {
  const part = {}
  for (const { type, value } of WALL_CLOCK.formatToParts(ms)) part[type] = Number(value)
  return Date.UTC(part.year, part.month - 1, part.day, part.hour % 24, part.minute, part.second) + (ms % 1000)
}

function instantOf(wall) {
  let ms = wall - (wallClock(wall) - wall)
  ms = wall - (wallClock(ms) - ms)
  return ms
}

export function formatTime(ms, options) {
  return new Date(ms).toLocaleString("de-DE", { ...options, timeZone })
}

export function timeTooltipTitle(options) {
  return (items) => items.length ? formatTime(items[0].parsed.x, options) : ""
}

function spansDays(min, max) {
  return max - min > 36 * HOUR_MS
}

function timeLabel(ms, days) {
  const wall = new Date(wallClock(ms))
  if (days) return `${WEEKDAYS[wall.getUTCDay()]} ${pad2(wall.getUTCDate())}.${pad2(wall.getUTCMonth() + 1)}.`
  return isPhone() && wall.getUTCHours() % 6 !== 0 ? "" : `${pad2(wall.getUTCHours())}:00`
}

// A day with a clock change has 23 or 25 hours; its ticks stay on the clock.
export function timeTicks(min, max) {
  const ticks = []
  const start = new Date(wallClock(min))
  if (!spansDays(min, max)) {
    let t = min - (start.getUTCMinutes() * 60_000 + start.getUTCSeconds() * 1000 + start.getUTCMilliseconds())
    if (t < min) t += HOUR_MS
    for (; t <= max; t += HOUR_MS) {
      if (new Date(wallClock(t)).getUTCHours() % 3 === 0) ticks.push(t)
    }
    return ticks
  }
  const year = start.getUTCFullYear(), month = start.getUTCMonth()
  for (let day = start.getUTCDate(); ; day++) {
    const t = instantOf(Date.UTC(year, month, day))
    if (t > max) break
    if (t >= min) ticks.push(t)
  }
  const step = Math.ceil(ticks.length / (isPhone() ? 4 : 8))
  return ticks.filter((_, index) => index % step === 0)
}

export function localMidnight(isoDate) {
  const [ year, month, day ] = isoDate.split("-").map(Number)
  return instantOf(Date.UTC(year, month - 1, day))
}

export function timeScale(min, max) {
  return {
    type: "linear",
    min,
    max,
    afterBuildTicks: (scale) => { scale.ticks = timeTicks(scale.min, scale.max).map((value) => ({ value })) },
    grid: { drawOnChartArea: false },
    ticks: {
      autoSkip: false,
      maxRotation: 0,
      callback(value) { return timeLabel(value, spansDays(this.min, this.max)) },
    },
  }
}

// Each tick sits on the first category at or within an hour after it.
export function timeCategoryScale(times) {
  const labels = new Map()
  if (times.length > 0) {
    const days = spansDays(times[0], times.at(-1))
    let index = 0
    for (const tick of timeTicks(times[0], times.at(-1))) {
      while (index < times.length && times[index] < tick) index++
      if (index < times.length && times[index] - tick < HOUR_MS) labels.set(index, timeLabel(tick, days))
    }
  }
  return {
    afterBuildTicks: (scale) => { scale.ticks = scale.ticks.filter((tick) => labels.has(tick.value)) },
    grid: { drawOnChartArea: false },
    ticks: { autoSkip: false, maxRotation: 0, callback: (value) => labels.get(value) },
  }
}

export function roundedFloor(values, step) {
  const lowest = values.reduce((low, value) => (Number.isFinite(value) ? Math.min(low, value) : low), 0)
  return lowest < 0 ? Math.floor(lowest / step) * step : undefined
}

// A minimum off the tick step (−100 on a 500 step) stays unlabelled, so the labels keep an even rhythm.
export function dropOffStepBound(scale) {
  const [ first, second, third ] = scale.ticks
  if (!third) return
  if (second.value - first.value < third.value - second.value - 1e-9) scale.ticks.shift()
}

// Chart.js' own 1–2–5 steps would top a peak of 1.020 at 1.500, a third of the plot empty.
const SNUG_FACTORS = [ 1, 2, 2.5, 5, 10 ]
export function snugTop(values, spaces = 5) {
  const peak = values.map(Number).reduce((high, value) => (Number.isFinite(value) ? Math.max(high, value) : high), 0)
  if (peak <= 0) return {}
  const magnitude = 10 ** Math.floor(Math.log10(peak / spaces))
  for (const factor of SNUG_FACTORS) {
    const step = factor * magnitude
    const count = Math.ceil(peak / step - 1e-9)
    if (count <= spaces) return { max: count * step, ticks: { stepSize: step, maxTicksLimit: count + 1 } }
  }
}

// By the entity's stable (config) order, never cycled through the series.
export function vizToken(index) {
  return `--viz-${(index % VIZ_SIZE) + 1}`
}

export function tonesByOrder(ids) {
  return new Map(ids.map((id, index) => [ id, vizToken(index) ]))
}

export function lineElements() {
  return { line: { borderWidth: isPhone() ? 0.75 : 1.25 } }
}

function paintDatasets(chart) {
  for (const dataset of chart.data.datasets) {
    if (!dataset.tone) continue
    const color = themeColor(dataset.tone)
    dataset.borderColor = color
    dataset.backgroundColor = dataset.fillAlpha == null ? color : withAlpha(color, dataset.fillAlpha)
  }
}

let defaultsSet = false
function setDefaults() {
  if (defaultsSet) return
  defaultsSet = true
  Chart.defaults.font.family = getComputedStyle(document.body).fontFamily
  Chart.defaults.locale = document.documentElement.lang || "de"
  Chart.defaults.elements.bar.borderRadius = 3
  Chart.defaults.plugins.filler.drawTime = "beforeDatasetsDraw"
}

function valueTick(value, _index, ticks) {
  const step = ticks.length > 1 ? Math.abs(ticks[1].value - ticks[0].value) : 1
  const decimals = step > 0 && step < 1 ? Math.min(3, Math.ceil(-Math.log10(step) - 1e-9)) : 0
  return formatNumber(value, { decimals })
}

function scaleConfig(chart, dataset) {
  const scales = chart.config.options.scales || {}
  return scales[dataset.yAxisID || "y"] || {}
}

export function tooltipLabel(context) {
  const dataset = context.dataset
  const scale = scaleConfig(context.chart, dataset)
  const unit = dataset.unit ?? scale.unit
  const decimals = dataset.decimals ?? scale.decimals ?? 0
  const value = context.parsed.y
  const text = dataset.flowWords
    ? formatFlow(value, { ...dataset.flowWords, unit, decimals })
    : formatNumber(value, { decimals, unit })
  return `${dataset.label}: ${text}`
}

// A line's own fill is faint or none, so its legend key is a solid dot in the line's colour.
function inLegend(chart, index) {
  const dataset = chart.data.datasets[index]
  if (!dataset || dataset.legend === false || dataset.endLabel) return false
  return !dataset.hidden || chart.isDatasetVisible(index)
}

function legendKeys(chart) {
  return Chart.defaults.plugins.legend.labels.generateLabels(chart)
    .filter((item) => inLegend(chart, item.datasetIndex))
    .map((item) => ({ ...item, fillStyle: item.strokeStyle || item.fillStyle, lineWidth: 0, lineDash: [] }))
}

const END_LABEL_GAP = 4
const END_LABEL_CLEAR = 12
const END_LABEL_EPSILON = 0.5
const END_LABEL_SPOTS = [
  { end: "right", side: "above" }, { end: "left", side: "above" },
  { end: "right", side: "below" }, { end: "left", side: "below" },
]

function pointBoxDistance(point, box) {
  const dx = Math.max(box.left - point.x, 0, point.x - box.right)
  const dy = Math.max(box.top - point.y, 0, point.y - box.bottom)
  return Math.hypot(dx, dy)
}

function pointSegmentDistance(point, a, b) {
  const dx = b.x - a.x, dy = b.y - a.y
  const length = dx * dx + dy * dy
  const t = length === 0 ? 0 : Math.max(0, Math.min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length))
  return Math.hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
}

// Liang–Barsky clipping: the share of a–b inside the box.
function shareInBox(a, b, box) {
  let enter = 0, leave = 1
  const dx = b.x - a.x, dy = b.y - a.y
  const edges = [ [ -dx, a.x - box.left ], [ dx, box.right - a.x ], [ -dy, a.y - box.top ], [ dy, box.bottom - a.y ] ]
  for (const [ p, q ] of edges) {
    if (p === 0) {
      if (q < 0) return 0
    } else if (p < 0) {
      enter = Math.max(enter, q / p)
    } else {
      leave = Math.min(leave, q / p)
    }
  }
  return Math.max(0, leave - enter)
}

function segmentBoxDistance(a, b, box) {
  const corners = [ [ box.left, box.top ], [ box.right, box.top ], [ box.left, box.bottom ], [ box.right, box.bottom ] ]
  return Math.min(
    pointBoxDistance(a, box), pointBoxDistance(b, box),
    ...corners.map(([ x, y ]) => pointSegmentDistance({ x, y }, a, b))
  )
}

// Negative where the series run through the box: a line clipping a corner beats one striking through.
function clearance(box, lines) {
  let nearest = Infinity
  let through = 0
  for (const points of lines) {
    if (points.length === 1) nearest = Math.min(nearest, pointBoxDistance(points[0], box))
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1], b = points[i]
      const share = shareInBox(a, b, box)
      through += share * Math.hypot(b.x - a.x, b.y - a.y)
      nearest = Math.min(nearest, share > 0 ? 0 : segmentBoxDistance(a, b, box))
    }
  }
  return through > 0 ? -through : nearest
}

const overlaps = (a, b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom

// Every spot END_LABEL_CLEAR away counts as clear, so a free right end keeps the label where it was.
export function placeEndLabel({ lineY, width, height, area, lines = [], taken = [] }) {
  let best = null
  for (const { end, side } of END_LABEL_SPOTS) {
    const x = end === "right" ? area.right - END_LABEL_GAP : area.left + END_LABEL_GAP
    const y = side === "above" ? lineY - END_LABEL_GAP : lineY + END_LABEL_GAP
    const box = {
      left: end === "right" ? x - width : x, right: end === "right" ? x : x + width,
      top: side === "above" ? y - height : y, bottom: side === "above" ? y : y + height,
    }
    if (box.top < area.top || box.bottom > area.bottom || taken.some((other) => overlaps(box, other))) continue
    const score = Math.min(clearance(box, lines), END_LABEL_CLEAR)
    if (best && score <= best.score + END_LABEL_EPSILON) continue
    best = { score, x, y, box, textAlign: end, textBaseline: side === "above" ? "bottom" : "top" }
  }
  return best
}

function seriesLines(chart) {
  return chart.data.datasets.flatMap((dataset, index) => {
    if (dataset.endLabel || !chart.isDatasetVisible(index)) return []
    const points = chart.getDatasetMeta(index).data.filter((point) => !point.skip && Number.isFinite(point.y))
    return [ points.map(({ x, y }) => ({ x, y })) ]
  })
}

function endLabelText(chart, dataset, meta) {
  const value = meta.controller.getParsed(meta.data.length - 1)?.y
  const ticks = chart.scales[meta.yAxisID]?.ticks || []
  const onTick = ticks.some((tick) => Math.abs(tick.value - value) <= 1e-9 * Math.max(1, Math.abs(value)))
  if (onTick || !Number.isFinite(value)) return dataset.endLabel
  const decimals = dataset.decimals ?? scaleConfig(chart, dataset).decimals ?? 0
  return `${formatNumber(value, { decimals })} ${dataset.endLabel}`
}

function drawEndLabels(chart) {
  if (!chart.data.datasets.some((dataset) => dataset.endLabel)) return
  const { ctx, chartArea } = chart
  const lines = seriesLines(chart)
  const taken = []
  chart.data.datasets.forEach((dataset, index) => {
    if (!dataset.endLabel || !chart.isDatasetVisible(index)) return
    const meta = chart.getDatasetMeta(index)
    const point = meta.data.at(-1)
    if (!point) return
    const text = endLabelText(chart, dataset, meta)
    ctx.save()
    ctx.font = `600 ${LEGEND_FONT_PX}px ${Chart.defaults.font.family}`
    const spot = placeEndLabel({
      lineY: point.y, width: ctx.measureText(text).width, height: LEGEND_FONT_PX,
      area: chartArea, lines, taken,
    })
    if (spot) {
      taken.push(spot.box)
      ctx.textAlign = spot.textAlign
      ctx.textBaseline = spot.textBaseline
      ctx.lineJoin = "round"
      ctx.lineWidth = HALO_WIDTH
      ctx.strokeStyle = themeColor("--chart-halo")
      ctx.fillStyle = themeColor(dataset.endLabelTone || "--felt-secondary-color")
      ctx.strokeText(text, spot.x, spot.y)
      ctx.fillText(text, spot.x, spot.y)
    }
    ctx.restore()
  })
}

function paintOptions(chart) {
  const text = themeColor("--felt-body-color")
  const muted = themeColor("--felt-secondary-color")
  const grid = themeColor("--chart-grid")
  // The raw config, not the resolver proxy.
  const options = chart.config.options

  // The card subtitle names the main axes' unit; a second value axis keeps its title except on phones.
  for (const [ id, scale ] of Object.entries(options.scales || {})) {
    scale.ticks = Object.assign(scale.ticks || {}, { color: muted })
    scale.title = Object.assign(scale.title || {}, { color: muted })
    if (id === "x" || id === "y") scale.title.display = false
    scale.grid = Object.assign(scale.grid || {}, { color: grid })
    scale.border = Object.assign(scale.border || {}, { color: grid })
    // The merged config may already hold Chart.js' own numeric formatter.
    if (id.startsWith("y") && [ undefined, Chart.Ticks.formatters.numeric ].includes(scale.ticks.callback)) {
      scale.ticks.callback = valueTick
    }
    if (isPhone()) {
      scale.title.display = false
      if (id.startsWith("y")) scale.ticks.maxTicksLimit ??= PHONE_VALUE_TICKS
    }
  }

  options.plugins ||= {}
  const legend = options.plugins.legend ||= {}
  const keySize = LEGEND_KEY_PX / Math.SQRT2
  legend.labels = Object.assign(legend.labels || {}, {
    color: text, usePointStyle: true, pointStyle: "circle", generateLabels: legendKeys,
    boxWidth: keySize, boxHeight: keySize, padding: 12, font: { size: LEGEND_FONT_PX },
  })
  const tooltip = options.plugins.tooltip = Object.assign(options.plugins.tooltip || {}, {
    backgroundColor: themeColor("--felt-surface-raised"),
    titleColor: text,
    bodyColor: text,
    borderColor: grid,
    borderWidth: 1,
  })
  tooltip.callbacks = { label: tooltipLabel, ...tooltip.callbacks }
}

const subscriptions = new WeakMap()

export const chartTheme = {
  id: "chartTheme",

  beforeInit(chart) {
    setDefaults()
    paintOptions(chart)
    paintDatasets(chart)
    subscriptions.set(chart, onThemeChange(() => {
      paintOptions(chart)
      paintDatasets(chart)
      chart.update("none")
    }))
  },

  beforeUpdate(chart) {
    paintDatasets(chart)
  },

  afterDatasetsDraw(chart) {
    drawEndLabels(chart)
  },

  afterDestroy(chart) {
    subscriptions.get(chart)?.()
    subscriptions.delete(chart)
  },
}

// Draws `config` on `canvas` with the theme, reusing `chart` when it has the same type: a
// refresh swaps data and options in place instead of building a new chart. Returns the chart.
export function renderChart(chart, canvas, config) {
  if (chart && chart.config.type === config.type) {
    chart.data = config.data
    chart.options = config.options
    paintOptions(chart)
    chart.update("none")
    return chart
  }
  chart?.destroy()
  return new Chart(canvas, { ...config, plugins: [ ...(config.plugins || []), chartTheme ] })
}
