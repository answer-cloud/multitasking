import { Controller } from "@hotwired/stimulus"

// The quick-add box. Type and press Enter, or press the microphone and say it.
//
//   <form data-controller="quick-add" data-action="turbo:submit-end->quick-add#reset">
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
    if (this.Recognition) this.micTarget.hidden = false
  }

  disconnect() {
    this.recognition?.abort()
  }

  focus(event) {
    if (event.target.closest("input, textarea, select, [contenteditable]")) return

    event.preventDefault()
    this.inputTarget.focus()
  }

  listen(event) {
    event.preventDefault()

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
    this.inputTarget.value = ""
    this.inputTarget.placeholder = "Listening…"
    this.micTarget.classList.add("is-listening")
    this.micTarget.setAttribute("aria-pressed", "true")
    recognition.start()
  }

  // Whatever was said goes straight in. Misheard? It is one click to fix.
  heard() {
    this.recognition = null
    this.micTarget.classList.remove("is-listening")
    this.micTarget.setAttribute("aria-pressed", "false")
    this.inputTarget.placeholder = "What needs doing?"

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
