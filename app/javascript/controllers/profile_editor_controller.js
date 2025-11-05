import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewMode", "editMode", "editButton", "editButtonText", "form"]
  
  connect() {
    console.log('📝 Profile editor controller connected')
  }
  
  toggleEdit(event) {
    event.preventDefault()
    
    if (this.editModeTarget.classList.contains('d-none')) {
      // Switch to edit mode
      this.viewModeTarget.classList.add('d-none')
      this.editModeTarget.classList.remove('d-none')
      this.editButtonTextTarget.textContent = 'Cancel'
      this.editButtonTarget.classList.remove('btn-outline-primary')
      this.editButtonTarget.classList.add('btn-outline-secondary')
    } else {
      // Switch back to view mode
      this.cancelEdit()
    }
  }
  
  cancelEdit() {
    this.viewModeTarget.classList.remove('d-none')
    this.editModeTarget.classList.add('d-none')
    this.editButtonTextTarget.textContent = 'Edit'
    this.editButtonTarget.classList.remove('btn-outline-secondary')
    this.editButtonTarget.classList.add('btn-outline-primary')
    
    // Reset form to original values
    this.formTarget.reset()
  }
}


