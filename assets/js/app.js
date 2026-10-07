// Bundled by esbuild (config :esbuild in config/config.exs): phoenix and phoenix_live_view
// resolve through NODE_PATH to the Hex packages in deps/, everything else is relative.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

import EnergyFlow from "./hooks/energy_flow.js"
import EnergyReport from "./hooks/energy_report.js"
import HistoryChart from "./hooks/history_chart.js"
import LightDetail from "./hooks/light_detail.js"
import LiveFreshness from "./hooks/live_freshness.js"
import SensorsChart from "./hooks/sensors_chart.js"
import SettingsSheet from "./hooks/settings_sheet.js"
import SolakonHistory from "./hooks/solakon_history.js"
import TodayChart from "./hooks/today_chart.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const hooks = {
  EnergyFlow,
  EnergyReport,
  HistoryChart,
  LightDetail,
  LiveFreshness,
  SensorsChart,
  SettingsSheet,
  SolakonHistory,
  TodayChart,
}

const liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken }, hooks })

liveSocket.connect()
window.liveSocket = liveSocket

// A link that is also a phx-click (the Solakon-Verlauf's range tabs, the lamp's settings gear)
// keeps Rails' href as the fallback; while LiveView is connected, its click event replaces
// the navigation.
document.addEventListener("click", (event) => {
  const link = event.target instanceof Element && event.target.closest("a[href][phx-click]")
  const plain = event.button === 0 && !(event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
  if (link && plain && liveSocket.isConnected()) event.preventDefault()
}, true)

// Without Turbo, a LiveView form's data-turbo-confirm (the schedule's delete buttons) asks
// first; declining stops the submit before LiveView's own listener sees it.
document.addEventListener("submit", (event) => {
  const form = event.target
  const message = form instanceof HTMLFormElement && form.hasAttribute("phx-submit") && form.dataset.turboConfirm
  if (message && !window.confirm(message)) {
    event.preventDefault()
    event.stopImmediatePropagation()
  }
}, true)
