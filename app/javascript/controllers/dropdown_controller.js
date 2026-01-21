import { Controller } from "@hotwired/stimulus"

/**
 * Simple Dropdown Controller
 * Handles show/hide of dropdown menus
 */
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    // Close dropdown when clicking outside
    this.boundClickOutside = this.clickOutside.bind(this)
    document.addEventListener('click', this.boundClickOutside)
  }

  disconnect() {
    document.removeEventListener('click', this.boundClickOutside)
  }

  toggle(event) {
    event?.preventDefault()
    event?.stopPropagation()
    
    if (this.hasMenuTarget) {
      const isVisible = this.menuTarget.style.display !== 'none'
      this.menuTarget.style.display = isVisible ? 'none' : 'block'
    }
  }

  show() {
    if (this.hasMenuTarget) {
      this.menuTarget.style.display = 'block'
    }
  }

  hide() {
    if (this.hasMenuTarget) {
      this.menuTarget.style.display = 'none'
    }
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hide()
    }
  }
}


