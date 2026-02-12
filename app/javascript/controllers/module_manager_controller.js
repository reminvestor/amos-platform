import { Controller } from "@hotwired/stimulus"

/**
 * Module Manager Controller
 * 
 * Handles the module management canvas interactions including:
 * - Loading and displaying modules
 * - Filtering modules by status
 * - Module activation/deactivation
 * - Opening module canvases
 */
export default class extends Controller {
  static targets = ["moduleList", "totalCount", "activeCount", "draftCount", "aiCount"]

  connect() {
    console.log("Module Manager controller connected")
    this.loadModules()
  }

  async loadModules() {
    try {
      const response = await fetch('/modules.json', {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        this.modules = data.modules
        this.updateCounts()
      }
    } catch (error) {
      console.error("Failed to load modules:", error)
    }
  }

  updateCounts() {
    if (!this.modules) return
    
    if (this.hasTotalCountTarget) {
      this.totalCountTarget.textContent = this.modules.length
    }
    if (this.hasActiveCountTarget) {
      this.activeCountTarget.textContent = this.modules.filter(m => m.status === 'active').length
    }
    if (this.hasDraftCountTarget) {
      this.draftCountTarget.textContent = this.modules.filter(m => m.status === 'draft').length
    }
    if (this.hasAiCountTarget) {
      this.aiCountTarget.textContent = this.modules.filter(m => m.author_type === 'amos').length
    }
  }

  filter(event) {
    const filter = event.target.dataset.filter
    
    // Update active button
    event.target.closest('.btn-group').querySelectorAll('.btn').forEach(btn => {
      btn.classList.remove('active')
    })
    event.target.classList.add('active')
    
    // Filter table rows
    if (this.hasModuleListTarget) {
      const rows = this.moduleListTarget.querySelectorAll('tr[data-module-slug]')
      rows.forEach(row => {
        const slug = row.dataset.moduleSlug
        const module = this.modules?.find(m => m.slug === slug)
        
        if (!module) {
          row.style.display = ''
          return
        }
        
        if (filter === 'all') {
          row.style.display = ''
        } else if (filter === 'active' && module.status === 'active') {
          row.style.display = ''
        } else if (filter === 'draft' && module.status === 'draft') {
          row.style.display = ''
        } else {
          row.style.display = 'none'
        }
      })
    }
  }

  refresh() {
    console.log("🔄 Refreshing module manager...")
    this.loadModules()
    // Force canvas reload if Scout controller is available
    if (window.scoutController && typeof window.scoutController.loadScoutCanvas === 'function') {
      window.scoutController.loadScoutCanvas('module_manager', {}, true)
    } else {
      // Fallback: reload via fetch
      location.reload()
    }
  }

  requestNewModule() {
    console.log("📝 Requesting new module...")
    // Send a message to Amos via the chat input
    const message = "I'd like to create a new custom app. Can you help me design it?"
    this.sendMessageToAmos(message)
  }

  browseApps() {
    console.log("📱 Opening apps marketplace...")
    // Load the apps/marketplace canvas
    if (window.scoutController) {
      window.scoutController.loadScoutCanvas("module_marketplace", {})
    }
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

  async openModule(event) {
    const slug = event.target.closest('[data-slug]')?.dataset.slug
    if (!slug) return
    
    try {
      // Get the module's default canvas
      const response = await fetch(`/modules/${slug}/canvases.json`)
      if (response.ok) {
        const data = await response.json()
        const defaultCanvas = data.canvases.find(c => c.is_default) || data.canvases[0]
        
        if (defaultCanvas && window.scoutController) {
          window.scoutController.loadScoutCanvas(defaultCanvas.full_type)
        }
      }
    } catch (error) {
      console.error("Failed to open module:", error)
    }
  }

  async viewDetails(event) {
    event.preventDefault()
    const slug = event.target.closest('[data-slug]')?.dataset.slug
    if (!slug) return
    
    try {
      const response = await fetch(`/modules/${slug}.json`)
      if (response.ok) {
        const module = await response.json()
        this.showModuleDetails(module)
      }
    } catch (error) {
      console.error("Failed to load module details:", error)
    }
  }

  showModuleDetails(module) {
    // Create a modal to show module details
    const modal = document.createElement('div')
    modal.className = 'modal fade'
    modal.innerHTML = `
      <div class="modal-dialog modal-lg">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title">${module.name}</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body">
            <p>${module.description || 'No description'}</p>
            <hr>
            <div class="row">
              <div class="col-md-6">
                <h6>Status</h6>
                <p><span class="badge bg-${this.statusColor(module.status)}">${module.status}</span></p>
              </div>
              <div class="col-md-6">
                <h6>Version</h6>
                <p>${module.version}</p>
              </div>
            </div>
            <h6>Components</h6>
            <ul class="list-unstyled">
              <li>📊 Canvases: ${module.components_summary.canvases}</li>
              <li>🗃️ Models: ${module.components_summary.models}</li>
              <li>🔧 Tools: ${module.components_summary.tools}</li>
              <li>🔗 Webhooks: ${module.components_summary.webhooks}</li>
            </ul>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
          </div>
        </div>
      </div>
    `
    
    document.body.appendChild(modal)
    const bsModal = new bootstrap.Modal(modal)
    bsModal.show()
    
    modal.addEventListener('hidden.bs.modal', () => {
      modal.remove()
    })
  }

  statusColor(status) {
    const colors = {
      active: 'success',
      deployed: 'primary',
      testing: 'info',
      draft: 'secondary',
      disabled: 'warning',
      failed: 'danger'
    }
    return colors[status] || 'secondary'
  }

  async viewCanvases(event) {
    event.preventDefault()
    const slug = event.target.closest('[data-slug]')?.dataset.slug
    if (!slug) return
    
    try {
      const response = await fetch(`/modules/${slug}/canvases.json`)
      if (response.ok) {
        const data = await response.json()
        this.showCanvasesModal(slug, data.canvases)
      }
    } catch (error) {
      console.error("Failed to load canvases:", error)
    }
  }

  showCanvasesModal(moduleSlug, canvases) {
    const canvasList = canvases.map(c => `
      <li class="list-group-item d-flex justify-content-between align-items-center">
        <div>
          <strong>${c.name}</strong>
          <span class="badge bg-secondary ms-2">${c.canvas_type}</span>
          ${c.is_default ? '<span class="badge bg-primary ms-1">Default</span>' : ''}
        </div>
        <button class="btn btn-sm btn-outline-primary" onclick="window.scoutController?.loadScoutCanvas('${c.full_type}')">
          Open
        </button>
      </li>
    `).join('')
    
    const modal = document.createElement('div')
    modal.className = 'modal fade'
    modal.innerHTML = `
      <div class="modal-dialog">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title">Module Canvases</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body">
            ${canvases.length ? `<ul class="list-group">${canvasList}</ul>` : '<p class="text-muted">No canvases available</p>'}
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
          </div>
        </div>
      </div>
    `
    
    document.body.appendChild(modal)
    const bsModal = new bootstrap.Modal(modal)
    bsModal.show()
    
    modal.addEventListener('hidden.bs.modal', () => {
      modal.remove()
    })
  }

  async activate(event) {
    event.preventDefault()
    const slug = event.target.closest('[data-slug]')?.dataset.slug
    if (!slug) return
    
    if (!await showConfirm('Activate this module?', { title: 'Activate Module' })) return
    
    try {
      const response = await fetch(`/modules/${slug}/activate`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        }
      })
      
      if (response.ok) {
        this.refresh()
      }
    } catch (error) {
      console.error("Failed to activate module:", error)
    }
  }

  async deactivate(event) {
    event.preventDefault()
    const slug = event.target.closest('[data-slug]')?.dataset.slug
    if (!slug) return
    
    if (!await showConfirm('Deactivate this module? Users will no longer be able to access it.', { title: 'Deactivate Module', dangerous: true })) return
    
    try {
      const response = await fetch(`/modules/${slug}/deactivate`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        }
      })
      
      if (response.ok) {
        this.refresh()
      }
    } catch (error) {
      console.error("Failed to deactivate module:", error)
    }
  }

  async delete(event) {
    event.preventDefault()
    const slug = event.target.closest('[data-slug]')?.dataset.slug
    if (!slug) return
    
    if (!await showConfirm('Are you sure you want to delete this module? This action cannot be undone.', { title: 'Delete Module', dangerous: true })) return
    
    try {
      const response = await fetch(`/modules/${slug}`, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        }
      })
      
      if (response.ok) {
        this.refresh()
      }
    } catch (error) {
      console.error("Failed to delete module:", error)
    }
  }

  // Share module with team (change from user_private to entity_shared)
  async shareWithTeam(event) {
    event.preventDefault()
    const slug = event.target.closest('[data-slug]')?.dataset.slug
    if (!slug) return
    
    if (!await showConfirm('Share this app with your team? All team members will be able to see and use it.', { title: 'Share App' })) return
    
    try {
      const response = await fetch(`/modules/${slug}/share`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        this.showToast(data.message || 'App shared with team!', 'success')
        this.refresh()
      } else {
        const error = await response.json()
        this.showToast(error.error || 'Failed to share app', 'danger')
      }
    } catch (error) {
      console.error("Failed to share module:", error)
      this.showToast('Failed to share app', 'danger')
    }
  }

  // Make module private again (change from entity_shared to user_private)
  async makePrivate(event) {
    event.preventDefault()
    const slug = event.target.closest('[data-slug]')?.dataset.slug
    if (!slug) return
    
    if (!await showConfirm('Make this app private? Only you will be able to see it.', { title: 'Make Private' })) return
    
    try {
      const response = await fetch(`/modules/${slug}/unshare`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        this.showToast(data.message || 'App is now private!', 'success')
        this.refresh()
      } else {
        const error = await response.json()
        this.showToast(error.error || 'Failed to make app private', 'danger')
      }
    } catch (error) {
      console.error("Failed to make module private:", error)
      this.showToast('Failed to make app private', 'danger')
    }
  }

  // Simple toast notification
  showToast(message, type = 'info') {
    // Try to use existing toast system if available
    if (window.showToast) {
      window.showToast(message, type)
      return
    }

    // Fallback: Create a simple toast
    const toast = document.createElement('div')
    toast.className = `alert alert-${type} position-fixed`
    toast.style.cssText = 'top: 20px; right: 20px; z-index: 9999; max-width: 300px;'
    toast.innerHTML = `
      <div class="d-flex align-items-center">
        <span>${message}</span>
        <button type="button" class="btn-close ms-2" onclick="this.parentElement.parentElement.remove()"></button>
      </div>
    `
    document.body.appendChild(toast)
    
    // Auto-remove after 3 seconds
    setTimeout(() => toast.remove(), 3000)
  }
}

