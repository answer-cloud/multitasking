import { Controller } from "@hotwired/stimulus"

// Keeps the projects you hid off the dashboard's to-do lists.
//
//   <div data-controller="hidden-projects" data-hidden-projects-ids-value="[5, 9]">
//     <ul><li data-checklist-item>… <span data-project-id="5">Api</span> …</li></ul>
//   </div>
//
// The server leaves hidden projects out when it draws the page. Its streams
// go to the whole team and do not know what you hid, so a task an agent
// pushes in, or one you reopen, would land anyway. This takes those rows back
// out. Done rows stay: what got done today is counted whatever its project.
export default class extends Controller {
  static values = { ids: Array }

  connect() {
    this.observer = new MutationObserver(() => this.sweep())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer.disconnect()
  }

  sweep() {
    if (this.idsValue.length === 0) return

    const hidden = this.idsValue.map(String)
    this.element.querySelectorAll("[data-checklist-item]:not(.is-done)").forEach((row) => {
      const chip = row.querySelector("[data-project-id]")
      if (chip && hidden.includes(chip.dataset.projectId)) row.remove()
    })
  }
}
