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
        
        // Check if we should start a design conversation (interactive mode)
        if (data.start_design_conversation) {
          // Start a design conversation with AMOS
          button.innerHTML = '<i data-lucide="message-circle"></i> Designing...'
          button.classList.remove('btn-primary', 'btn-outline-primary')
          button.classList.add('btn-info')
          button.disabled = true
          
          // Show notification
          this.showNotification(data.message || `Let's design your ${data.module_name}!`, 'info')
          
          // Send the design prompt to AMOS to start the conversation
          this.startDesignConversation(data.design_prompt, data.template_key, data.plan_id)
          
          // Refresh lucide icons
          if (window.lucide) lucide.createIcons()
          
          // After a delay, update button to show we're in design mode
          setTimeout(() => {
            button.innerHTML = '<i data-lucide="pencil-ruler"></i> In Design'
            button.classList.remove('btn-info')
            button.classList.add('btn-secondary')
            if (window.lucide) lucide.createIcons()
          }, 2000)
        } else if (data.show_design && data.template_key) {
          // Show design preview for user approval
          button.innerHTML = '<i data-lucide="eye"></i> Review Design'
          button.classList.remove('btn-primary', 'btn-outline-primary')
          button.classList.add('btn-success')
          button.disabled = false
          
          // Show notification about the design
          this.showNotification(data.message || `Review the design for ${data.module_name} before building.`, 'info')
          
          // Load the design preview canvas
          this.loadDesignPreview(data.template_key, data.plan_id)
          
          // Refresh lucide icons
          if (window.lucide) lucide.createIcons()
          
          // Update button to allow reopening the design
          button.onclick = () => this.loadDesignPreview(data.template_key, data.plan_id)
        } else if (data.show_plan && data.plan_id) {
          // Fallback: Show execution plan (for custom modules)
          button.innerHTML = '<i data-lucide="clipboard-list"></i> Review Plan'
          button.classList.remove('btn-primary', 'btn-outline-primary')
          button.classList.add('btn-success')
          button.disabled = false
          
          this.showNotification(data.message || `Plan created for ${data.module_name}.`, 'info')
          this.loadPlanCanvas(data.plan_id)
          
          if (window.lucide) lucide.createIcons()
          button.onclick = () => this.loadPlanCanvas(data.plan_id)
        } else {
          // Building started (autonomous mode)
          // Show building state (the module is being built in the background)
          button.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span> Building...'
          button.classList.remove('btn-primary', 'btn-outline-primary')
          button.classList.add('btn-info')
          
          // Refresh lucide icons
          if (window.lucide) lucide.createIcons()
          
          // Show notification that building has started
          this.showNotification(`Building ${data.module_name}... This may take a minute.`, 'info')
          
          // Update button after a delay to show it's complete (or user can check module manager)
          setTimeout(() => {
            button.innerHTML = '<i data-lucide="box"></i> In Progress'
            button.classList.remove('btn-info')
            button.classList.add('btn-secondary')
            button.disabled = true
            if (window.lucide) lucide.createIcons()
          }, 3000)
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
      window.showInfo("Please type this in the chat: " + message)
    }
  }

  // Start a design conversation with AMOS
  startDesignConversation(designPrompt, templateKey, planId) {
    console.log("💬 Starting design conversation for:", templateKey)
    
    // Find the message input and form
    const messageInput = document.getElementById('message-input')
    const messageForm = document.getElementById('message-form')
    
    if (messageInput && messageForm) {
      // Set the design prompt as AMOS's response context
      // We'll send a trigger message that AMOS will respond to with the design questions
      const triggerMessage = `I want to build a custom ${templateKey.replace(/_/g, ' ')} module. Help me design it.`
      
      messageInput.value = triggerMessage
      messageInput.focus()
      
      // Submit the form to start the conversation
      messageForm.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
      
      console.log("✅ Design conversation started")
    } else {
      console.warn("Could not find message input/form")
      // Fallback: show the design prompt in a notification
      this.showNotification("Check the chat to start designing your module!", 'info')
    }
  }

  // Load the design preview canvas
  async loadDesignPreview(templateKey, planId) {
    console.log("🎨 Loading design preview for template:", templateKey, "plan:", planId)
    
    try {
      const response = await fetch('/scout/load_canvas', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        },
        body: JSON.stringify({
          canvas_type: 'module_design_preview',
          canvas_data: { template_key: templateKey, plan_id: planId }
        })
      })
      
      if (response.ok) {
        const data = await response.json()
        if (data.success && data.canvas) {
          // Update the canvas area
          const canvasContent = document.querySelector('.canvas-content, #canvas-content, [data-canvas-content]')
          if (canvasContent) {
            canvasContent.innerHTML = data.canvas.content
            console.log("✅ Design preview loaded successfully")
            
            // Update canvas title if there's a header
            const canvasTitle = document.querySelector('.canvas-header-title, #canvas-title')
            if (canvasTitle && data.canvas.title) {
              canvasTitle.textContent = data.canvas.title
            }
            
            // Refresh icons
            if (window.lucide) lucide.createIcons()
          } else {
            console.warn("Could not find canvas content area, showing in modal")
            this.showPlanModal(data.canvas.content, data.canvas.title)
          }
        }
      } else {
        console.error("Failed to load design preview:", response.statusText)
        this.showNotification('Could not load design preview', 'error')
      }
    } catch (error) {
      console.error("Error loading design preview:", error)
      this.showNotification('Error loading design', 'error')
    }
  }

  // Load the plan details canvas
  async loadPlanCanvas(planId) {
    console.log("📋 Loading plan canvas for plan:", planId)
    
    try {
      const response = await fetch('/scout/load_canvas', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        },
        body: JSON.stringify({
          canvas_type: 'plan_details',
          canvas_data: { plan_id: planId }
        })
      })
      
      if (response.ok) {
        const data = await response.json()
        if (data.success && data.canvas) {
          // Update the canvas area
          const canvasContent = document.querySelector('.canvas-content, #canvas-content, [data-canvas-content]')
          if (canvasContent) {
            canvasContent.innerHTML = data.canvas.content
            console.log("✅ Plan canvas loaded successfully")
            
            // Update canvas title if there's a header
            const canvasTitle = document.querySelector('.canvas-header-title, #canvas-title')
            if (canvasTitle && data.canvas.title) {
              canvasTitle.textContent = data.canvas.title
            }
            
            // Refresh icons
            if (window.lucide) lucide.createIcons()
          } else {
            console.warn("Could not find canvas content area")
            // Fallback: show the plan in a modal
            this.showPlanModal(data.canvas.content, data.canvas.title)
          }
        }
      } else {
        console.error("Failed to load plan canvas:", response.statusText)
        this.showNotification('Could not load plan details', 'error')
      }
    } catch (error) {
      console.error("Error loading plan canvas:", error)
      this.showNotification('Error loading plan', 'error')
    }
  }
  
  // Show plan in a modal as fallback
  showPlanModal(content, title) {
    // Create modal element
    const modalId = 'planDetailsModal'
    let modal = document.getElementById(modalId)
    
    if (!modal) {
      modal = document.createElement('div')
      modal.id = modalId
      modal.className = 'modal fade'
      modal.tabIndex = -1
      modal.innerHTML = `
        <div class="modal-dialog modal-xl modal-dialog-scrollable">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">${title || 'Plan Details'}</h5>
              <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
              ${content}
            </div>
          </div>
        </div>
      `
      document.body.appendChild(modal)
    } else {
      modal.querySelector('.modal-title').textContent = title || 'Plan Details'
      modal.querySelector('.modal-body').innerHTML = content
    }
    
    // Show modal using Bootstrap
    const bsModal = new bootstrap.Modal(modal)
    bsModal.show()
    
    // Refresh icons
    if (window.lucide) lucide.createIcons()
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

