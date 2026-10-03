// Connects to data-controller="light-detail". Slim: tab switching + debounced
// fire-and-forget sliders/swatches/wheel. Zone/power/toast state is
// server-rendered via Turbo Streams (see app/components/lights/*).
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { key: String, tab: String }
  static targets = ["panel", "tab", "range", "temp", "preset"]

  connect() {
    this.showTab(this.tabValue || "white")
    this.rangeTargets.forEach((r) => this.fill(r))
  }

  tab(event) { this.showTab(event.params.tab) }

  showTab(name) {
    this.tabValue = name
    this.panelTargets.forEach((p) => { p.hidden = p.dataset.tab !== name })
    this.tabTargets.forEach((t) => {
      const active = t.dataset.lightDetailTabParam === name
      t.classList.toggle("active", active)
      t.setAttribute("aria-selected", active)
    })
  }

  brightness(event) {
    this.fill(event.target)
    this.debounce(() => this.send({ command: "brightness", value: event.target.value }))
  }

  // felt's .form-range draws its filled part up to --fill.
  fill(range) {
    const share = (range.value - range.min) / (range.max - range.min) * 100
    range.style.setProperty("--fill", `${share}%`)
  }

  temp(event) {
    const k = event.params.temp ?? event.target.value
    if (this.hasTempTarget && event.params.temp) this.tempTarget.value = k
    this.markActivePreset(k)
    this.debounce(() => this.send({ command: "color_temp", temp_k: k }))
  }

  markActivePreset(k) {
    this.presetTargets.forEach((b) => {
      const active = b.dataset.lightDetailTempParam === String(k)
      b.classList.toggle("active", active)
      b.setAttribute("aria-pressed", active)
    })
  }

  swatch(event) { this.applyHex(event.params.color) }
  wheel(event) { this.applyHex(event.target.value) }

  applyHex(hex) {
    const r = parseInt(hex.slice(1, 3), 16)
    const g = parseInt(hex.slice(3, 5), 16)
    const b = parseInt(hex.slice(5, 7), 16)
    this.debounce(() => this.send({ command: "color", r, g, b }))
  }

  debounce(fn) { clearTimeout(this._d); this._d = setTimeout(fn, 250) }

  send(body) {
    fetch(`/lights/${this.keyValue}/command`, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
      },
      body: new URLSearchParams(body).toString(),
    })
  }
}
