// Connects to data-controller="settings-dialog" on a streamed-in
// <dialog class="modal">: opens it as a modal and removes it once it closes,
// so the gear can stream a fresh one in again. Esc and closedby="any" close it
// natively; the backdrop action covers browsers without closedby.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Removed right away before Turbo caches the page: a dialog left in the
  // snapshot would open itself again on a back navigation.
  connect() {
    this.beforeCache = () => this.remove()
    document.addEventListener("turbo:before-cache", this.beforeCache)
    if (!this.element.open) this.element.showModal()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  close(event) {
    event?.preventDefault()
    if (this.element.open) this.element.close()
    else this.remove()
  }

  // .modal-dialog lets clicks through, so a click that lands on the dialog
  // element itself is a click on the backdrop.
  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  remove() { this.element.remove() }
}
