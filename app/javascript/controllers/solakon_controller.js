import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "epsToggle", "epsState", "epsPower", "epsVoltage", "epsError",
    "controlToggle", "controlState", "controlHelp", "controlError",
  ]

  async toggleEps(event) {
    const desired = event.target.checked
    this._hideError(this.epsErrorTarget)
    try {
      const response = await fetch("/solakon/eps", {
        method: "PATCH",
        headers: this._jsonHeaders(),
        body: JSON.stringify({ enabled: desired }),
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Schalten fehlgeschlagen")
      this.epsStateTarget.textContent = data.enabled ? "An" : "Aus"
      event.target.checked = data.enabled
    } catch (error) {
      event.target.checked = !desired
      this._showError(this.epsErrorTarget, error.message)
    }
  }

  async toggleControl(event) {
    const desired = event.target.checked
    this._hideError(this.controlErrorTarget)
    try {
      const response = await fetch("/solakon/control", {
        method: "PATCH",
        headers: this._jsonHeaders(),
        body: JSON.stringify({ active: desired }),
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Umschalten fehlgeschlagen")
      event.target.checked = data.active
      this.controlStateTarget.textContent = data.active ? "Aktiv" : "Pausiert"
      this.controlHelpTarget.textContent = data.active ? "folgt dem gemessenen Verbrauch" : "pausiert"
    } catch (error) {
      event.target.checked = !desired
      this._showError(this.controlErrorTarget, error.message)
    }
  }

  _jsonHeaders() {
    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content,
    }
  }

  _showError(target, message) {
    target.textContent = message
    target.hidden = false
  }

  _hideError(target) {
    target.textContent = ""
    target.hidden = true
  }
}
