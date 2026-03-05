import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  static values = { text: String }

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => {
      const btn = this.buttonTarget
      const original = btn.innerHTML
      btn.innerHTML = "Copied!"
      btn.classList.add("copied")
      setTimeout(() => {
        btn.innerHTML = original
        btn.classList.remove("copied")
      }, 1500)
    })
  }
}
