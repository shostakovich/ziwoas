// Plain ES modules, resolved through the import map in the root layout (no bundler).
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { Application } from "@hotwired/stimulus"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const hooks = {
  // The lamp settings sheet removes itself when closed (Rails' settings-dialog
  // controller); the LiveView forgets it too, or its next patch would bring it back.
  SettingsSheet: {
    mounted() { this.el.addEventListener("close", () => this.pushEvent("close_settings", {})) }
  }
}

const liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken }, hooks })

liveSocket.connect()
window.liveSocket = liveSocket

// A link that is also a phx-click (the Solakon-Verlauf's range tabs) keeps Rails' href as the
// fallback; while LiveView is connected, its click event replaces the navigation.
document.addEventListener("click", (event) => {
  const link = event.target instanceof Element && event.target.closest("a[href][phx-click]")
  const plain = event.button === 0 && !(event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
  if (link && plain && liveSocket.isConnected()) event.preventDefault()
}, true)

// A switch that is also a phx-click (the PV page's EPS and Auto-Regelung) keeps Rails'
// data-action, whose Stimulus handler would PATCH as well; while LiveView is connected, its
// click event is the only one that switches.
document.addEventListener("change", (event) => {
  const control = event.target instanceof Element && event.target.closest("input[phx-click]")
  if (control && liveSocket.isConnected()) event.stopImmediatePropagation()
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

// The Stimulus controllers stay shared with Rails (app/javascript/controllers):
// every `controllers/*_controller` entry of the import map registers under its
// Stimulus identifier, as stimulus-loading does there.
const stimulus = Application.start()
window.Stimulus = stimulus
const { imports } = JSON.parse(document.querySelector("script[type='importmap']").textContent)

for (const name of Object.keys(imports)) {
  const match = name.match(/^controllers\/(.+)_controller$/)
  if (match) {
    import(name).then((module) => stimulus.register(match[1].replace(/_/g, "-"), module.default))
  }
}
