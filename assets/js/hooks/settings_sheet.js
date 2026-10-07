// The lamp settings sheet: a modal while it is rendered. Every way out (Escape, the
// backdrop, the close button, "Abbrechen" via data-dismiss) closes the dialog, and the
// close tells the LiveView to forget it, or its next patch would bring it back.
export default {
  mounted() {
    if (!this.el.open) this.el.showModal()
    this.el.addEventListener("close", () => this.pushEvent("close_settings", {}))
    this.el.addEventListener("click", (event) => {
      // .modal-dialog lets clicks through, so a click on the dialog element itself is on the backdrop.
      if (event.target === this.el || event.target.closest("[data-dismiss=dialog]")) {
        event.preventDefault()
        this.el.close()
      }
    })
  },
}
