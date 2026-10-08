import { renderChart, vizToken, timeScale, timeTooltipTitle, thresholdLine } from "../lib/chart_theme.js"
import { themeColor } from "../lib/theme_colors.js"

const DAY_MS = 86_400_000
const LINE_TONES = {
  warn: { tone: "--felt-warning", textTone: "--felt-warning-text" },
  bad: { tone: "--felt-danger", textTone: "--felt-danger-text" },
}
const HATCH_PX = 8
const MARKER_FONT_PX = 11
const MARKER_GAP_PX = 2

// Points are [ms, value | null, standIn]; a full push replaces them, an appended one replaces
// those from its `from` on, the quarter hour the server recomputed.
export default {
  mounted() {
    this.charts = {}
    this.series = {}
    this.handleEvent("room_air_chart:data", (data) => {
      if (data.room !== this.el.dataset.room) return
      if (data.replace) {
        this.setup = data
        this.series = data.series
      } else if (this.setup) {
        this.append(data.from, data.series)
      } else {
        return
      }
      this.to = data.to
      this.trim()
      this.renderAll()
    })
  },

  destroyed() {
    Object.values(this.charts).forEach((chart) => chart.destroy())
    this.charts = {}
  },

  append(from, series) {
    for (const [ quantity, points ] of Object.entries(series)) {
      const kept = (this.series[quantity] || []).filter(([ at ]) => at < from)
      this.series[quantity] = kept.concat(points)
    }
  },

  // Keeps the last point before the window, so a line enters it from the left edge.
  trim() {
    const from = this.to - DAY_MS
    for (const [ quantity, points ] of Object.entries(this.series)) {
      const inside = points.findIndex(([ at ]) => at >= from)
      const start = inside === -1 ? points.length - 1 : inside - 1
      if (start > 0) this.series[quantity] = points.slice(start)
    }
  },

  renderAll() {
    for (const chart of this.setup.charts) this.render(chart)
  },

  render(setup) {
    const canvas = this.el.querySelector(`canvas[data-chart="${setup.key}"]`)
    if (!canvas) return
    const xBounds = { min: this.to - DAY_MS, max: this.to }
    const series = setup.series.map((s, index) => dataset(s, this.series[s.quantity] || [], index))
    const lines = setup.lines.map(({ value, label, level }) => ({
      ...thresholdLine(xBounds, { value, name: label, ...LINE_TONES[level] }),
      endLabelPlain: true,
      endLabelBox: true,
    }))
    const first = this.series[setup.series[0].quantity] || []
    const standIn = ranges(first, this.to, ([ , value, standIn ]) => standIn === 1 && value != null)
    const gaps = ranges(first, this.to, ([ , value ]) => value == null)

    this.charts[setup.key] = renderChart(this.charts[setup.key], canvas, {
      type: "line",
      data: { datasets: [ ...series, ...lines ] },
      options: options(setup, xBounds, series, {
        standIn, gaps, band: setup.band, standInLabel: this.setup.stand_in, nowLabel: this.setup.now_stand_in,
        standInNow: lastPoint(first)?.[2] === 1,
      }),
      plugins: [ shading, standInMarker ],
    })
  },
}

function dataset({ label }, points, index) {
  return {
    label,
    data: points.map(([ x, y ]) => ({ x, y })),
    standIn: points.map((point) => point[2] === 1),
    tone: vizToken(index),
    borderWidth: 2,
    pointRadius: 0,
    tension: 0.25,
  }
}

function lastPoint(points) {
  for (let i = points.length - 1; i >= 0; i--) if (points[i][1] != null) return points[i]
  return null
}

// Each point that matches holds until the next one, the last until the window's end.
function ranges(points, to, matches) {
  const found = []
  points.forEach((point, index) => {
    if (!matches(point)) return
    const at = point[0]
    const end = index + 1 < points.length ? points[index + 1][0] : to
    const previous = found[found.length - 1]
    if (previous && previous[1] >= at) previous[1] = end
    else found.push([ at, end ])
  })
  return found
}

// A narrow swing (a room's temperature) gets at least `min_span` around its middle.
function spanAround(series, span) {
  const values = series.flatMap((s) => s.data.map((p) => p.y)).filter((y) => y != null)
  if (!values.length) return {}
  const low = Math.min(...values), high = Math.max(...values)
  if (high - low >= span) return {}
  const middle = (low + high) / 2
  return { suggestedMin: Math.floor(middle - span / 2), suggestedMax: Math.ceil(middle + span / 2) }
}

// Ticks too close to the window's end would push the plot in by half a label; dropping them
// lets the plot run to the card's right edge.
const EDGE_SHARE = 0.06
function flushRight(scale) {
  return {
    ...scale,
    afterBuildTicks(axis) {
      scale.afterBuildTicks(axis)
      const edge = (axis.max - axis.min) * EDGE_SHARE
      axis.ticks = axis.ticks.filter(({ value }) => axis.max - value > edge)
    },
  }
}

function options(setup, xBounds, series, shadingOptions) {
  const y = { beginAtZero: setup.from_zero, unit: setup.unit || undefined, decimals: setup.decimals }
  if (setup.suggested_min != null) y.suggestedMin = setup.suggested_min
  if (setup.suggested_max != null) y.suggestedMax = setup.suggested_max
  if (setup.min_span != null) Object.assign(y, spanAround(series, setup.min_span))
  return {
    responsive: true,
    maintainAspectRatio: false,
    animation: false,
    interaction: { mode: "nearest", axis: "x", intersect: false },
    // Room for the stand-in marker's label above the plot.
    layout: { padding: { top: shadingOptions.standInNow ? MARKER_FONT_PX + 2 * MARKER_GAP_PX + 2 : 0 } },
    scales: { x: flushRight(timeScale(xBounds.min, xBounds.max)), y },
    plugins: {
      legend: { display: false },
      roomAirShading: shadingOptions,
      tooltip: {
        filter: (item) => !item.dataset.endLabel,
        callbacks: {
          title: timeTooltipTitle({ weekday: "short", hour: "2-digit", minute: "2-digit" }),
          afterLabel: (item) => (item.dataset.standIn?.[item.dataIndex] ? shadingOptions.standInLabel : ""),
        },
      },
    },
  }
}

function hatch(ctx) {
  const tile = document.createElement("canvas")
  tile.width = tile.height = HATCH_PX
  const pen = tile.getContext("2d")
  pen.strokeStyle = themeColor("--chart-stand-in")
  pen.lineWidth = 1.5
  pen.beginPath()
  for (const offset of [ -HATCH_PX, 0, HATCH_PX ]) {
    pen.moveTo(offset, HATCH_PX)
    pen.lineTo(offset + HATCH_PX, 0)
  }
  pen.stroke()
  return ctx.createPattern(tile, "repeat")
}

// Draws the comfortable band, the gaps and the stand-in sensor's phases behind the lines.
const shading = {
  id: "roomAirShading",

  beforeDatasetsDraw(chart) {
    const shadingOptions = chart.config.options.plugins?.roomAirShading
    if (!shadingOptions) return
    const { ctx, chartArea: area, scales } = chart
    ctx.save()
    ctx.beginPath()
    ctx.rect(area.left, area.top, area.right - area.left, area.bottom - area.top)
    ctx.clip()

    if (shadingOptions.band) {
      const [ low, high ] = shadingOptions.band
      const top = scales.y.getPixelForValue(high)
      ctx.fillStyle = themeColor("--chart-band")
      ctx.fillRect(area.left, top, area.right - area.left, scales.y.getPixelForValue(low) - top)
    }

    if (shadingOptions.gaps.length) {
      ctx.fillStyle = themeColor("--chart-gap")
      for (const [ from, to ] of shadingOptions.gaps) {
        const left = scales.x.getPixelForValue(from)
        ctx.fillRect(left, area.top, Math.max(scales.x.getPixelForValue(to) - left, 1), area.bottom - area.top)
      }
    }

    if (shadingOptions.standIn.length) {
      ctx.fillStyle = hatch(ctx)
      for (const [ from, to ] of shadingOptions.standIn) {
        const left = scales.x.getPixelForValue(from)
        ctx.fillRect(left, area.top, Math.max(scales.x.getPixelForValue(to) - left, 1), area.bottom - area.top)
      }
    }
    ctx.restore()
  },
}

// Marks the line's end when its newest value comes from the stand-in sensor; the label sits
// in the plot's top padding with a thin leader down to the dot, clear of data and line labels.
const standInMarker = {
  id: "roomAirStandInMarker",

  afterDatasetsDraw(chart) {
    const shadingOptions = chart.config.options.plugins?.roomAirShading
    if (!shadingOptions?.standInNow || !shadingOptions.nowLabel) return
    const meta = chart.getDatasetMeta(0)
    const point = [ ...meta.data ].reverse().find((element) => !element.skip && Number.isFinite(element.y))
    if (!point) return
    const { ctx, chartArea: area } = chart
    const muted = themeColor("--felt-secondary-color")
    ctx.save()
    ctx.strokeStyle = muted
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(point.x, point.y - 5)
    ctx.lineTo(point.x, area.top - MARKER_GAP_PX)
    ctx.stroke()
    ctx.fillStyle = themeColor(chart.data.datasets[0].tone)
    ctx.strokeStyle = themeColor("--felt-surface")
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.arc(point.x, point.y, 3.5, 0, 2 * Math.PI)
    ctx.fill()
    ctx.stroke()
    ctx.font = `600 ${MARKER_FONT_PX}px ${getComputedStyle(document.body).fontFamily}`
    ctx.textAlign = "right"
    ctx.textBaseline = "bottom"
    ctx.fillStyle = muted
    ctx.fillText(shadingOptions.nowLabel, point.x + 1, area.top - MARKER_GAP_PX - 1)
    ctx.restore()
  },
}
