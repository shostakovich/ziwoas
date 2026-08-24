import consumer from "channels/consumer"

const POLL_MS     = 30_000
const AGE_TICK_MS = 10_000

class LiveFeed {
  constructor() {
    this.subscribers = new Set()
    this.reset()
  }

  reset() {
    this.plugs          = new Map()
    this.energyFlow     = null
    this.offlineAfterS  = null
    this.staleAfterS    = null
    this.clockOffsetMs  = 0
    this.lastSyncAt     = null
    this.lastSyncTs     = null
    this.lastSignature  = null
    this.subscription   = null
    this.pollTimer      = null
    this.ageTimer       = null
  }

  subscribe(handlers) {
    this.subscribers.add(handlers)
    if (this.subscribers.size === 1) this.start()
    else if (this.energyFlow) this.deliver(handlers, this.state())
    return () => this.unsubscribe(handlers)
  }

  unsubscribe(handlers) {
    this.subscribers.delete(handlers)
    if (this.subscribers.size === 0) this.stop()
  }

  start() {
    this.subscription = consumer.subscriptions.create("DashboardChannel", {
      connected: () => this.refresh({ resyncIfOutOfTouch: true }),
      received: (data) => this.receive(data),
    })

    this._onVisibilityChange = () => {
      if (document.visibilityState === "visible") this.refresh({ resyncIfOutOfTouch: true })
    }
    this._onPageShow = () => this.refresh({ resyncIfOutOfTouch: true })
    this._onOnline   = () => this.refresh({ resyncIfOutOfTouch: true })

    document.addEventListener("visibilitychange", this._onVisibilityChange)
    window.addEventListener("pageshow", this._onPageShow)
    window.addEventListener("online", this._onOnline)

    this.pollTimer = setInterval(() => this.refresh(), POLL_MS)
    this.ageTimer  = setInterval(() => this.emitIfAged(), AGE_TICK_MS)

    this.refresh()
  }

  stop() {
    this.subscription?.unsubscribe()
    clearInterval(this.pollTimer)
    clearInterval(this.ageTimer)
    document.removeEventListener("visibilitychange", this._onVisibilityChange)
    window.removeEventListener("pageshow", this._onPageShow)
    window.removeEventListener("online", this._onOnline)
    this.reset()
  }

  async refresh({ resyncIfOutOfTouch = false } = {}) {
    const wasOutOfTouch = this.outOfTouch()
    try {
      const response = await fetch("/api/live")
      if (!response.ok) return
      const data = await response.json()

      this.clockOffsetMs = data.now_ts * 1000 - Date.now()
      this.offlineAfterS = data.offline_after_s
      this.staleAfterS   = data.stale_after_s
      this.energyFlow    = data.energy_flow
      if (Array.isArray(data.plugs)) data.plugs.forEach((plug) => this.mergePlug(plug))

      this.sync(data.now_ts)
      this.emitState()
      if (resyncIfOutOfTouch && wasOutOfTouch) this.emitResync()
    } catch (e) {
      this.emitIfAged()
      console.error("liveFeed refresh failed:", e)
    }
  }

  receive(data) {
    if (data.solakon) return void this.refresh()
    if (!Array.isArray(data.plugs)) return

    data.plugs.forEach((plug) => this.mergePlug(plug))
    this.sync(this.serverNowTs())
    this.emitState()
    this.subscribers.forEach((handlers) => handlers.onDelta?.(data.plugs))
  }

  mergePlug(update) {
    if (!update.id) return
    const current = this.plugs.get(update.id)
    if (current && (update.last_seen_ts || 0) < (current.last_seen_ts || 0)) return
    this.plugs.set(update.id, { ...current, ...update })
  }

  sync(serverTs) {
    this.lastSyncAt = Date.now()
    this.lastSyncTs = serverTs
  }

  serverNowTs() { return (Date.now() + this.clockOffsetMs) / 1000 }

  referenceTs() { return this.outOfTouch() ? this.lastSyncTs : this.serverNowTs() }

  plugOnline(plug) {
    if (plug.last_seen_ts == null || this.offlineAfterS == null) return false
    return this.referenceTs() - plug.last_seen_ts <= this.offlineAfterS
  }

  solakonOnline(flow) {
    if (!flow?.solakon_online) return false
    if (flow.reading_ts == null || this.staleAfterS == null) return false
    return this.referenceTs() - flow.reading_ts <= this.staleAfterS
  }

  outOfTouch() {
    if (this.lastSyncAt == null || this.offlineAfterS == null) return false
    return Date.now() - this.lastSyncAt > this.offlineAfterS * 1000
  }

  state() {
    const plugs = [...this.plugs.values()].map((plug) => ({
      ...plug,
      online: this.plugOnline(plug),
    }))
    const flow = this.energyFlow
      ? { ...this.energyFlow, solakon_online: this.solakonOnline(this.energyFlow) }
      : null

    return { plugs, energyFlow: flow, stale: this.outOfTouch() }
  }

  emitState() {
    const state = this.state()
    this.lastSignature = this.signature(state)
    this.subscribers.forEach((handlers) => this.deliver(handlers, state))
  }

  emitResync() {
    this.subscribers.forEach((handlers) => handlers.onResync?.())
  }

  emitIfAged() {
    const state = this.state()
    if (this.signature(state) === this.lastSignature) return
    this.lastSignature = this.signature(state)
    this.subscribers.forEach((handlers) => this.deliver(handlers, state))
  }

  signature(state) {
    const plugs = state.plugs.map((p) => `${p.id}:${p.online ? 1 : 0}`).join(",")
    return `${state.stale ? 1 : 0}|${state.energyFlow?.solakon_online ? 1 : 0}|${plugs}`
  }

  deliver(handlers, state) {
    handlers.onState?.(state)
  }
}

export default new LiveFeed()
