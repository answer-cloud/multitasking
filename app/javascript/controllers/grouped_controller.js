import { Controller } from "@hotwired/stimulus"

// Keeps each task under its project in the dashboard's by-project view.
//
//   <div data-controller="grouped">
//     <ul id="tasks" hidden></ul>
//     <template data-grouped-target="template"><section>…<h3></h3><ul></ul></section></template>
//     <section data-project-id="5" data-name="api" data-grouped-target="group">
//       <h3>Api</h3>
//       <ul><li data-checklist-item>… <span data-project-id="5">Api</span> …</li></ul>
//     </section>
//   </div>
//
// The server draws the groups. Its streams do not know which view a page is
// in: they prepend new and reopened tasks to #tasks, here an empty intake,
// and swap a row's project chip when it moves. This watches for both and
// files the row on top of the group its chip names, making that group if it
// is the project's first.
export default class extends Controller {
  static targets = ["group", "template"]

  connect() {
    this.observer = new MutationObserver(() => this.file())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer.disconnect()
  }

  // Moving a row is a mutation too, so this runs again after it; by then
  // every row is in place and it does nothing.
  file() {
    this.element.querySelectorAll("[data-checklist-item]:not(.is-leaving)").forEach((row) => {
      const chip = row.querySelector("[data-project-id]")
      if (!chip) return

      const list = this.groupFor(chip).querySelector("ul")
      if (row.parentElement !== list) list.prepend(row)
    })
  }

  groupFor(chip) {
    const id = chip.dataset.projectId
    return this.groupTargets.find((group) => group.dataset.projectId === id) || this.addGroup(chip)
  }

  // Where the server would have put it: A to Z, Other last.
  addGroup(chip) {
    const group = this.templateTarget.content.firstElementChild.cloneNode(true)
    const name = chip.textContent.trim().toLowerCase()
    group.dataset.projectId = chip.dataset.projectId
    group.dataset.name = name
    group.querySelector("h3").innerHTML = chip.innerHTML

    const next = chip.dataset.projectId && this.groupTargets.find((other) => !other.dataset.projectId || other.dataset.name > name)
    next ? next.before(group) : this.element.append(group)
    return group
  }
}
