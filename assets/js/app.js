import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

import { currentLook } from "./lib/look.js"

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

// The look rides along on every join, so a page reached by live navigation knows a switched look.
const params = () => ({ _csrf_token: csrfToken, look: currentLook() })
const liveSocket = new LiveSocket("/live", Socket, { params, hooks })

liveSocket.connect()
window.liveSocket = liveSocket
