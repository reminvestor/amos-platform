import { Controller } from "@hotwired/stimulus"

/**
 * Module Marketplace Controller
 * 
 * Handles browsing and installing module templates
 */
export default class extends Controller {
  static targets = ["search", "grid", "featured"]

  connect() {
    console.log("Module Marketplace controller connected")
  }

  search(event) {
    const query = event.target.value.toLowerCase()
    
    this.gridTarget.querySelectorAll('[data-category]').forEach(card => {
      const title = card.querySelector('.card-title')?.textContent?.toLowerCase() || ''
      const desc = card.querySelector('.card-text')?.textContent?.toLowerCase() || ''
      
      if (title.includes(query) || desc.includes(query) || query === '') {
        card.style.display = ''
      } else {
        card.style.display = 'none'
      }
    })
  }

  filterCategory(event) {
    const category = event.target.dataset.category
    
    // Update button states
    event.target.closest('.btn-group').querySelectorAll('.btn').forEach(btn => {
      btn.classList.remove('active')
    })
    event.target.classList.add('active')
    
    // Filter cards
    this.gridTarget.querySelectorAll('[data-category]').forEach(card => {
      if (category === 'all' || card.dataset.category === category) {
        card.style.display = ''
      } else {
        card.style.display = 'none'
      }
    })
  }

  async installTemplate(event) {
    const template = event.target.dataset.template
    if (!template) return
    
    const button = event.target
    const originalContent = button.innerHTML
    
    // Show loading state
    button.disabled = true
    button.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span> Installing...'
    
    try {
      // Call the install API
      const response = await fetch('/modules/install_template', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ template })
      })
      
      if (response.ok) {
        const data = await response.json()
        
        // Show success
        button.innerHTML = '<i data-lucide="check"></i> Installed!'
        button.classList.remove('btn-primary', 'btn-outline-primary')
        button.classList.add('btn-success')
        
        // Refresh lucide icons
        if (window.lucide) lucide.createIcons()
        
        // Show notification
        this.showNotification(`${data.module_name} installed successfully!`, 'success')
        
        // Optionally redirect to the new module
        if (data.redirect) {
          setTimeout(() => {
            if (window.scoutController) {
              window.scoutController.loadScoutCanvas(data.redirect)
            }
          }, 1500)
        }
      } else {
        const error = await response.json()
        button.innerHTML = originalContent
        button.disabled = false
        this.showNotification(error.message || 'Installation failed', 'error')
      }
    } catch (error) {
      console.error("Installation failed:", error)
      button.innerHTML = originalContent
      button.disabled = false
      this.showNotification('Installation failed. Please try again.', 'error')
    }
  }

  requestCustom() {
    console.log("📝 Requesting custom module...")
    // Send a message to Amos via the chat input
    const message = "I'd like to build a custom module. Can you help me design it?"
    this.sendMessageToAmos(message)
  }

  // Helper to send a message to Amos
  sendMessageToAmos(message) {
    const messageInput = document.getElementById('message-input')
    const messageForm = document.getElementById('message-form')
    
    if (messageInput && messageForm) {
      console.log("✅ Sending message to Amos:", message)
      messageInput.value = message
      messageInput.focus()
      
      // Submit the form
      messageForm.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
    } else {
      console.warn("Could not find message-input or message-form element")
      // Fallback: show the message in an alert
      alert("Please type this in the chat: " + message)
    }
  }

  showNotification(message, type = 'info') {
    // Create toast notification
    const toast = document.createElement('div')
    toast.className = `toast show position-fixed bottom-0 end-0 m-3`
    toast.setAttribute('role', 'alert')
    toast.innerHTML = `
      <div class="toast-header bg-${type === 'success' ? 'success' : type === 'error' ? 'danger' : 'info'} text-white">
        <strong class="me-auto">
          ${type === 'success' ? '✅' : type === 'error' ? '❌' : 'ℹ️'} 
          ${type === 'success' ? 'Success' : type === 'error' ? 'Error' : 'Info'}
        </strong>
        <button type="button" class="btn-close btn-close-white" data-bs-dismiss="toast"></button>
      </div>
      <div class="toast-body">
        ${message}
      </div>
    `
    
    document.body.appendChild(toast)
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      toast.remove()
    }, 5000)
  }
}

