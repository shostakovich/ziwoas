import { formatNumber, formatPercent } from "../lib/format.js"

const DEBOUNCE_MS = 250

// A lamp's tabs, brightness, white and colour. The tabs and panels are phx-update="ignore",
// so what the hand set here stays; the commands go to the LiveView as "light_command".
// Power, zones and the toast are server-rendered.
export default {
  mounted() {
    this.showTab("white")
    this.el.querySelectorAll("[data-light=brightness]").forEach(fill)
    this.onClick = (event) => this.click(event)
    this.onInput = (event) => this.input(event.target)
    this.el.addEventListener("click", this.onClick)
    this.el.addEventListener("input", this.onInput)
  },

  destroyed() {
    clearTimeout(this.debounceTimer)
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("input", this.onInput)
  },

  click(event) {
    const tab = event.target.closest("[role=tab][data-tab]")
    if (tab) return this.showTab(tab.dataset.tab)
    const preset = event.target.closest("button[data-temp]")
    if (preset) this.temp(preset.dataset.temp, { preset: true })
  },

  input(target) {
    if (target.matches("[data-light=brightness]")) this.brightness(target)
    else if (target.matches("[data-light=temp]")) this.temp(target.value)
    else if (target.matches("input[data-color]")) this.swatch(target.dataset.color)
    else if (target.matches("input[type=color]")) this.wheel(target.value)
  },

  showTab(name) {
    this.el.querySelectorAll("[role=tabpanel][data-tab]").forEach((panel) => { panel.hidden = panel.dataset.tab !== name })
    this.el.querySelectorAll("[role=tab][data-tab]").forEach((tab) => {
      const active = tab.dataset.tab === name
      tab.classList.toggle("active", active)
      tab.setAttribute("aria-selected", active)
    })
  },

  brightness(range) {
    fill(range)
    this.setText("brightness-value", formatPercent(range.value))
    this.send({ command: "brightness", value: range.value })
  },

  temp(kelvin, { preset = false } = {}) {
    const slider = this.el.querySelector("[data-light=temp]")
    if (slider && preset) slider.value = kelvin
    this.setText("temp-value", formatNumber(kelvin, { unit: "K" }))
    this.el.querySelectorAll("button[data-temp]").forEach((button) => {
      const active = button.dataset.temp === String(kelvin)
      button.classList.toggle("active", active)
      button.setAttribute("aria-pressed", active)
    })
    this.send({ command: "color_temp", temp_k: kelvin })
  },

  swatch(hex) {
    this.markCustom(null)
    this.sendHex(hex)
  },

  wheel(hex) {
    this.el.querySelectorAll("input[data-color]").forEach((radio) => { radio.checked = false })
    this.markCustom(hex)
    this.sendHex(hex)
  },

  markCustom(hex) {
    const wheel = this.el.querySelector("[data-light=wheel]")
    if (!wheel) return
    wheel.classList.toggle("ld-swatch-custom", !!hex)
    if (hex) wheel.style.setProperty("--ld-custom", hex)
  },

  sendHex(hex) {
    const [r, g, b] = [1, 3, 5].map((at) => parseInt(hex.slice(at, at + 2), 16))
    this.send({ command: "color", r, g, b })
  },

  setText(name, text) {
    const node = this.el.querySelector(`[data-light="${name}"]`)
    if (node) node.textContent = text
  },

  send(command) {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => {
      this.pushEvent("light_command", { light_key: this.el.dataset.key, ...command })
    }, DEBOUNCE_MS)
  },
}

// felt's .form-range draws its filled part up to --felt-form-range-fill.
function fill(range) {
  const share = (range.value - range.min) / (range.max - range.min) * 100
  range.style.setProperty("--felt-form-range-fill", `${share}%`)
}
