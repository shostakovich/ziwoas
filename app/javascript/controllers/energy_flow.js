// Shared energy-flow SVG rendering for the dashboard and solakon controllers.
// The flow geometry and the animated-dot logic are identical on both pages, so
// they live here to avoid the two copies drifting apart.

export const EF_PATHS = {
  solarHome: "M 200,122 C 205,150 250,166 306,170",
  solarGrid: "M 200,122 C 195,150 150,166 94,170",
  solarBattery: "M 200,122 L 200,218",
  gridHome: "M 94,170 L 306,170",
  gridBattery: "M 94,170 C 150,174 195,190 200,218",
  batteryHome: "M 200,218 C 205,190 250,174 306,170",
}

export const EF_LENS = {
  solarHome: 123,
  solarGrid: 123,
  solarBattery: 96,
  gridHome: 212,
  gridBattery: 123,
  batteryHome: 123,
}

// Animation duration (s) for one dot traversing a path of length `len` at `w`
// watts. Below 1 W there is no flow, so no animation.
export function efDur(w, len) {
  return w < 1 ? null : Math.max(0.5, Math.min(8, len / w))
}

// Swap the battery character image. Works for both <img> (src) and SVG <image>
// (href) targets.
export function setBatteryImage(image, state) {
  if (!image) return
  const key = state || "normal"
  const src = image.dataset[`batteryState${key.charAt(0).toUpperCase()}${key.slice(1)}`]
  if (!src) return
  if (image.tagName.toLowerCase() === "img") image.src = src
  else image.setAttribute("href", src)
}

// Render (or update) the three animated flow dots for one path. Duration state
// is kept on the calling controller's `efLastDur` map so unchanged flows are not
// redrawn. Respects prefers-reduced-motion by placing static dots instead.
export function efSetDots(controller, targetName, path, color, w, len) {
  const target = controller[targetName]
  if (!target) return
  const dur = efDur(w, len)
  const prev = controller.efLastDur[targetName]
  const changed = dur === null ? prev != null : prev == null || Math.abs(dur - prev) / prev > 0.05
  if (!changed) return
  controller.efLastDur[targetName] = dur
  target.innerHTML = ""
  if (!dur) return

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  for (let i = 0; i < 3; i++) {
    const c = document.createElementNS("http://www.w3.org/2000/svg", "circle")
    c.setAttribute("r", "4.5")
    c.setAttribute("fill", color)
    if (reduceMotion) {
      c.style.cssText = `offset-path:path("${path}");offset-distance:${25 + i * 25}%`
      target.appendChild(c)
    } else {
      c.style.cssText = `offset-path:path("${path}")`
      target.appendChild(c)
      c.animate(
        [{ offsetDistance: "0%" }, { offsetDistance: "100%" }],
        { duration: dur * 1000, delay: -(i * dur / 3) * 1000, iterations: Infinity, easing: "linear" }
      )
    }
  }
}
