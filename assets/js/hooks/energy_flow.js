import { EnergyFlowView } from "../lib/energy_flow_view.js"

// The SVG is phx-update="ignore"; the ring values outside it come back as placeholders on every patch.
export default {
  mounted() {
    this.view = new EnergyFlowView(this.el)
    this.render()
  },

  updated() {
    this.render()
  },

  render() {
    this.view.render(JSON.parse(this.el.dataset.state))
  },
}
