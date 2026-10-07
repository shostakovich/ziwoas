const TICK_MS = 10_000

export const RESYNC_EVENT = "live-freshness:resync"

// The one thing only the client can know: how long ago the last live broadcast arrived.
// Every broadcast moves data-beat; when the beats stop, the page dims (.live-stale) instead
// of showing watts nobody measured anymore. A beat after a long silence means missed
// broadcasts, so it fires RESYNC_EVENT on the document, which the chart hooks reload from.
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
      const gap = Date.now() - this.lastBeatAt
      this.lastBeatAt = Date.now()
      if (gap > this.thresholdMs()) document.dispatchEvent(new CustomEvent(RESYNC_EVENT))
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
