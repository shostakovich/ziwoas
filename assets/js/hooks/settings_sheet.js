// Closing tells the LiveView to forget the sheet, or its next patch would bring it back.
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
