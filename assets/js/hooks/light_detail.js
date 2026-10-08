const DEBOUNCE_MS = 250

// The native picker fires while the hand moves, hence the debounce.
export default {
  mounted() {
    this.el.addEventListener("input", () => {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = setTimeout(() => this.send(this.el.value), DEBOUNCE_MS)
    })
  },

  destroyed() {
    clearTimeout(this.debounceTimer)
  },

  send(hex) {
    const [r, g, b] = [1, 3, 5].map((at) => parseInt(hex.slice(at, at + 2), 16))
    this.pushEvent("light_command", { command: "color", r, g, b })
  },
}
