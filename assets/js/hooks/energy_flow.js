import { EnergyFlowView } from "../lib/energy_flow_view.js"

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
