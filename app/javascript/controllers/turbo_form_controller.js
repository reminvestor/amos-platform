import { Controller } from "@hotwired/stimulus"

// Auto-submits forms when inputs change, with debounce
export default class extends Controller {
  static targets = [ "form" ]
  
  connect() {
    this.timeout = null
    console.log("Turbo form controller connected")
  }
  
  submit() {
    // Debounce to prevent too many requests while typing
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.element.requestSubmit()
    }, 300)
  }
} 