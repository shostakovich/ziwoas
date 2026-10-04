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
// Charts also share the page's font, rounded bar ends and round legend keys
// (matching .legend-dot).

import "chart.js"
import { themeColor, withAlpha, onThemeChange } from "lib/theme_colors"

const VIZ_SIZE = 10
const GRID_ALPHA = 0.55

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
}

// A line's own fill is faint or none; its legend key is a solid dot in the
// line's colour, like .legend-dot. Dashed lines are thresholds and references,
// not data: their key is a short dashed line.
function legendKeys(chart) {
  return Chart.defaults.plugins.legend.labels.generateLabels(chart).map((item) => {
    if (chart.data.datasets[item.datasetIndex]?.borderDash?.length) return { ...item, pointStyle: "line", lineWidth: 2 }
    return { ...item, fillStyle: item.strokeStyle || item.fillStyle, lineWidth: 0, lineDash: [] }
  })
}

function paintOptions(chart) {
  const text = themeColor("--text")
  const muted = themeColor("--muted")
  const grid = withAlpha(themeColor("--border"), GRID_ALPHA)
  // The raw config (scales already merged per axis), not the resolver proxy.
  const options = chart.config.options

  for (const scale of Object.values(options.scales || {})) {
    scale.ticks = Object.assign(scale.ticks || {}, { color: muted })
    scale.title = Object.assign(scale.title || {}, { color: muted })
    scale.grid = Object.assign(scale.grid || {}, { color: grid })
    scale.border = Object.assign(scale.border || {}, { color: grid })
  }

  options.plugins ||= {}
  const legend = options.plugins.legend ||= {}
  legend.labels = Object.assign(legend.labels || {}, {
    color: text, usePointStyle: true, pointStyle: "circle", generateLabels: legendKeys,
  })
  options.plugins.tooltip = Object.assign(options.plugins.tooltip || {}, {
    backgroundColor: themeColor("--surface-raised"),
    titleColor: text,
    bodyColor: text,
    borderColor: grid,
    borderWidth: 1,
  })
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

  afterDestroy(chart) {
    subscriptions.get(chart)?.()
    subscriptions.delete(chart)
  },
}
