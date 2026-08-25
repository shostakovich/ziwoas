import { Controller } from "@hotwired/stimulus"

const TICK_MS = 10_000

// The one thing only the client can know: how long ago the last live
// broadcast arrived. Every live broadcast replaces the beat target; when the
// beats stop, the page dims (.live-stale) instead of showing watts nobody
// measured anymore. A beat after a long silence means missed broadcasts, so
// it fires a resync event the chart controllers reload from.
export default class extends Controller {
  static targets = ["beat"]
  static values = { thresholdS: { type: Number, default: 120 } }

  connect() {
    this.lastBeatAt ??= Date.now()
    this.timer = setInterval(() => this.check(), TICK_MS)
    this._onWake = () => this.check()
    window.addEventListener("pageshow", this._onWake)
    document.addEventListener("visibilitychange", this._onWake)
  }

  disconnect() {
    clearInterval(this.timer)
    window.removeEventListener("pageshow", this._onWake)
    document.removeEventListener("visibilitychange", this._onWake)
  }

  beatTargetConnected() {
    const gap = this.lastBeatAt ? Date.now() - this.lastBeatAt : 0
    this.lastBeatAt = Date.now()
    this.element.classList.remove("live-stale")
    if (gap > this.thresholdMs()) this.dispatch("resync", { target: document })
  }

  check() {
    this.element.classList.toggle("live-stale", Date.now() - this.lastBeatAt > this.thresholdMs())
  }

  thresholdMs() {
    return this.thresholdSValue * 1000
  }
}
