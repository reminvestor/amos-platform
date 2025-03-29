import { Controller } from "@hotwired/stimulus"

// Manages contact selection in contact group form
export default class extends Controller {
  static targets = [ "checkbox" ]
  
  connect() {
    console.log("Contact selection controller connected")
  }
  
  toggleAll(event) {
    const isChecked = event.target.checked
    
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = isChecked
    })
  }
} 