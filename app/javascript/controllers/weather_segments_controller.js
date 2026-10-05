import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="weather-segments"
// One instance per day-card. Manages single-select expansion of the four
// segment tiles into the matching hidden hour-row. Click same tile to
// collapse; click another to switch.
export default class extends Controller {
  static targets = ["tile", "hourRow"]
  static classes = ["selected"]

  connect() {
    this.selectedIndex = null
    this.render()
  }

  toggle(event) {
    const idx = Number(event.currentTarget.dataset.segmentIndex)
    this.selectedIndex = (this.selectedIndex === idx) ? null : idx
    this.render()
  }

  render() {
    this.tileTargets.forEach((tile) => {
      const idx = Number(tile.dataset.segmentIndex)
      const open = idx === this.selectedIndex
      this.selectedClasses.forEach((name) => tile.classList.toggle(name, open))
      tile.setAttribute("aria-expanded", open ? "true" : "false")
    })
    this.hourRowTargets.forEach((row) => {
      const idx = Number(row.dataset.segmentIndex)
      const open = idx === this.selectedIndex
      row.hidden = !open
    })
  }
}
