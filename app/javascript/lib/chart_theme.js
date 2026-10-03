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

import { themeColor, withAlpha, onThemeChange } from "lib/theme_colors"

const VIZ_SIZE = 10

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

function paintOptions(chart) {
  const text = themeColor("--text")
  const muted = themeColor("--muted")
  const grid = themeColor("--border")
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
  legend.labels = Object.assign(legend.labels || {}, { color: text })
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
