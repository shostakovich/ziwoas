import { EnergyFlowView } from "../lib/energy_flow_view.js"

// The energy flow card: the state arrives on data-state with every live beat. The SVG is
// phx-update="ignore", so its running dots survive the patch; the ring values outside it
// come back as the server's placeholders and are drawn again here.
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
