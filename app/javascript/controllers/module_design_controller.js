import { Controller } from "@hotwired/stimulus"

/**
 * Module Design Controller
 * 
 * Handles approval and modification of module designs
 * Supports both:
 * - Plan-based approval (planId)
 * - Session-based approval (sessionId) from conversational design
 */
export default class extends Controller {
  static values = {
    template: String,
    planId: Number,
    sessionId: Number
  }

  connect() {
    console.log("Module Design controller connected", {
      template: this.templateValue,
      planId: this.planIdValue,
      sessionId: this.sessionIdValue
    })
  }

  async approve() {
    console.log("✅ Approving design and starting build...")
    
    const approveBtn = this.element.querySelector('[data-action="click->module-design#approve"]')
    if (approveBtn) {
      approveBtn.disabled = true
      approveBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span> Building...'
    }

    try {
      let response
      
      if (this.sessionIdValue) {
        // Session-based approval (from conversational design)
        response = await fetch('/scout/approve_module_design', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
          },
          body: JSON.stringify({
            session_id: this.sessionIdValue,
            user_confirmation: 'User clicked Approve & Build button'
          })
        })
      } else if (this.planIdValue) {
        // Plan-based approval
        response = await fetch('/scout/approve_plan', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
          },
          body: JSON.stringify({
            plan_id: this.planIdValue,
            auto_execute: true
          })
        })
      } else {
        throw new Error('No session_id or plan_id available for approval')
      }

      if (response.ok) {
        const data = await response.json()
        const moduleName = data.module_name || this.templateValue?.replace(/_/g, ' ') || 'your module'
        this.showNotification(`🚀 Building ${moduleName}... This may take a minute.`, 'success')
        
        // Update the canvas to show building status
        this.showBuildingStatus(moduleName)
        
        // If module was created, we can optionally load it
        if (data.module_slug) {
          setTimeout(() => {
            this.loadModuleCanvas(data.module_slug)
          }, 2000)
        }
      } else {
        const error = await response.json()
        this.showNotification(error.message || error.error || 'Failed to start build', 'error')
        if (approveBtn) {
          approveBtn.disabled = false
          approveBtn.innerHTML = '<i class="bi bi-check-circle me-1"></i>Approve & Build'
        }
      }
    } catch (error) {
      console.error("Approval failed:", error)
      this.showNotification('Failed to start build. Please try again.', 'error')
      if (approveBtn) {
        approveBtn.disabled = false
        approveBtn.innerHTML = '<i class="bi bi-check-circle me-1"></i>Approve & Build'
      }
    }
  }

  requestChanges() {
    console.log("📝 Requesting changes to design...")
    
    // Prompt user for what they want to change
    const feedback = prompt("What changes would you like to make to this design?")
    if (feedback) {
      const context = this.sessionIdValue 
        ? `(design session ${this.sessionIdValue})` 
        : `(${this.templateValue?.replace(/_/g, ' ')})`
      const message = `I'd like to make some changes to the module design ${context}: ${feedback}`
      this.sendMessageToAmos(message)
    }
  }
  
  loadModuleCanvas(moduleSlug) {
    // Load the new module's overview canvas
    document.dispatchEvent(new CustomEvent('canvas:load', {
      detail: {
        canvas_type: `module_${moduleSlug}_list`,
        canvas_title: moduleSlug.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
      }
    }))
  }

  showBuildingStatus(moduleName = 'Your Module') {
    // Replace the actions section with a building status
    const actionsSection = this.element.querySelector('.bg-light.rounded')
    if (actionsSection) {
      actionsSection.innerHTML = `
        <div class="text-center py-4">
          <div class="spinner-border text-primary mb-3" role="status">
            <span class="visually-hidden">Building...</span>
          </div>
          <h5 class="mb-2">🏗️ Building ${moduleName}</h5>
          <p class="text-muted mb-0">
            Creating database tables, generating views, and registering AI tools...
            <br>This typically takes about a minute.
          </p>
          <div class="progress mt-3" style="height: 4px;">
            <div class="progress-bar progress-bar-striped progress-bar-animated" style="width: 100%"></div>
          </div>
        </div>
      `
    }
  }

  sendMessageToAmos(message) {
    const messageInput = document.getElementById('message-input')
    const messageForm = document.getElementById('message-form')
    
    if (messageInput && messageForm) {
      messageInput.value = message
      messageInput.focus()
      messageForm.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
    } else {
      // Fallback: show the message for the user to type
      showInfo("Please tell AMOS: " + message)
    }
  }

  showNotification(message, type = 'info') {
    const toast = document.createElement('div')
    toast.className = 'toast show position-fixed bottom-0 end-0 m-3'
    toast.style.zIndex = '9999'
    toast.setAttribute('role', 'alert')
    
    const bgClass = type === 'success' ? 'success' : type === 'error' ? 'danger' : 'info'
    const icon = type === 'success' ? '✅' : type === 'error' ? '❌' : 'ℹ️'
    
    toast.innerHTML = `
      <div class="toast-header bg-${bgClass} text-white">
        <strong class="me-auto">${icon} ${type === 'success' ? 'Success' : type === 'error' ? 'Error' : 'Info'}</strong>
        <button type="button" class="btn-close btn-close-white" onclick="this.closest('.toast').remove()"></button>
      </div>
      <div class="toast-body">${message}</div>
    `
    
    document.body.appendChild(toast)
    setTimeout(() => toast.remove(), 5000)
  }
}

