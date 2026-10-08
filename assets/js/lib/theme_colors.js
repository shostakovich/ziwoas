// Chart.js needs plain sRGB, so each token is painted into a 1×1 canvas and read back.

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

export function withAlpha(color, alpha) {
  const key = `${color}|${alpha}`
  if (!cache.has(key)) {
    const [r, g, b] = toRgb(color).match(/\d+(\.\d+)?/g).map(Number)
    cache.set(key, `rgba(${r}, ${g}, ${b}, ${alpha})`)
  }
  return cache.get(key)
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
