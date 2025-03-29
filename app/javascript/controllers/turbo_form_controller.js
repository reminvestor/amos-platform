import { Controller } from "@hotwired/stimulus"

// Auto-submits forms when inputs change, with debounce
export default class extends Controller {
  static targets = [ "form" ]
  
  connect() {
    console.log("Turbo form controller connected")
    this.timeout = null
  }
  
  submit() {
    // Debounce to prevent too many requests while typing
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      // Get all form data
      const formData = new FormData(this.element)
      
      // Build the URL with params
      const url = new URL(this.element.action)
      for (const [key, value] of formData.entries()) {
        url.searchParams.append(key, value)
      }
      
      // Make the Turbo Visit
      Turbo.visit(url.toString())
    }, 300)
  }
} 