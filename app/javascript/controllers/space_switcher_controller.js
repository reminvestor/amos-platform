import { Controller } from "@hotwired/stimulus"

// SpaceSwitcherController
// Handles switching between Amos spaces (Personal, Operations, Design)
// THREE MODE ARCHITECTURE:
// - Personal: No sidebar, just chat + canvas
// - Operations: Collaboration sidebar (agents, team, channels)
// - Design: Collaboration sidebar (design agents, current projects)
export default class extends Controller {
  static values = {
    current: { type: String, default: "operations" }
  }

  connect() {
    console.log("🌌 SpaceSwitcher connected, current space:", this.currentValue)
    
    // Listen for Amos-initiated space switches
    window.addEventListener('amos:switch-space', this.handleAmosSwitchSpace.bind(this))
  }

  disconnect() {
    window.removeEventListener('amos:switch-space', this.handleAmosSwitchSpace.bind(this))
  }

  switchSpace(event) {
    const newSpace = event.currentTarget.dataset.space
    
    if (newSpace === this.currentValue) {
      console.log("🌌 Already in space:", newSpace)
      return
    }

    console.log("🌌 Switching to space:", newSpace)

    // Update UI immediately for responsiveness
    this.updateActiveTab(newSpace)

    // Send request to server to switch space
    this.persistSpaceChange(newSpace)
  }

  // Handle space switch triggered by Amos (e.g., "switch to Design mode")
  handleAmosSwitchSpace(event) {
    const { newSpace, message } = event.detail
    console.log(`🌌 Amos requested space switch to ${newSpace}: ${message}`)
    
    if (newSpace === this.currentValue) {
      return
    }

    this.updateActiveTab(newSpace)
    this.persistSpaceChange(newSpace)
  }

  updateActiveTab(newSpace) {
    // Handle all button variants: .space-tab, .space-btn-adaptive, .space-btn-compact
    const allButtons = this.element.querySelectorAll('.space-tab, .space-btn-adaptive, .space-btn-compact')
    allButtons.forEach(btn => {
      btn.classList.remove('active')
    })

    // Add active class to new tab
    const newTab = this.element.querySelector(`[data-space="${newSpace}"]`)
    if (newTab) {
      newTab.classList.add('active')
    }

    this.currentValue = newSpace
  }

  async persistSpaceChange(newSpace) {
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
        throw new Error(`Failed to switch space: ${response.statusText}`)
      }

      const data = await response.json()
      console.log("🌌 Space switched successfully:", data)

      // Dispatch event for other controllers to react
      this.dispatch("switched", { detail: { space: newSpace, data } })

      // Notify the user
      this.showNotification(`Switched to ${this.formatSpaceName(newSpace)} Space`)

      // Optionally reload tool loadout
      if (window.scoutController) {
        // Let scout controller know about the space change
        window.dispatchEvent(new CustomEvent('spaceChanged', { 
          detail: { space: newSpace } 
        }))
      }

      // Reload page after a short delay so sidebar updates
      // The notification will show briefly before reload
      setTimeout(() => {
        window.location.reload()
      }, 500)

    } catch (error) {
      console.error("🌌 Failed to switch space:", error)
      // Revert UI on error
      this.updateActiveTab(this.currentValue)
      this.showNotification("Failed to switch space", "error")
    }
  }

  formatSpaceName(space) {
    return space.charAt(0).toUpperCase() + space.slice(1)
  }

  showNotification(message, type = "success") {
    // Use existing notification system if available
    if (window.showNotification) {
      window.showNotification(message, type)
      return
    }

    // Simple fallback notification
    const notification = document.createElement('div')
    notification.className = `space-notification space-notification-${type}`
    notification.textContent = message
    notification.style.cssText = `
      position: fixed;
      bottom: 20px;
      left: 50%;
      transform: translateX(-50%);
      padding: 12px 24px;
      background: ${type === 'success' ? '#10b981' : '#ef4444'};
      color: white;
      border-radius: 8px;
      font-size: 14px;
      z-index: 9999;
      animation: slideUp 0.3s ease;
    `
    document.body.appendChild(notification)

    setTimeout(() => {
      notification.remove()
    }, 3000)
  }

  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }
}
