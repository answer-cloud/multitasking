import { Controller } from "@hotwired/stimulus"

// The task list, and the small party that happens when you tick something off.
//
//   <div data-controller="checklist" data-checklist-count-value="2"
//        data-action="turbo:before-stream-render@document->checklist#holdStream
//                     turbo:submit-end->checklist#settled">
//     <ul data-checklist-target="list">
//       <li data-checklist-item>
//         <form action="/tasks/1/completion" method="post">
//           <button type="submit" data-action="checklist#check">…</button>
//         </form>
//       </li>
//     </ul>
//     <span data-checklist-target="count">2</span>
//     <button data-checklist-target="sound" data-action="checklist#toggleSound">Sound on</button>
//     <p data-checklist-target="cheer"></p>
//   </div>
//
// The checkbox is a real submit button, so ticking works without JavaScript.
// This controller submits the same form, then plays the tick, the confetti,
// the chime and the send-off while the request is in flight. The server's
// Turbo Stream would yank the row out mid-animation, so holdStream makes it
// wait for the send-off to finish.
//
// Everything visual respects prefers-reduced-motion; the sound has its own
// switch and remembers it.
const CHEERS = [
  "Boom. One less thing.",
  "Into the jar it goes.",
  "Look at you go.",
  "The list grows weaker.",
  "Tidy.",
  "Another one bites the dust.",
  "Chef’s kiss.",
  "Satisfying, isn’t it?",
  "Gone. Poof.",
  "That’s the stuff.",
  "Your future self says thanks."
]

const MILESTONES = {
  1: "First one! The seal is broken.",
  3: "Hat trick. 🎩",
  5: "Five! High five. ✋",
  10: "Ten today. Absolute unit of a day.",
  15: "Fifteen. Are you even real?",
  25: "Twenty-five. Legend status unlocked."
}

const SHAPES = ["square", "strip", "star"]
const COLOURS = ["accent", "positive", "caution", "sun", "sky"]
const STARS = ["✦", "★", "✧", "✶"]
const SOUND_KEY = "multitasking:sound"

const pick = (list) => list[Math.floor(Math.random() * list.length)]
const between = (min, max) => min + Math.random() * (max - min)

export default class extends Controller {
  static targets = ["list", "count", "cheer", "sound"]
  static values = { count: Number }

  connect() {
    this.departures = new WeakMap()
    this.lastDeparture = null
    this.soundOn = this.readSound()
    this.renderSound()
  }

  disconnect() {
    clearTimeout(this.cheerTimer)
  }

  check(event) {
    event.preventDefault()

    const button = event.currentTarget
    const item = button.closest("[data-checklist-item]")
    if (item.classList.contains("is-leaving")) return

    item.classList.add("is-checked", "is-leaving")
    button.setAttribute("aria-checked", "true")
    button.form.requestSubmit()

    const finale = this.remaining === 0
    this.countValue += 1
    this.chime(finale)
    this.burst(button, finale ? 90 : 28)
    this.cheer(finale ? "Inbox zero! ✦ Go do something fun." : MILESTONES[this.countValue] || pick(CHEERS))
    this.depart(item, this.sendOff(item))
  }

  uncheck(event) {
    event.preventDefault()

    const button = event.currentTarget
    const item = button.closest("[data-checklist-item]")
    if (item.classList.contains("is-leaving")) return

    item.classList.remove("is-done")
    item.classList.add("is-leaving")
    button.setAttribute("aria-checked", "false")
    button.form.requestSubmit()

    this.countValue = Math.max(0, this.countValue - 1)
    this.boing()
    this.cheer("Back on the list. No judgement.")
    this.depart(item, this.fadeOut(item))
  }

  // Hold every stream until the current send-off has finished, so the row
  // leaves, then the jar fills, in that order. Streams that arrive with no
  // animation running render at once.
  holdStream(event) {
    const departure = this.lastDeparture
    if (!departure) return

    const render = event.detail.render
    event.detail.render = async (stream) => {
      await departure
      render(stream)
    }
  }

  settled(event) {
    const item = event.target.closest("[data-checklist-item]")

    if (item && !event.detail.success) return this.restore(item)
    if (!item && event.detail.success) this.plip()
  }

  toggleSound(event) {
    event.preventDefault()

    this.soundOn = !this.soundOn
    try { localStorage.setItem(SOUND_KEY, this.soundOn ? "on" : "off") } catch {}
    this.renderSound()
    if (this.soundOn) this.plip()
  }

  countValueChanged(value, previous) {
    if (!this.hasCountTarget) return

    this.countTarget.textContent = value
    if (previous === undefined || this.calm) return

    this.countTarget.animate([
      { transform: "scale(1) rotate(0)" },
      { transform: "scale(1.6) rotate(-8deg)", offset: 0.35 },
      { transform: "scale(0.9) rotate(4deg)", offset: 0.7 },
      { transform: "scale(1) rotate(0)" }
    ], { duration: 520, delay: 600, easing: "ease-out" })
  }

  // --- The send-off ---------------------------------------------------------

  depart(item, animation) {
    const departure = animation.catch(() => {})
    this.departures.set(item, departure)
    this.lastDeparture = departure
    departure.then(() => {
      if (this.lastDeparture === departure) this.lastDeparture = null
    })
  }

  // The tick draws and the line strikes through in CSS. Then the row hops,
  // winds up, and zips off towards the jar, and the gap closes behind it.
  async sendOff(item) {
    if (this.calm) return this.fadeOut(item, 500)

    await item.animate([
      { transform: "translateY(0) rotate(0)" },
      { transform: "translateY(-7px) rotate(-1.5deg)", offset: 0.4 },
      { transform: "translateY(1px) rotate(0.6deg)", offset: 0.75 },
      { transform: "translateY(0) rotate(0)" }
    ], { duration: 420, delay: 320, easing: "ease-out" }).finished

    await item.animate([
      { transform: "translateX(0) rotate(0)", opacity: 1 },
      { transform: "translateX(-14px) rotate(-1deg)", opacity: 1, offset: 0.25 },
      { transform: "translateX(110%) rotate(5deg)", opacity: 0 }
    ], { duration: 460, easing: "cubic-bezier(.55, 0, .75, .2)", fill: "forwards" }).finished

    await this.collapse(item)
  }

  async fadeOut(item, delay = 150) {
    await item.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 260, delay, fill: "forwards" }).finished
    await this.collapse(item)
  }

  collapse(item) {
    const height = `${item.offsetHeight}px`

    return item.animate([
      { height, paddingBlock: getComputedStyle(item).paddingBlock },
      { height: "0px", paddingBlock: "0px" }
    ], { duration: this.calm ? 1 : 220, easing: "ease-in-out", fill: "forwards" }).finished
  }

  // The request failed: put the row back as it was and say so.
  restore(item) {
    item.getAnimations().forEach((animation) => animation.cancel())
    const checking = item.classList.contains("is-checked")
    item.classList.remove("is-checked", "is-leaving")
    if (!checking) item.classList.add("is-done")
    item.querySelector("[role=checkbox]")?.setAttribute("aria-checked", checking ? "false" : "true")
    this.countValue += checking ? -1 : 1
    this.cheer("Hmm, that didn’t stick. Try again?")
  }

  get remaining() {
    return this.listTarget.querySelectorAll("[data-checklist-item]:not(.is-leaving)").length
  }

  get calm() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  // --- Confetti -------------------------------------------------------------

  burst(origin, pieces) {
    if (this.calm) return

    const box = origin.getBoundingClientRect()
    const x = box.left + box.width / 2
    const y = box.top + box.height / 2
    const power = pieces > 40 ? 2.2 : 1

    const layer = document.createElement("div")
    layer.className = "confetti"
    layer.setAttribute("aria-hidden", "true")
    document.body.append(layer)

    const flights = Array.from({ length: pieces }, () => {
      const shape = pick(SHAPES)
      const piece = document.createElement("span")
      piece.className = `confetti__piece confetti__piece--${shape} confetti__piece--${pick(COLOURS)}`
      if (shape === "star") piece.textContent = pick(STARS)
      piece.style.left = `${x}px`
      piece.style.top = `${y}px`
      layer.append(piece)

      // Mostly up and out, a few sideways, then gravity wins.
      const angle = between(-Math.PI * 0.95, -Math.PI * 0.05)
      const speed = between(50, 170) * power
      const dx = Math.cos(angle) * speed
      const dy = Math.sin(angle) * speed
      const spin = between(-600, 600)

      return piece.animate([
        { transform: "translate(-50%, -50%) scale(0.4)", opacity: 1 },
        { transform: `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px)) rotate(${spin / 2}deg) scale(1)`, opacity: 1, offset: 0.4 },
        { transform: `translate(calc(-50% + ${dx * 1.35}px), calc(-50% + ${dy + 160 * power}px)) rotate(${spin}deg) scale(0.7)`, opacity: 0 }
      ], { duration: between(900, 1500), easing: "cubic-bezier(.15, .6, .35, 1)", fill: "forwards" }).finished
    })

    Promise.allSettled(flights).then(() => layer.remove())
  }

  // --- The cheer ------------------------------------------------------------

  cheer(message) {
    if (!this.hasCheerTarget) return

    const bubble = this.cheerTarget
    bubble.textContent = message
    bubble.classList.remove("is-showing")
    void bubble.offsetWidth
    bubble.classList.add("is-showing")

    clearTimeout(this.cheerTimer)
    this.cheerTimer = setTimeout(() => bubble.classList.remove("is-showing"), 2400)
  }

  // --- Sound ----------------------------------------------------------------
  // Synthesised on the spot with Web Audio: no files to load, nothing to fetch.

  readSound() {
    try { return localStorage.getItem(SOUND_KEY) !== "off" } catch { return true }
  }

  renderSound() {
    if (!this.hasSoundTarget) return

    this.soundTarget.textContent = this.soundOn ? "Sound on" : "Sound off"
    this.soundTarget.setAttribute("aria-pressed", this.soundOn)
  }

  get audio() {
    this.audioContext ||= new (window.AudioContext || window.webkitAudioContext)()
    return this.audioContext
  }

  tone(from, to, start, length, { type = "triangle", volume = 0.14 } = {}) {
    const at = this.audio.currentTime + start
    const oscillator = this.audio.createOscillator()
    const gain = this.audio.createGain()

    oscillator.type = type
    oscillator.frequency.setValueAtTime(from, at)
    if (to !== from) oscillator.frequency.exponentialRampToValueAtTime(to, at + length * 0.8)
    gain.gain.setValueAtTime(0.0001, at)
    gain.gain.exponentialRampToValueAtTime(volume, at + 0.012)
    gain.gain.exponentialRampToValueAtTime(0.0001, at + length)

    oscillator.connect(gain).connect(this.audio.destination)
    oscillator.start(at)
    oscillator.stop(at + length + 0.05)
  }

  play(sounds) {
    if (!this.soundOn) return

    try { sounds() } catch {}
  }

  // A pop, then a bright two-note ding. The finale is a little fanfare.
  chime(finale) {
    this.play(() => {
      this.tone(900, 160, 0, 0.09, { type: "sine", volume: 0.22 })
      const notes = finale ? [523.25, 659.25, 783.99, 1046.5, 1318.51, 1567.98] : [783.99, 1174.66]
      notes.forEach((note, i) => this.tone(note, note, 0.05 + i * 0.085, finale ? 0.5 : 0.32))
    })
  }

  plip() {
    this.play(() => {
      this.tone(520, 880, 0, 0.12, { type: "sine", volume: 0.12 })
    })
  }

  boing() {
    this.play(() => {
      this.tone(420, 140, 0, 0.3, { type: "sine", volume: 0.16 })
    })
  }
}
