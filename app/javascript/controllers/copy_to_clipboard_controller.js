import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="copy-to-clipboard"
// Usage:
//   <div data-controller="copy-to-clipboard" data-copy-to-clipboard-text-value="Text to copy">
//     <button data-action="copy-to-clipboard#copy">Copy</button>
//   </div>
export default class extends Controller {
  static values = {
    text: String,
    successMessage: { type: String, default: "Copied!" },
    successDuration: { type: Number, default: 2000 }
  }

  static targets = ["source", "button"]

  connect() {
    // Controller connected
  }

  copy(event) {
    event.preventDefault()

    const textToCopy = this.hasTextValue ? this.textValue : this.getTextFromSource()

    if (!textToCopy) {
      console.error("No text to copy")
      return
    }

    navigator.clipboard.writeText(textToCopy).then(() => {
      this.showSuccess(event.currentTarget)
    }).catch(err => {
      console.error("Failed to copy text: ", err)
      this.showError(event.currentTarget)
    })
  }

  getTextFromSource() {
    if (!this.hasSourceTarget) {
      return null
    }

    // If source is an input/textarea, get its value
    if (this.sourceTarget.tagName === "INPUT" || this.sourceTarget.tagName === "TEXTAREA") {
      return this.sourceTarget.value
    }

    // Otherwise get text content
    return this.sourceTarget.textContent.trim()
  }

  showSuccess(button) {
    // Show toast notification
    this.showToast('Copied to clipboard!', 'success')

    if (!button) return

    const originalHTML = button.innerHTML
    const originalClasses = button.className

    // Update button to show success
    button.innerHTML = `<i class="bi bi-check-lg me-1"></i>${this.successMessageValue}`
    button.classList.remove('btn-primary', 'btn-outline-primary', 'btn-secondary', 'btn-outline-secondary')
    button.classList.add('btn-success')
    button.disabled = true

    // Restore original state after duration
    setTimeout(() => {
      if (button) {
        button.innerHTML = originalHTML
        button.className = originalClasses
        button.disabled = false
      }
    }, this.successDurationValue)
  }

  showToast(message, type = 'success') {
    const toast = document.createElement('div')

    toast.setAttribute('style', `
      position: fixed !important;
      top: 70px !important;
      left: 50% !important;
      transform: translateX(-50%) !important;
      z-index: 99999 !important;
      background-color: #d1e7dd !important;
      border: 2px solid #0f5132 !important;
      color: #0f5132 !important;
      padding: 16px 24px !important;
      border-radius: 8px !important;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3) !important;
      font-size: 16px !important;
      font-weight: 500 !important;
      display: flex !important;
      align-items: center !important;
      gap: 12px !important;
      min-width: 300px !important;
    `)

    toast.innerHTML = `
      <i class="fas fa-check-circle" style="font-size: 20px;"></i>
      <span>${message}</span>
      <button type="button"
              onclick="this.parentElement.remove()"
              style="margin-left: auto; background: none; border: none; font-size: 20px; cursor: pointer; color: #0f5132;">×</button>
    `

    document.body.appendChild(toast)

    // Auto-dismiss after 3 seconds
    setTimeout(() => {
      if (toast.parentElement) {
        toast.remove()
      }
    }, 3000)
  }

  showError(button) {
    if (!button) return

    const originalHTML = button.innerHTML
    const originalClasses = button.className

    button.innerHTML = '<i class="bi bi-x-lg me-1"></i>Error'
    button.classList.remove('btn-primary', 'btn-outline-primary', 'btn-secondary', 'btn-outline-secondary')
    button.classList.add('btn-danger')

    setTimeout(() => {
      if (button) {
        button.innerHTML = originalHTML
        button.className = originalClasses
      }
    }, 2000)
  }
}
