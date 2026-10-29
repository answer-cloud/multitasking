import { Controller } from "@hotwired/stimulus"

// The quick-add box. Type and press Enter, or press the microphone and say it.
//
// Shortcuts, anywhere on the page:
//   /      jump to the box (ignored while typing in another field)
//   Alt+V  start talking; press again to add what you said (Option+V on a Mac)
//   Esc    stop talking and throw it away
//
// Alt+V rather than a bare letter because the box has focus on load, where a
// letter would just be typed. It is matched on `code`, not `key`, because
// Option+V on a Mac produces "√".
//
//   <form data-controller="quick-add"
//         data-action="turbo:submit-end->quick-add#reset keydown@document->quick-add#shortcut">
//     <input type="hidden" data-quick-add-target="source" value="typed">
//     <input data-quick-add-target="input">
//     <button type="button" hidden data-quick-add-target="mic" data-action="quick-add#listen">Mic</button>
//   </form>
//
// Voice uses the browser's own speech recognition, so nothing is recorded or
// sent anywhere by this app. Browsers without it never see the microphone.
export default class extends Controller {
  static targets = ["input", "source", "mic", "hint"]

  connect() {
    this.Recognition = window.SpeechRecognition || window.webkitSpeechRecognition
    if (!this.Recognition) return

    this.micTarget.hidden = false
    this.element.classList.add("has-voice")
  }

  disconnect() {
    this.recognition?.abort()
  }

  shortcut(event) {
    if (event.altKey && event.code === "KeyV" && !event.metaKey && !event.ctrlKey) return this.listen(event)
    if (event.key === "Escape" && this.recognition) return this.cancel(event)
    if (event.key !== "/" || event.target.closest("input, textarea, select, [contenteditable]")) return

    event.preventDefault()
    this.inputTarget.focus()
  }

  listen(event) {
    event.preventDefault()
    if (!this.Recognition) return

    if (this.recognition) return this.recognition.stop()

    const recognition = new this.Recognition()
    recognition.lang = navigator.language || "en-US"
    recognition.interimResults = true
    recognition.continuous = false

    recognition.onresult = (result) => {
      this.inputTarget.value = Array.from(result.results).map((r) => r[0].transcript).join("")
    }
    recognition.onerror = (error) => {
      if (error.error === "not-allowed") this.hintTarget.textContent = "The microphone is blocked. Allow it in the address bar, then try again."
    }
    recognition.onend = () => this.heard()

    this.recognition = recognition
    this.cancelled = false
    this.hintHTML = this.hintTarget.innerHTML
    this.hintTarget.textContent = "Listening… press the shortcut again to add it, or Esc to cancel."
    this.inputTarget.value = ""
    this.inputTarget.placeholder = "Listening…"
    this.micTarget.classList.add("is-listening")
    this.micTarget.setAttribute("aria-pressed", "true")
    recognition.start()
  }

  cancel(event) {
    event.preventDefault()

    this.cancelled = true
    this.recognition.abort()
  }

  // Whatever was said goes straight in. Misheard? It is one click to fix.
  heard() {
    this.recognition = null
    this.micTarget.classList.remove("is-listening")
    this.micTarget.setAttribute("aria-pressed", "false")
    this.inputTarget.placeholder = "What needs doing?"
    if (this.hintHTML !== undefined && this.hintTarget.textContent.startsWith("Listening")) this.hintTarget.innerHTML = this.hintHTML

    if (this.cancelled) this.inputTarget.value = ""
    if (this.inputTarget.value.trim() === "") return

    this.sourceTarget.value = "voice"
    this.element.requestSubmit()
  }

  reset(event) {
    if (!event.detail.success) return

    this.element.reset()
    this.sourceTarget.value = "typed"
    this.inputTarget.focus()
  }
}
