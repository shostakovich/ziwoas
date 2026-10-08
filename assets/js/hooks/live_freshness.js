const TICK_MS = 10_000

export default {
  mounted() {
    this.beat = this.el.dataset.beat
    this.lastBeatAt = Date.now()
    this.timer = setInterval(() => this.check(), TICK_MS)
    this.onWake = () => this.check()
    window.addEventListener("pageshow", this.onWake)
    document.addEventListener("visibilitychange", this.onWake)
  },

  updated() {
    if (this.el.dataset.beat !== this.beat) {
      this.beat = this.el.dataset.beat
      this.lastBeatAt = Date.now()
    }
    this.check()
  },

  destroyed() {
    clearInterval(this.timer)
    window.removeEventListener("pageshow", this.onWake)
    document.removeEventListener("visibilitychange", this.onWake)
  },

  // Through the hook's JS commands, so the class outlives the next patch.
  check() {
    const stale = Date.now() - this.lastBeatAt > this.thresholdMs()
    if (stale === this.el.classList.contains("live-stale")) return
    if (stale) this.js().addClass(this.el, "live-stale")
    else this.js().removeClass(this.el, "live-stale")
  },

  thresholdMs() {
    return Number(this.el.dataset.thresholdS || 120) * 1000
  },
}
