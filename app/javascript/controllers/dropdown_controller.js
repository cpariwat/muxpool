import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.closeOnOutsideClick = this.closeOnOutsideClick.bind(this)
    this.closeOnEscape = this.closeOnEscape.bind(this)
  }

  toggle(event) {
    event.stopPropagation()
    if (this.menuTarget.hidden) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.menuTarget.hidden = false
    requestAnimationFrame(() => {
      document.addEventListener("click", this.closeOnOutsideClick)
      document.addEventListener("keydown", this.closeOnEscape)
    })
  }

  close() {
    this.menuTarget.hidden = true
    document.removeEventListener("click", this.closeOnOutsideClick)
    document.removeEventListener("keydown", this.closeOnEscape)
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  closeOnEscape(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick)
    document.removeEventListener("keydown", this.closeOnEscape)
  }
}
