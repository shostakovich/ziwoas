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
// beneath every line.
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
    ticks: { autoSkip: false, maxRotation: 0, callback: (value) => labels.get(value) },
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

// A reference line (a threshold) names itself at its right end, above the line.
function drawEndLabels(chart) {
  const { ctx, chartArea } = chart
  chart.data.datasets.forEach((dataset, index) => {
    if (!dataset.endLabel || !chart.isDatasetVisible(index)) return
    const point = chart.getDatasetMeta(index).data.at(-1)
    if (!point) return
    ctx.save()
    ctx.font = `600 ${LEGEND_FONT_PX}px ${Chart.defaults.font.family}`
    ctx.textAlign = "right"
    ctx.textBaseline = "bottom"
    ctx.lineJoin = "round"
    ctx.lineWidth = 3
    ctx.strokeStyle = themeColor("--surface")
    ctx.fillStyle = themeColor(dataset.endLabelTone || "--muted")
    const x = Math.min(point.x, chartArea.right) - 4
    const y = point.y - 3
    ctx.strokeText(dataset.endLabel, x, y)
    ctx.fillText(dataset.endLabel, x, y)
    ctx.restore()
  })
}

function paintOptions(chart) {
  const text = themeColor("--text")
  const muted = themeColor("--muted")
  const grid = withAlpha(themeColor("--border"), GRID_ALPHA)
  // The raw config (scales already merged per axis), not the resolver proxy.
  const options = chart.config.options

  // Value axes (y…) get German ticks. Phones: no axis titles (the card
  // subtitle names the unit) and fewer value ticks.
  for (const [ id, scale ] of Object.entries(options.scales || {})) {
    scale.ticks = Object.assign(scale.ticks || {}, { color: muted })
    scale.title = Object.assign(scale.title || {}, { color: muted })
    scale.grid = Object.assign(scale.grid || {}, { color: grid })
    scale.border = Object.assign(scale.border || {}, { color: grid })
    // The merged config may already hold Chart.js' own numeric formatter.
    if (id.startsWith("y") && [ undefined, Chart.Ticks.formatters.numeric ].includes(scale.ticks.callback)) {
      scale.ticks.callback = valueTick
    }
    if (isPhone()) {
      scale.title.display = false
      if (id.startsWith("y")) scale.ticks.maxTicksLimit = PHONE_VALUE_TICKS
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
