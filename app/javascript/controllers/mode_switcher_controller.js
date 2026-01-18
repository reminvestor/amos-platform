import { Controller } from "@hotwired/stimulus"

// Mode Switcher Controller - dropdown for switching between Personal/Operations/Design modes
export default class extends Controller {
  static targets = ["dropdown"]
  static values = {
    current: String
  }

  connect() {
    console.log("🎛️ Mode Switcher connected, current:", this.currentValue)
    // Close dropdown when clicking outside
    this.boundCloseOnOutsideClick = this.closeOnOutsideClick.bind(this)
    document.addEventListener('click', this.boundCloseOnOutsideClick)
  }

  disconnect() {
    document.removeEventListener('click', this.boundCloseOnOutsideClick)
  }

  toggle(event) {
    event.stopPropagation()
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.toggle('open')
    }
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target) && this.hasDropdownTarget) {
      this.dropdownTarget.classList.remove('open')
    }
  }

  async switchMode(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const newSpace = event.currentTarget.dataset.space
    if (newSpace === this.currentValue) {
      this.dropdownTarget.classList.remove('open')
      return
    }

    console.log("🎛️ Switching to mode:", newSpace)

    try {
      const response = await fetch('/scout/switch_space', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ space: newSpace })
      })

      if (!response.ok) {
        throw new Error(`Failed to switch mode: ${response.statusText}`)
      }

      const data = await response.json()
      console.log("🎛️ Mode switched successfully:", data)

      // Show notification
      this.showNotification(`Switched to ${this.formatModeName(newSpace)}`)

      // Reload page to update the entire UI
      setTimeout(() => {
        window.location.reload()
      }, 300)

    } catch (error) {
      console.error("🎛️ Failed to switch mode:", error)
      this.showNotification("Failed to switch mode", "error")
    }
  }

  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.getAttribute('content') : ''
  }

  formatModeName(space) {
    const names = {
      personal: 'Personal Mode',
      operations: 'Operations Mode',
      design: 'Design Mode'
    }
    return names[space] || `${space.charAt(0).toUpperCase() + space.slice(1)} Mode`
  }

  showNotification(message, type = 'success') {
    // Use existing notification system if available
    if (typeof window.showNotification === 'function') {
      window.showNotification(message, type)
      return
    }

    // Simple fallback toast
    const toast = document.createElement('div')
    toast.className = `mode-switch-toast ${type}`
    toast.textContent = message
    toast.style.cssText = `
      position: fixed;
      top: 20px;
      right: 20px;
      padding: 12px 20px;
      background: ${type === 'error' ? '#ef4444' : '#10b981'};
      color: white;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 500;
      z-index: 10000;
      animation: slideIn 0.3s ease;
    `
    document.body.appendChild(toast)
    setTimeout(() => toast.remove(), 3000)
  }
}

