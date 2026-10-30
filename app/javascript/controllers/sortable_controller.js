import { Controller } from "@hotwired/stimulus"

// Drag a task up or down the list by its handle, or focus the handle and use
// the arrow keys. Where it lands is saved at once.
//
//   <ul data-controller="sortable">
//     <li>
//       <button type="button" data-sortable-target="handle" data-url="/tasks/1/position"
//               data-action="pointerdown->sortable#grab pointermove->sortable#move
//                            pointerup->sortable#drop lostpointercapture->sortable#drop
//                            keydown->sortable#nudge">Move</button>
//     </li>
//   </ul>
//
// The dragged row is never taken out of the page: its neighbours move around
// it instead. Taking it out would drop the pointer capture that keeps the
// drag going when the pointer leaves the handle.
//
// A neighbour that moves is re-inserted, which would replay its drop-in
// animation, so it is marked settled first.
export default class extends Controller {
  static targets = ["handle"]

  connect() {
    this.element.classList.add("is-sortable")
  }

  grab(event) {
    if (event.button !== 0) return
    event.preventDefault()

    this.item = event.currentTarget.closest("li")
    this.from = this.indexOf(this.item)
    event.currentTarget.setPointerCapture(event.pointerId)
    this.item.classList.add("is-dragging")
  }

  // Past the middle of a neighbour, swap with it. A loop, because a fast drag
  // can cross several rows between two events.
  move(event) {
    if (!this.item) return

    let above, below
    while ((above = this.item.previousElementSibling) && event.clientY < this.middleOf(above)) this.pass(this.item, above, "after")
    while ((below = this.item.nextElementSibling) && event.clientY > this.middleOf(below)) this.pass(this.item, below, "before")
  }

  drop() {
    if (!this.item) return

    const item = this.item
    this.item = null
    item.classList.remove("is-dragging")
    if (this.indexOf(item) !== this.from) this.save(item)
  }

  nudge(event) {
    const item = event.currentTarget.closest("li")
    const sibling = { ArrowUp: item.previousElementSibling, ArrowDown: item.nextElementSibling }[event.key]
    if (!sibling) return
    event.preventDefault()

    this.pass(item, sibling, event.key === "ArrowUp" ? "after" : "before")
    this.save(item)
  }

  // Moves a neighbour to the other side of `row`: "after" puts it below, so
  // the row goes up.
  pass(row, sibling, side) {
    sibling.classList.add("is-settled")
    row[side](sibling)
  }

  save(item) {
    const handle = this.handleTargets.find((target) => item.contains(target))

    fetch(handle.dataset.url, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken },
      body: JSON.stringify({ position: this.indexOf(item) })
    })
  }

  // Counted the way the server counts: rows on their way to the jar are
  // already done there.
  indexOf(item) {
    return Array.from(this.element.children).filter((row) => !row.classList.contains("is-checked")).indexOf(item)
  }

  middleOf(row) {
    const box = row.getBoundingClientRect()
    return box.top + box.height / 2
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
