// Marks the chip of the room under the sticky bar while the page scrolls, and keeps it in view.
export default {
  mounted() {
    this.onScroll = () => {
      if (this.frame) return
      this.frame = requestAnimationFrame(() => {
        this.frame = null
        this.spy()
      })
    }
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.spy()
  },

  updated() {
    this.mark(this.current, false)
    this.spy()
  },

  destroyed() {
    window.removeEventListener("scroll", this.onScroll)
    if (this.frame) cancelAnimationFrame(this.frame)
  },

  chips() {
    return Array.from(this.el.querySelectorAll("[data-room]"))
  },

  spy() {
    const edge = this.el.getBoundingClientRect().bottom + 8
    let current = this.chips()[0]?.dataset.room

    for (const chip of this.chips()) {
      const room = document.getElementById(chip.dataset.room)
      if (room && room.getBoundingClientRect().top <= edge) current = chip.dataset.room
    }

    if (current !== this.current) {
      this.current = current
      this.mark(current, true)
    }
  },

  mark(id, reveal) {
    for (const chip of this.chips()) {
      if (chip.dataset.room !== id) {
        chip.removeAttribute("aria-current")
        continue
      }

      chip.setAttribute("aria-current", "location")
      if (reveal) {
        const left = chip.offsetLeft - (this.el.clientWidth - chip.offsetWidth) / 2
        this.el.scrollTo({ left, behavior: "instant" })
      }
    }
  },
}
