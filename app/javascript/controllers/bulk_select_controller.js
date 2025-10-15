import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="bulk-select"
// Usage:
//   <div data-controller="bulk-select">
//     <input type="checkbox" data-bulk-select-target="masterCheckbox" data-action="bulk-select#toggleAll">
//     <input type="checkbox" data-bulk-select-target="checkbox" data-action="bulk-select#updateCount">
//     <button data-bulk-select-target="actionButton">Bulk Action</button>
//     <span data-bulk-select-target="counter"></span>
//   </div>
export default class extends Controller {
  static targets = ["masterCheckbox", "checkbox", "actionButton", "counter"]

  connect() {
    this.updateUI()
  }

  toggleAll(event) {
    const checked = event.target.checked

    this.checkboxTargets.forEach(checkbox => {
      if (!checkbox.disabled) {
        checkbox.checked = checked
      }
    })

    this.updateUI()
  }

  updateCount() {
    this.updateUI()

    // Update master checkbox state
    if (this.hasMasterCheckboxTarget) {
      const allChecked = this.enabledCheckboxes.every(cb => cb.checked)
      const noneChecked = this.enabledCheckboxes.every(cb => !cb.checked)

      this.masterCheckboxTarget.checked = allChecked
      this.masterCheckboxTarget.indeterminate = !allChecked && !noneChecked
    }
  }

  selectAll(event) {
    event.preventDefault()

    this.checkboxTargets.forEach(checkbox => {
      if (!checkbox.disabled) {
        checkbox.checked = true
      }
    })

    if (this.hasMasterCheckboxTarget) {
      this.masterCheckboxTarget.checked = true
    }

    this.updateUI()
  }

  deselectAll(event) {
    event.preventDefault()

    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = false
    })

    if (this.hasMasterCheckboxTarget) {
      this.masterCheckboxTarget.checked = false
      this.masterCheckboxTarget.indeterminate = false
    }

    this.updateUI()
  }

  updateUI() {
    const selectedCount = this.selectedCheckboxes.length

    // Update action buttons
    this.actionButtonTargets.forEach(button => {
      button.disabled = selectedCount === 0

      // Update button text if it contains a count
      const countElement = button.querySelector('.count')
      if (countElement) {
        countElement.textContent = selectedCount
      }
    })

    // Update counter displays
    this.counterTargets.forEach(counter => {
      counter.textContent = selectedCount
    })
  }

  get selectedCheckboxes() {
    return this.checkboxTargets.filter(cb => cb.checked)
  }

  get enabledCheckboxes() {
    return this.checkboxTargets.filter(cb => !cb.disabled)
  }
}
