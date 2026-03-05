import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "form", "input"]

  connect() {
    this.formTarget.hidden = true
  }

  edit() {
    this.displayTarget.hidden = true
    this.formTarget.hidden = false
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  cancel() {
    this.formTarget.hidden = true
    this.displayTarget.hidden = false
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.cancel()
    }
  }
}
