// Bundled by esbuild (config :esbuild in config/config.exs): phoenix and phoenix_live_view
// resolve through NODE_PATH to the Hex packages in deps/, everything else is relative.
// data-confirm on links, buttons and forms
import "phoenix_html"
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
