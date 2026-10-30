import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Asks data-turbo-confirm questions in our own dialog instead of the
// browser's grey alert. Nothing on the button changes: Turbo hands every
// confirm to this controller once it is on the page, and without JavaScript
// the form simply submits.
//
//   <dialog class="confirm" data-controller="confirm" data-action="close->confirm#settle">
//     <form method="dialog">
//       <p data-confirm-target="message"></p>
//       <button value="cancel">Cancel</button>
//       <button value="confirm" data-confirm-target="accept">Delete</button>
//     </form>
//   </dialog>
//
// The accept button borrows the label of the button that asked, so "Delete
// task" is answered by "Delete task" rather than a vague "OK".
export default class extends Controller {
  static targets = ["message", "accept"]

  connect() {
    this.confirm = (message, _form, submitter) => this.ask(message, submitter)
    Turbo.config.forms.confirm = this.confirm
  }

  // Only if it is still ours: on a Turbo visit the next page's dialog may
  // already have taken over.
  disconnect() {
    if (Turbo.config.forms.confirm === this.confirm) Turbo.config.forms.confirm = undefined
    this.answer?.(false)
  }

  ask(message, submitter) {
    this.messageTarget.textContent = message
    this.acceptTarget.textContent = submitter?.textContent.trim() || "Yes"
    this.element.returnValue = ""
    this.element.showModal()

    return new Promise((resolve) => { this.answer = resolve })
  }

  // Fires however the dialog closes — either button, or Esc.
  settle() {
    this.answer?.(this.element.returnValue === "confirm")
    this.answer = null
  }

  // A click on the backdrop lands on the dialog itself, not on the panel.
  dismiss(event) {
    if (event.target === this.element) this.element.close()
  }
}
