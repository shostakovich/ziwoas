// The element that held focus is gone after the patch; the server names where it goes instead.
export default {
  mounted() {
    this.handleEvent("focus_return", ({ ids }) => {
      const target = ids
        .map((id) => document.getElementById(id))
        .find((el) => el && el.getClientRects().length > 0)

      target?.focus()
    })
  },
}
