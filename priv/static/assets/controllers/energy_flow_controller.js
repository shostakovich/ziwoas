import { Controller } from "@hotwired/stimulus"
import { EnergyFlowView } from "controllers/energy_flow"

// Thin wrapper around EnergyFlowView: the SVG and its running dot animations
// live inside this element and are never replaced. Turbo swaps only the hidden
// state carrier, and every swap re-connects the target with fresh data.
export default class extends Controller {
  static targets = ["state"]

  stateTargetConnected(element) {
    this.view ??= new EnergyFlowView(this.element)
    this.view.render(JSON.parse(element.dataset.state))
  }
}
