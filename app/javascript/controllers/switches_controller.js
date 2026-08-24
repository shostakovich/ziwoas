import { Controller } from "@hotwired/stimulus"
import liveFeed from "controllers/live_feed"

export default class extends Controller {
  connect() {
    this.unsubscribe = liveFeed.subscribe({
      onDelta: (updates) => updates.forEach((plug) => this.updateCard(plug)),
    })
  }

  disconnect() {
    this.unsubscribe?.()
  }

  updateCard(plug) {
    const card = this.element.querySelector(`[data-plug-id="${plug.id}"]`)
    if (!card) return

    const watt = card.querySelector(`[data-switches-watt="${plug.id}"]`)
    if (watt && typeof plug.apower_w === "number") {
      watt.textContent = `${Math.round(plug.apower_w)} W`
    }

    if (typeof plug.output === "boolean") {
      const knob = card.querySelector("button.sw-knob")
      if (knob) {
        knob.classList.toggle("off", !plug.output)
        knob.disabled = false
        const form = knob.closest("form")
        if (form) form.action = form.action.replace(/state=(on|off)/, `state=${plug.output ? "off" : "on"}`)
        const error = card.querySelector(".sw-error")
        if (error) error.textContent = ""
      }

      const wattChip = card.querySelector(`[data-switches-watt-chip="${plug.id}"]`)
      if (wattChip) wattChip.classList.toggle("hidden", !plug.output)

      card.classList.remove("sw-offline")
    }
  }
}
