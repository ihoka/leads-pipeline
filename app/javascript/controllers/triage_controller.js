import { Controller } from "@hotwired/stimulus"

// Keyboard-first triage. The queue is meant to be worked without the mouse:
// j/k to move, a/d/s to decide.
export default class extends Controller {
  static targets = ["row", "advance", "disqualify", "snooze"]
  static values = { selected: Number }

  connect() {
    this.index = Math.max(0, this.rowTargets.findIndex((row) => row.classList.contains("is-selected")))
    this.onKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  handleKeydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (["INPUT", "TEXTAREA", "SELECT"].includes(event.target.tagName)) return

    const actions = {
      j: () => this.move(1),
      k: () => this.move(-1),
      a: () => this.decide("advance"),
      d: () => this.decide("disqualify"),
      s: () => this.decide("snooze")
    }

    const action = actions[event.key]
    if (!action) return

    event.preventDefault()
    action()
  }

  move(offset) {
    if (this.rowTargets.length === 0) return

    const next = Math.min(Math.max(this.index + offset, 0), this.rowTargets.length - 1)
    if (next === this.index) return

    this.index = next
    this.select()
  }

  select() {
    this.rowTargets.forEach((row, position) => {
      row.classList.toggle("is-selected", position === this.index)
    })

    const row = this.rowTargets[this.index]
    row.scrollIntoView({ block: "nearest" })
    row.querySelector("a")?.click()
  }

  decide(kind) {
    const targets = {
      advance: this.hasAdvanceTarget && this.advanceTarget,
      disqualify: this.hasDisqualifyTarget && this.disqualifyTarget,
      snooze: this.hasSnoozeTarget && this.snoozeTarget
    }

    targets[kind]?.click()
  }
}
