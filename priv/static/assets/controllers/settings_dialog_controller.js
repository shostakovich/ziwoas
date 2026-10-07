import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Removed before Turbo caches the page, or the snapshot would reopen it on a back navigation.
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

  // .modal-dialog lets clicks through, so a click on the dialog element itself is on the backdrop.
  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  remove() { this.element.remove() }
}
