import { Controller } from "@hotwired/stimulus"

// The quick-add box. Type and press Enter, or press the microphone and say it.
//
// Shortcuts, anywhere on the page:
//   /             jump to the box (ignored while typing in another field)
//   Cmd+Shift+V   start talking; press again to add what you said
//                 (Ctrl+Shift+V off a Mac)
//   Esc           stop talking and throw it away
//
// A chord rather than a bare letter because the box has focus on load, where a
// letter would just be typed. It is matched on `code`, not `key`, so a keyboard
// layout that puts something else on V still works. The chord is also the
// browser's "paste as plain text"; here it means talk instead, which is the
// trade the shortcut was chosen for.
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
//
// Recognition runs continuously and this controller decides when you have
// finished: SILENCE_MS after the last word it heard. Left to itself the
// browser stops at the first breath, which added half a sentence.
const SILENCE_MS = 2500

export default class extends Controller {
  static targets = ["input", "source", "mic", "hint"]

  connect() {
    this.Recognition = window.SpeechRecognition || window.webkitSpeechRecognition
    if (!this.Recognition) return

    this.micTarget.hidden = false
    this.element.classList.add("has-voice")
  }

  disconnect() {
    clearTimeout(this.silence)
    this.recognition?.abort()
  }

  shortcut(event) {
    if (this.isTalkShortcut(event)) return this.listen(event)
    if (event.key === "Escape" && this.recognition) return this.cancel(event)
    if (event.key !== "/" || event.target.closest("input, textarea, select, [contenteditable]")) return

    event.preventDefault()
    this.inputTarget.focus()
  }

  isTalkShortcut(event) {
    const command = navigator.platform.startsWith("Mac") ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey
    return command && event.shiftKey && !event.altKey && event.code === "KeyV"
  }

  listen(event) {
    event.preventDefault()
    if (!this.Recognition) return

    if (this.recognition) return this.recognition.stop()

    const recognition = new this.Recognition()
    recognition.lang = navigator.language || "en-US"
    recognition.interimResults = true
    recognition.continuous = true

    recognition.onresult = (result) => {
      this.inputTarget.value = Array.from(result.results).map((r) => r[0].transcript).join("")
      this.waitForSilence()
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

  // Each word heard restarts the clock. Nothing heard at all never submits.
  waitForSilence() {
    clearTimeout(this.silence)
    this.silence = setTimeout(() => this.recognition?.stop(), SILENCE_MS)
  }

  cancel(event) {
    event.preventDefault()

    this.cancelled = true
    this.recognition.abort()
  }

  // Whatever was said goes straight in. Misheard? It is one click to fix.
  heard() {
    clearTimeout(this.silence)
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
