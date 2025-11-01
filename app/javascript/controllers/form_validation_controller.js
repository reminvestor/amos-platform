import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="form-validation"
// Usage:
//   <form data-controller="form-validation" class="needs-validation" novalidate>
//     <input type="email" required>
//     <div class="invalid-feedback">Please enter a valid email</div>
//     <button type="submit">Submit</button>
//   </form>
//
// To reset validation state:
//   <button data-action="form-validation#reset">Reset</button>
export default class extends Controller {
  static values = {
    submitOnValid: { type: Boolean, default: true },
    showToast: { type: Boolean, default: false }
  }

  connect() {
    // Ensure the form has the novalidate attribute to use custom validation
    this.element.setAttribute('novalidate', '')

    // Add needs-validation class if not present
    if (!this.element.classList.contains('needs-validation')) {
      this.element.classList.add('needs-validation')
    }
  }

  // Main validation handler triggered on form submit
  submit(event) {
    // Check if form is valid using HTML5 validation API
    if (!this.element.checkValidity()) {
      event.preventDefault()
      event.stopPropagation()

      // Show validation feedback
      this.element.classList.add('was-validated')

      // Focus on first invalid field
      this.focusFirstInvalidField()

      // Show toast notification if enabled
      if (this.showToastValue) {
        this.showErrorToast()
      }

      return false
    }

    // Form is valid - add validation class for visual feedback
    this.element.classList.add('was-validated')

    // If submitOnValid is false, prevent submission and let caller handle it
    if (!this.submitOnValidValue) {
      event.preventDefault()
    }

    return true
  }

  // Reset validation state
  reset() {
    this.element.classList.remove('was-validated')
    this.element.reset()

    // Clear any custom error messages
    this.clearCustomErrors()
  }

  // Clear validation state without resetting form data
  clearValidation() {
    this.element.classList.remove('was-validated')
    this.clearCustomErrors()
  }

  // Focus on the first invalid field for better UX
  focusFirstInvalidField() {
    const firstInvalid = this.element.querySelector(':invalid')
    if (firstInvalid) {
      firstInvalid.focus()

      // Scroll into view if needed
      firstInvalid.scrollIntoView({
        behavior: 'smooth',
        block: 'center'
      })
    }
  }

  // Clear custom error messages
  clearCustomErrors() {
    const inputs = this.element.querySelectorAll('input, select, textarea')
    inputs.forEach(input => {
      input.setCustomValidity('')
    })
  }

  // Show error toast notification
  showErrorToast() {
    const toast = document.createElement('div')

    toast.setAttribute('class', 'alert alert-danger alert-dismissible fade show')
    toast.setAttribute('role', 'alert')
    toast.setAttribute('style', `
      position: fixed;
      top: 80px;
      right: 20px;
      z-index: 9999;
      min-width: 300px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    `)

    toast.innerHTML = `
      <strong>Validation Error</strong>
      <p class="mb-0 mt-1">Please check the form and fix any errors.</p>
      <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
    `

    document.body.appendChild(toast)

    // Auto-dismiss after 5 seconds
    setTimeout(() => {
      if (toast.parentElement) {
        // Use Bootstrap's alert dismiss
        const bsAlert = bootstrap.Alert.getOrCreateInstance(toast)
        bsAlert.close()
      }
    }, 5000)
  }

  // Set custom validation message for a specific field
  // Can be called from other controllers or inline handlers
  setFieldError(fieldName, message) {
    const field = this.element.querySelector(`[name="${fieldName}"]`)
    if (field) {
      field.setCustomValidity(message)
      field.classList.add('is-invalid')

      // Show validation feedback
      this.element.classList.add('was-validated')
    }
  }

  // Clear error for a specific field
  clearFieldError(fieldName) {
    const field = this.element.querySelector(`[name="${fieldName}"]`)
    if (field) {
      field.setCustomValidity('')
      field.classList.remove('is-invalid')
    }
  }

  // Validate a single field without submitting
  validateField(event) {
    const field = event.target

    if (!field.checkValidity()) {
      field.classList.add('is-invalid')
      field.classList.remove('is-valid')
    } else {
      field.classList.remove('is-invalid')
      field.classList.add('is-valid')
    }
  }
}
