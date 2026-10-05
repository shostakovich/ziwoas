// Chart.js colours from design tokens, kept in step with the theme.
//
//   import { chartTheme, vizToken } from "lib/chart_theme"
//
//   new Chart(canvas, {
//     data: { datasets: [ { tone: "--viz-solar", fillAlpha: 0.12, … } ] },
//     plugins: [ chartTheme ],
//   })
//
// A dataset names its colour as a token (`tone`); the plugin resolves it into
// borderColor and backgroundColor (translucent when `fillAlpha` is set) and
// colours axes, grid lines, legend and tooltip from felt tokens. When the
// colour scheme or the look changes, it repaints and redraws the chart.
// Charts also share the page's font, rounded bar ends, small round legend keys,
// German numbers (lib/format) on value axes and in tooltips, and fills drawn
// beneath every line. The main axes carry no titles: the card's subtitle names
// the unit once. Time axes tick without grid lines.
//
// Per chart, a value scale may name its `unit` and `decimals` (tooltips read
// "Büro: 0,18 kWh"); a dataset may override both, say a signed flow in words
// (`flowWords: { positive: "lädt", negative: "entlädt" }`), stay out of the
// legend (`legend: false`), or carry a label at its line's end instead
// (`endLabel: "1.400 Grenzwert"`, coloured by `endLabelTone`).

import "chart.js"
import { themeColor, withAlpha, onThemeChange } from "lib/theme_colors"
import { formatNumber, formatFlow } from "lib/format"

const VIZ_SIZE = 10
const GRID_ALPHA = 0.55
// Legend keys are 9px dots; Chart.js draws a point style at boxHeight·√2/2.
const LEGEND_KEY_PX = 9
const LEGEND_FONT_PX = 12
const PHONE_VALUE_TICKS = 5
// Label halos let the card show through (felt stays felt) and still lift the
// text off the lines it crosses.
const HALO_ALPHA = 0.6
const HALO_WIDTH = 5

// Below felt's sm breakpoint a time axis gets fewer labels.
const PHONE = window.matchMedia("(max-width: 575.98px)")
export function isPhone() {
  return PHONE.matches
}

// Time axes, one rule for every chart: a day ticks on full hours every three
// hours ("21:00"), phones name every second one; longer spans tick once per
// day at midnight ("Sa 26.09."), at most four on phones and eight on wider
// screens. Labels never rotate.
//
// Hours and days are the household's (the layout's ziwoas-time-zone meta), not
// the browser's: a traveller sees the same axis as at home. Without the meta,
// the browser's zone.
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

// The household's wall-clock time at `ms`, encoded as if it were UTC: read its
// fields with getUTC*().
function wallClock(ms) {
  const part = {}
  for (const { type, value } of WALL_CLOCK.formatToParts(ms)) part[type] = Number(value)
  return Date.UTC(part.year, part.month - 1, part.day, part.hour % 24, part.minute, part.second) + (ms % 1000)
}

// The instant at which the household's clocks show `wall` (as from wallClock).
function instantOf(wall) {
  let ms = wall - (wallClock(wall) - wall)
  ms = wall - (wallClock(ms) - ms)
  return ms
}

// German date and time in the household's zone, for tooltips and labels.
export function formatTime(ms, options) {
  return new Date(ms).toLocaleString("de-DE", { ...options, timeZone })
}

function spansDays(min, max) {
  return max - min > 36 * HOUR_MS
}

function timeLabel(ms, days) {
  const wall = new Date(wallClock(ms))
  if (days) return `${WEEKDAYS[wall.getUTCDay()]} ${pad2(wall.getUTCDate())}.${pad2(wall.getUTCMonth() + 1)}.`
  return isPhone() && wall.getUTCHours() % 6 !== 0 ? "" : `${pad2(wall.getUTCHours())}:00`
}

// Tick instants (epoch ms) between min and max, on the household's clock. A
// day with a clock change has 23 or 25 hours; its ticks stay on the clock.
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

// The household's midnight (epoch ms) of an ISO date ("2026-09-26").
export function localMidnight(isoDate) {
  const [ year, month, day ] = isoDate.split("-").map(Number)
  return instantOf(Date.UTC(year, month - 1, day))
}

// x scale for points whose x is epoch ms.
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

// x scale for category labels standing for the instants in `times` (epoch ms,
// ascending): each tick sits on the first label at or within an hour after it.
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

// A value axis that dips below zero ends on the next multiple of `step` under
// the lowest value; undefined (Chart.js' own minimum) when nothing is negative.
export function roundedFloor(values, step) {
  const lowest = values.reduce((low, value) => (Number.isFinite(value) ? Math.min(low, value) : low), 0)
  return lowest < 0 ? Math.floor(lowest / step) * step : undefined
}

// afterBuildTicks for an axis with such a floor: a minimum off the tick step
// (−100 on a 500 step) bounds the plot unlabelled, so the labels keep an even
// rhythm.
export function dropOffStepBound(scale) {
  const [ first, second, third ] = scale.ticks
  if (!third) return
  if (second.value - first.value < third.value - second.value - 1e-9) scale.ticks.shift()
}

// A value axis whose top hugs the peak on a 1–2–2,5–5 step, in at most
// `spaces` steps: a peak of 1.020 tops out at 1.250 in steps of 250, where
// Chart.js' own 1–2–5 steps would leave a third of the plot empty above it at
// 1.500. Spread into the scale; empty when nothing rises above zero.
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

// Categorical colour for the entity at `index` in its stable (config) order.
export function vizToken(index) {
  return `--viz-${(index % VIZ_SIZE) + 1}`
}

function paintDatasets(chart) {
  for (const dataset of chart.data.datasets) {
    if (!dataset.tone) continue
    const color = themeColor(dataset.tone)
    dataset.borderColor = color
    dataset.backgroundColor = dataset.fillAlpha == null ? color : withAlpha(color, dataset.fillAlpha)
  }
}

// A canvas knows nothing of CSS: Chart.js gets the body font once, before the
// first chart is drawn.
let defaultsSet = false
function setDefaults() {
  if (defaultsSet) return
  defaultsSet = true
  Chart.defaults.font.family = getComputedStyle(document.body).fontFamily
  Chart.defaults.locale = document.documentElement.lang || "de"
  Chart.defaults.elements.bar.borderRadius = 3
  Chart.defaults.plugins.filler.drawTime = "beforeDatasetsDraw"
}

// Value ticks in German, as many decimals as the tick step needs.
function valueTick(value, _index, ticks) {
  const step = ticks.length > 1 ? Math.abs(ticks[1].value - ticks[0].value) : 1
  const decimals = step > 0 && step < 1 ? Math.min(3, Math.ceil(-Math.log10(step) - 1e-9)) : 0
  return formatNumber(value, { decimals })
}

function scaleConfig(chart, dataset) {
  const scales = chart.config.options.scales || {}
  return scales[dataset.yAxisID || "y"] || {}
}

// "Büro: 0,18 kWh", "Akku: entlädt 80 W".
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

// A line's own fill is faint or none; its legend key is a solid dot in the
// line's colour, like .legend-dot. A dataset hidden by its config (until shown
// on purpose), one with an end label and one marked `legend: false` stay out.
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

// A reference line (a threshold) names itself at an end of the plot: right and
// above it while that is clear of the series, else wherever the series keeps
// furthest away — left, or below the line.
const END_LABEL_GAP = 4
const END_LABEL_CLEAR = 12
// A spot has to be this much clearer (px) to beat an earlier one.
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

// How much of the segment a–b runs through the box (Liang–Barsky clipping),
// as a share of its length; 0 when it misses.
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

// How far the series keep from the box (px), or, where they run through it,
// how long a stretch of them does so, negated: a line clipping a corner beats
// one striking through the label.
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

// Where a label `width` × `height` px names the line at `lineY` (canvas px)
// inside `area` (the chart area), given the series as `lines` (arrays of
// {x, y} px) and the boxes of labels already placed (`taken`). Spots that
// leave the area or cover a placed label are out; of the rest, the clearest
// wins, and every spot at least END_LABEL_CLEAR away counts as clear, so a
// free right end keeps the label where it always was. Where every spot is
// crossed, the one the series cuts through least.
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

function drawEndLabels(chart) {
  const { ctx, chartArea } = chart
  const lines = seriesLines(chart)
  const taken = []
  chart.data.datasets.forEach((dataset, index) => {
    if (!dataset.endLabel || !chart.isDatasetVisible(index)) return
    const point = chart.getDatasetMeta(index).data.at(-1)
    if (!point) return
    ctx.save()
    ctx.font = `600 ${LEGEND_FONT_PX}px ${Chart.defaults.font.family}`
    const spot = placeEndLabel({
      lineY: point.y, width: ctx.measureText(dataset.endLabel).width, height: LEGEND_FONT_PX,
      area: chartArea, lines, taken,
    })
    if (spot) {
      taken.push(spot.box)
      dataset.endLabelSpot = spot
      ctx.textAlign = spot.textAlign
      ctx.textBaseline = spot.textBaseline
      ctx.lineJoin = "round"
      ctx.lineWidth = HALO_WIDTH
      ctx.strokeStyle = withAlpha(themeColor("--surface"), HALO_ALPHA)
      ctx.fillStyle = themeColor(dataset.endLabelTone || "--muted")
      ctx.strokeText(dataset.endLabel, spot.x, spot.y)
      ctx.fillText(dataset.endLabel, spot.x, spot.y)
    }
    ctx.restore()
  })
}

function paintOptions(chart) {
  const text = themeColor("--text")
  const muted = themeColor("--muted")
  const grid = withAlpha(themeColor("--border"), GRID_ALPHA)
  // The raw config (scales already merged per axis), not the resolver proxy.
  const options = chart.config.options

  // Value axes (y…) get German ticks. The main axes (x, y) never show a
  // title: the card subtitle names the unit. A second value axis (the
  // reports' sun scale) keeps its unit title, except on phones, which also
  // get fewer value ticks unless the scale counts its own (snugTop).
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
    backgroundColor: themeColor("--surface-raised"),
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

  // Datasets added or replaced after construction get their colours too.
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
