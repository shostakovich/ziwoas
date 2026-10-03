// Concrete colours for canvas charts from CSS custom properties.
//
// felt-css and the --viz-* tokens are light-dark()/color-mix()/oklch() values,
// which getPropertyValue() returns unresolved and getComputedStyle() may return
// as oklab()/oklch(). Chart.js needs plain sRGB, so each token is painted into a
// 1×1 canvas and read back.
//
//   import { themeColor, themeColors, withAlpha, onThemeChange } from "lib/theme_colors"
//
//   themeColor("--viz-solar")                 // "rgb(221, 158, 20)"
//   themeColors(["--viz-1", "--viz-2"])       // ["rgb(…)", "rgb(…)"]
//   withAlpha(themeColor("--viz-grid"), 0.14) // "rgba(49, 98, 172, 0.14)"
//   const off = onThemeChange(() => chart.update())  // call off() in disconnect()
//
// Results are cached; the cache clears and subscribers run when the system
// colour scheme flips or <html> changes data-look / data-bs-theme.

const cache = new Map()
const subscribers = new Set()
let probe = null
let pixel = null

function probeElement() {
  if (!probe || !probe.isConnected) {
    probe = document.createElement("span")
    probe.setAttribute("aria-hidden", "true")
    probe.style.cssText = "position:absolute;width:0;height:0;overflow:hidden;visibility:hidden;pointer-events:none"
    document.documentElement.appendChild(probe)
  }
  return probe
}

function pixelContext() {
  if (!pixel) {
    const canvas = document.createElement("canvas")
    canvas.width = canvas.height = 1
    pixel = canvas.getContext("2d", { willReadFrequently: true })
  }
  return pixel
}

function toRgb(cssColor) {
  const ctx = pixelContext()
  ctx.clearRect(0, 0, 1, 1)
  ctx.fillStyle = "rgba(0, 0, 0, 0)"
  ctx.fillStyle = cssColor
  ctx.fillRect(0, 0, 1, 1)
  const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data
  return a === 255 ? `rgb(${r}, ${g}, ${b})` : `rgba(${r}, ${g}, ${b}, ${+(a / 255).toFixed(3)})`
}

function resolve(name) {
  const el = probeElement()
  el.style.color = ""
  el.style.color = `var(${name})`
  return toRgb(getComputedStyle(el).color)
}

export function themeColor(name) {
  if (!cache.has(name)) cache.set(name, resolve(name))
  return cache.get(name)
}

export function themeColors(names) {
  return names.map(themeColor)
}

// Any CSS colour (including themeColor() output) with the given opacity.
export function withAlpha(color, alpha) {
  const match = toRgb(color).match(/\d+(\.\d+)?/g)
  const [r, g, b] = match.map(Number)
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

export function onThemeChange(callback) {
  subscribers.add(callback)
  return () => subscribers.delete(callback)
}

function themeChanged() {
  cache.clear()
  subscribers.forEach((callback) => callback())
}

window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", themeChanged)
new MutationObserver(themeChanged).observe(document.documentElement, {
  attributes: true,
  attributeFilter: [ "data-look", "data-bs-theme" ]
})
