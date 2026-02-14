import { Controller } from "@hotwired/stimulus"

/**
 * Module Canvas Controller
 * 
 * Handles interactions for dynamically generated module canvases.
 * Buttons trigger DIRECT UI actions (modals, forms, API calls) - NOT AMOS.
 * AMOS is reserved for complex natural language tasks.
 */
export default class extends Controller {
  static values = {
    module: String,
    model: String
  }

  connect() {
    // Support legacy data-module attribute
    if (!this.hasModuleValue && this.element.dataset.module) {
      this.moduleValue = this.element.dataset.module
    }
    
    console.log(`📦 Module Canvas connected: ${this.moduleValue}`)
    this.initializeLucideIcons()
    this.bindButtonActions()
    this.loadInitialData()
  }

  disconnect() {
    console.log(`📦 Module Canvas disconnected: ${this.moduleValue}`)
  }

  // Initialize Lucide icons within the canvas
  initializeLucideIcons() {
    if (window.lucide) {
      window.lucide.createIcons()
    }
  }

  // Bind click handlers to all buttons with data-action
  bindButtonActions() {
    // Find all elements with data-action (but not Stimulus format)
    const actionElements = this.element.querySelectorAll('[data-action]')
    
    actionElements.forEach(el => {
      const action = el.dataset.action
      // Skip if it's already a Stimulus action format (contains ->)
      if (action && !action.includes('->')) {
        el.addEventListener('click', (e) => this.handleAction(e, action, el))
      }
    })

    // Also bind data-filter elements
    const filterElements = this.element.querySelectorAll('[data-filter]')
    filterElements.forEach(el => {
      el.addEventListener('click', (e) => this.handleFilter(e, el.dataset.filter))
    })

    // Bind row action buttons
    this.element.querySelectorAll('[data-row-action]').forEach(el => {
      el.addEventListener('click', (e) => this.handleRowAction(e))
    })
  }

  // Stimulus action handler - called via data-action="click->module-canvas#performAction"
  // Reads action name from data-action-name attribute
  performAction(event) {
    event.preventDefault()
    const element = event.currentTarget
    const action = element.dataset.actionName || element.dataset.action
    console.log(`📦 performAction called: ${action}`)
    this.handleAction(event, action, element)
  }

  // Handle button action clicks - DIRECT UI ACTIONS, not AMOS
  handleAction(event, action, element) {
    event.preventDefault()
    const model = element?.dataset.model || this.modelValue || this.inferModelFromContext()
    console.log(`📦 Canvas action: ${action} for ${model} in ${this.moduleValue}`)

    switch(action) {
      case 'add':
      case 'quick-add':
        this.openAddModal(model)
        break
      case 'refresh':
        this.refreshData()
        break
      case 'export':
        this.exportData(model)
        break
      case 'search':
      case 'quick-search':
        this.focusSearch()
        break
      case 'print':
        window.print()
        break
      case 'export-pdf':
        this.exportPdf()
        break
      case 'cancel':
        this.closeModal()
        break
      case 'select-all':
        this.toggleSelectAll(event.target)
        break
      case 'quick-report':
        this.openReportModal(model)
        break
      default:
        // For unknown actions, try to navigate to a canvas
        this.navigateToCanvas(action, model)
    }
  }

  // Infer model name from canvas context
  inferModelFromContext() {
    // First check heading
    const heading = this.element.querySelector('h2, h3')
    if (heading) {
      const text = heading.textContent.toLowerCase()
      if (text.includes('category')) return 'Category'
      if (text.includes('supplier')) return 'Supplier'
      if (text.includes('product')) return 'Product'
      if (text.includes('stock movement')) return 'StockMovement'
      if (text.includes('stock alert')) return 'StockAlert'
      if (text.includes('inventory')) return 'Product' // Default for inventory overview
    }
    return 'Record'
  }

  // ========================================
  // DIRECT UI ACTIONS
  // ========================================

  // Open Add modal with form
  openAddModal(model) {
    console.log(`📦 Opening add modal for ${model}`)
    this.openFormModal('add', model, null)
  }

  // Open Edit modal with form
  openEditModal(model, id, data = {}) {
    console.log(`📦 Opening edit modal for ${model} id ${id}`)
    this.openFormModal('edit', model, id, data)
  }

  // Generic form modal opener
  async openFormModal(mode, model, id, existingData = {}) {
    const modalId = 'moduleFormModal'
    let modal = document.getElementById(modalId)
    
    // Create modal if it doesn't exist
    if (!modal) {
      modal = this.createFormModal(modalId)
      document.body.appendChild(modal)
    }

    const title = mode === 'add' ? `Add New ${this.humanize(model)}` : `Edit ${this.humanize(model)}`
    modal.querySelector('.modal-title').textContent = title

    // Load form fields based on model schema
    const formBody = modal.querySelector('.modal-body')
    formBody.innerHTML = '<div class="text-center py-4"><div class="spinner-border text-primary"></div><p class="mt-2">Loading form...</p></div>'

    // Show modal
    const bsModal = new bootstrap.Modal(modal)
    bsModal.show()

    // Fetch schema and build form
    try {
      const schema = await this.fetchModelSchema(model)
      const formHtml = this.buildFormFromSchema(schema, mode, existingData)
      formBody.innerHTML = formHtml
      
      // Store context for form submission
      modal.dataset.mode = mode
      modal.dataset.model = model
      modal.dataset.recordId = id || ''
      modal.dataset.moduleSlug = this.moduleValue
      
      // Initialize any form components
      this.initializeLucideIcons()
    } catch (error) {
      console.error('Failed to load form schema:', error)
      formBody.innerHTML = `
        <div class="alert alert-danger">
          <i data-lucide="alert-circle"></i>
          Failed to load form. Please try again.
        </div>
      `
      this.initializeLucideIcons()
    }
  }

  // Create the form modal HTML
  createFormModal(modalId) {
    const modal = document.createElement('div')
    modal.id = modalId
    modal.className = 'modal fade'
    modal.tabIndex = -1
    modal.innerHTML = `
      <div class="modal-dialog modal-lg">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title">Form</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body">
            <!-- Form will be loaded here -->
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
            <button type="button" class="btn btn-primary" onclick="window.moduleCanvasController?.submitForm()">
              <i data-lucide="save"></i> Save
            </button>
          </div>
        </div>
      </div>
    `
    
    // Store reference for form submission
    window.moduleCanvasController = this
    
    return modal
  }

  // Fetch model schema from API
  async fetchModelSchema(model) {
    try {
      const response = await fetch(`/api/modules/${this.moduleValue}/models/${model}/schema`)
      if (response.ok) {
        return await response.json()
      }
    } catch (e) {
      console.log('Schema API not available, using fallback')
    }
    
    // Fallback: return basic schema based on model name
    return this.getFallbackSchema(model)
  }

  // Fallback schema when API isn't available
  getFallbackSchema(model) {
    const schemas = {
      'Category': {
        fields: [
          { name: 'name', type: 'string', required: true, label: 'Name' },
          { name: 'description', type: 'text', required: false, label: 'Description' }
        ]
      },
      'Supplier': {
        fields: [
          { name: 'name', type: 'string', required: true, label: 'Name' },
          { name: 'contact_name', type: 'string', required: false, label: 'Contact Name' },
          { name: 'email', type: 'email', required: false, label: 'Email' },
          { name: 'phone', type: 'string', required: false, label: 'Phone' },
          { name: 'address', type: 'text', required: false, label: 'Address' }
        ]
      },
      'Product': {
        fields: [
          { name: 'name', type: 'string', required: true, label: 'Name' },
          { name: 'sku', type: 'string', required: true, label: 'SKU' },
          { name: 'description', type: 'text', required: false, label: 'Description' },
          { name: 'price', type: 'number', required: true, label: 'Price' },
          { name: 'quantity', type: 'integer', required: true, label: 'Quantity' },
          { name: 'category_id', type: 'select', required: false, label: 'Category', model: 'Category' },
          { name: 'supplier_id', type: 'select', required: false, label: 'Supplier', model: 'Supplier' }
        ]
      },
      'StockMovement': {
        fields: [
          { name: 'product_id', type: 'select', required: true, label: 'Product', model: 'Product' },
          { name: 'movement_type', type: 'select', required: true, label: 'Type', options: ['in', 'out', 'adjustment'] },
          { name: 'quantity', type: 'integer', required: true, label: 'Quantity' },
          { name: 'notes', type: 'text', required: false, label: 'Notes' }
        ]
      },
      'StockAlert': {
        fields: [
          { name: 'product_id', type: 'select', required: true, label: 'Product', model: 'Product' },
          { name: 'alert_type', type: 'select', required: true, label: 'Alert Type', options: ['low_stock', 'out_of_stock', 'overstock'] },
          { name: 'threshold', type: 'integer', required: true, label: 'Threshold' }
        ]
      }
    }
    
    return schemas[model] || { fields: [{ name: 'name', type: 'string', required: true, label: 'Name' }] }
  }

  // Build form HTML from schema
  buildFormFromSchema(schema, mode, existingData = {}) {
    const fields = schema.fields || []
    
    let html = '<form id="moduleRecordForm" class="needs-validation" novalidate>'
    
    fields.forEach(field => {
      const value = existingData[field.name] || ''
      const required = field.required ? 'required' : ''
      const requiredStar = field.required ? '<span class="text-danger">*</span>' : ''
      
      html += `<div class="mb-3">`
      html += `<label class="form-label">${field.label || this.humanize(field.name)} ${requiredStar}</label>`
      
      switch(field.type) {
        case 'text':
          html += `<textarea class="form-control" name="${field.name}" rows="3" ${required}>${value}</textarea>`
          break
        case 'select':
          html += `<select class="form-select" name="${field.name}" ${required} data-model="${field.model || ''}">`
          html += `<option value="">Select...</option>`
          if (field.options) {
            field.options.forEach(opt => {
              const selected = value === opt ? 'selected' : ''
              html += `<option value="${opt}" ${selected}>${this.humanize(opt)}</option>`
            })
          }
          html += `</select>`
          // If it's a relationship, we'll load options async
          if (field.model) {
            this.loadSelectOptions(field.name, field.model)
          }
          break
        case 'number':
        case 'integer':
          const step = field.type === 'integer' ? '1' : 'any'
          html += `<input type="number" class="form-control" name="${field.name}" value="${value}" step="${step}" ${required}>`
          break
        case 'email':
          html += `<input type="email" class="form-control" name="${field.name}" value="${value}" ${required}>`
          break
        case 'boolean':
          const checked = value ? 'checked' : ''
          html += `<div class="form-check"><input type="checkbox" class="form-check-input" name="${field.name}" ${checked}></div>`
          break
        default:
          html += `<input type="text" class="form-control" name="${field.name}" value="${value}" ${required}>`
      }
      
      html += `</div>`
    })
    
    html += '</form>'
    return html
  }

  // Load options for select fields (relationships)
  async loadSelectOptions(fieldName, modelName) {
    try {
      const response = await fetch(`/api/modules/${this.moduleValue}/models/${modelName}?limit=100`)
      if (response.ok) {
        const data = await response.json()
        const select = document.querySelector(`select[name="${fieldName}"]`)
        if (select && data.records) {
          data.records.forEach(record => {
            const option = document.createElement('option')
            option.value = record.id
            option.textContent = record.name || record.title || `#${record.id}`
            select.appendChild(option)
          })
        }
      }
    } catch (e) {
      console.log(`Could not load options for ${modelName}`)
    }
  }

  // Submit the form
  async submitForm() {
    const modal = document.getElementById('moduleFormModal')
    const form = document.getElementById('moduleRecordForm')
    
    if (!form.checkValidity()) {
      form.classList.add('was-validated')
      return
    }

    const mode = modal.dataset.mode
    const model = modal.dataset.model
    const recordId = modal.dataset.recordId
    const moduleSlug = modal.dataset.moduleSlug

    // Collect form data
    const formData = new FormData(form)
    const data = Object.fromEntries(formData.entries())

    // Show loading state
    const saveBtn = modal.querySelector('.btn-primary')
    const originalText = saveBtn.innerHTML
    saveBtn.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Saving...'
    saveBtn.disabled = true

    try {
      const url = mode === 'add' 
        ? `/api/modules/${moduleSlug}/models/${model}`
        : `/api/modules/${moduleSlug}/models/${model}/${recordId}`
      
      const method = mode === 'add' ? 'POST' : 'PATCH'

      const response = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify(data)
      })

      if (response.ok) {
        // Close modal and refresh
        bootstrap.Modal.getInstance(modal).hide()
        this.showToast('success', `${this.humanize(model)} saved successfully!`)
        this.refreshData()
      } else {
        const error = await response.json()
        this.showToast('error', error.message || 'Failed to save record')
      }
    } catch (error) {
      console.error('Save failed:', error)
      this.showToast('error', 'Failed to save. Please try again.')
    } finally {
      saveBtn.innerHTML = originalText
      saveBtn.disabled = false
    }
  }

  // Close modal
  closeModal() {
    const modal = document.getElementById('moduleFormModal')
    if (modal) {
      bootstrap.Modal.getInstance(modal)?.hide()
    }
  }

  // Refresh data in the current canvas
  async refreshData() {
    console.log('📦 Refreshing canvas data...')
    
    // If there's a table, reload it
    const table = this.element.querySelector('table tbody')
    if (table) {
      table.innerHTML = '<tr><td colspan="100" class="text-center py-4"><div class="spinner-border text-primary"></div></td></tr>'
      
      const model = this.inferModelFromContext()
      try {
        const response = await fetch(`/api/modules/${this.moduleValue}/models/${model}?limit=50`)
        if (response.ok) {
          const data = await response.json()
          this.renderTableRows(table, data.records || [])
        }
      } catch (e) {
        table.innerHTML = '<tr><td colspan="100" class="text-center text-muted">No data available</td></tr>'
      }
    }
    
    // Reload stats
    this.loadInitialData()
  }

  // Render table rows
  renderTableRows(tbody, records) {
    if (records.length === 0) {
      tbody.innerHTML = '<tr><td colspan="100" class="text-center text-muted py-4">No records found</td></tr>'
      return
    }

    // Get column headers from thead
    const headers = Array.from(this.element.querySelectorAll('thead th')).map(th => th.textContent.trim().toLowerCase())
    
    tbody.innerHTML = records.map(record => {
      let row = '<tr data-id="' + record.id + '">'
      row += '<td><input type="checkbox" class="form-check-input"></td>'
      
      // Add cells for each visible field
      Object.entries(record).slice(0, 5).forEach(([key, value]) => {
        if (key !== 'id' && key !== 'entity_id') {
          row += `<td>${value ?? '-'}</td>`
        }
      })
      
      // Actions column
      row += `
        <td class="text-end">
          <button class="btn btn-sm btn-outline-primary" data-row-action="edit" data-id="${record.id}">
            <i data-lucide="edit-2"></i>
          </button>
          <button class="btn btn-sm btn-outline-danger" data-row-action="delete" data-id="${record.id}">
            <i data-lucide="trash-2"></i>
          </button>
        </td>
      `
      row += '</tr>'
      return row
    }).join('')

    // Re-bind row actions and icons
    this.bindButtonActions()
    this.initializeLucideIcons()
  }

  // Export data
  async exportData(model) {
    console.log(`📦 Exporting ${model} data...`)
    try {
      const response = await fetch(`/api/modules/${this.moduleValue}/models/${model}?limit=1000&format=csv`)
      if (response.ok) {
        const blob = await response.blob()
        const url = window.URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        a.download = `${model.toLowerCase()}_export.csv`
        a.click()
      }
    } catch (e) {
      this.showToast('error', 'Export failed')
    }
  }

  // Focus search input
  focusSearch() {
    const searchInput = this.element.querySelector('input[type="search"], input[placeholder*="search" i]')
    if (searchInput) {
      searchInput.focus()
    }
  }

  // Export PDF
  exportPdf() {
    window.print()
  }

  // Open report modal
  openReportModal(model) {
    this.showToast('info', 'Report generation coming soon!')
  }

  // Navigate to a canvas
  navigateToCanvas(canvasType, model) {
    const canvasSlug = `${this.moduleValue}/${model.toLowerCase()}_${canvasType}`
    if (window.scoutController?.loadScoutCanvas) {
      window.scoutController.loadScoutCanvas(canvasSlug)
    }
  }

  // Handle filter selection
  handleFilter(event, filter) {
    event.preventDefault()
    console.log(`📦 Applying filter: ${filter}`)
    
    // Update dropdown button text
    const dropdown = event.target.closest('.dropdown')
    if (dropdown) {
      const button = dropdown.querySelector('.dropdown-toggle')
      if (button) {
        button.textContent = event.target.textContent
      }
    }

    // Apply filter by reloading with filter param
    this.loadFilteredData(filter)
  }

  // Load filtered data
  async loadFilteredData(filter) {
    const model = this.inferModelFromContext()
    const table = this.element.querySelector('table tbody')
    
    if (table) {
      try {
        const response = await fetch(`/api/modules/${this.moduleValue}/models/${model}?filter=${encodeURIComponent(filter)}&limit=50`)
        if (response.ok) {
          const data = await response.json()
          this.renderTableRows(table, data.records || [])
        }
      } catch (e) {
        console.error('Filter failed:', e)
      }
    }
  }

  // Handle row action (edit, delete, view)
  handleRowAction(event) {
    event.preventDefault()
    const button = event.target.closest('[data-row-action]')
    const action = button?.dataset.rowAction
    const id = button?.dataset.id || button?.closest('tr')?.dataset.id
    // Use the modelValue from data attributes, fallback to infer
    const model = this.modelValue || this.inferModelFromContext()
    
    console.log(`📦 Row action: ${action} on ${model} id ${id} (module: ${this.moduleValue})`)
    
    if (!id) {
      console.error('📦 No record ID found for row action')
      this.showToast('error', 'Could not identify record')
      return
    }
    
    switch(action) {
      case 'edit':
        this.loadAndEditRecord(model, id)
        break
      case 'delete':
        this.confirmAndDelete(model, id)
        break
      case 'view':
        this.viewRecord(model, id)
        break
    }
  }

  // Load record and open edit modal
  async loadAndEditRecord(model, id) {
    console.log(`📦 Loading record for edit: ${this.moduleValue}/models/${model}/${id}`)
    try {
      const response = await fetch(`/api/modules/${this.moduleValue}/models/${model}/${id}`)
      if (response.ok) {
        const data = await response.json()
        console.log(`📦 Record loaded:`, data)
        this.openEditModal(model, id, data.record || data)
      } else {
        const errorText = await response.text()
        console.error(`📦 Failed to load record: ${response.status}`, errorText)
        this.showToast('error', `Failed to load record: ${response.status}`)
      }
    } catch (e) {
      console.error('📦 Error loading record:', e)
      this.showToast('error', 'Failed to load record')
    }
  }

  // Confirm and delete record
  async confirmAndDelete(model, id) {
    if (!confirm(`Are you sure you want to delete this ${this.humanize(model).toLowerCase()}?`)) {
      return
    }

    console.log(`📦 Deleting record: ${this.moduleValue}/models/${model}/${id}`)
    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      if (!csrfToken) {
        console.error('📦 No CSRF token found')
        this.showToast('error', 'Security token missing. Please refresh the page.')
        return
      }
      
      const response = await fetch(`/api/modules/${this.moduleValue}/models/${model}/${id}`, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        }
      })

      if (response.ok) {
        this.showToast('success', `${this.humanize(model)} deleted`)
        // Remove row from table
        const row = this.element.querySelector(`tr[data-id="${id}"]`)
        if (row) row.remove()
      } else {
        const errorText = await response.text()
        console.error(`📦 Delete failed: ${response.status}`, errorText)
        this.showToast('error', `Delete failed: ${response.status}`)
      }
    } catch (e) {
      console.error('📦 Delete error:', e)
      this.showToast('error', 'Delete failed: ' + e.message)
    }
  }

  // View record details
  viewRecord(model, id) {
    // Navigate to detail canvas or open detail modal
    const canvasSlug = `${this.moduleValue}/${model.toLowerCase()}_detail`
    if (window.scoutController?.loadScoutCanvas) {
      window.scoutController.loadScoutCanvas(canvasSlug, { id })
    }
  }

  // Toggle select all checkbox
  toggleSelectAll(checkbox) {
    const rowCheckboxes = this.element.querySelectorAll('tbody input[type="checkbox"]')
    rowCheckboxes.forEach(cb => cb.checked = checkbox.checked)
  }

  // Show toast notification
  showToast(type, message) {
    // Use existing toast system if available
    if (window.showToast) {
      window.showToast(type, message)
      return
    }

    // Create simple toast
    const toast = document.createElement('div')
    toast.className = `alert alert-${type === 'error' ? 'danger' : type === 'success' ? 'success' : 'info'} position-fixed`
    toast.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 250px;'
    toast.innerHTML = `
      <div class="d-flex align-items-center">
        <i data-lucide="${type === 'error' ? 'alert-circle' : type === 'success' ? 'check-circle' : 'info'}"></i>
        <span class="ms-2">${message}</span>
      </div>
    `
    document.body.appendChild(toast)
    
    if (window.lucide) window.lucide.createIcons()
    
    setTimeout(() => toast.remove(), 4000)
  }

  // Load initial data for the canvas
  async loadInitialData() {
    // Find stat cards and update them
    const statElements = this.element.querySelectorAll('[data-stat]')
    if (statElements.length === 0) return

    try {
      const response = await fetch(`/api/modules/${this.moduleValue}/stats`)
      if (response.ok) {
        const data = await response.json()
        this.updateStats(data)
      }
    } catch (error) {
      console.log('📦 Stats endpoint not available, using placeholder data')
      statElements.forEach(el => {
        if (el.textContent === '--') {
          el.textContent = '0'
        }
      })
    }
  }

  // Update stat cards with data
  updateStats(data) {
    Object.entries(data).forEach(([key, value]) => {
      const el = this.element.querySelector(`[data-stat="${key}"]`)
      if (el) {
        el.textContent = value
      }
    })
  }

  // Helper: Convert snake_case to Title Case
  humanize(str) {
    if (!str) return ''
    return str
      .replace(/_/g, ' ')
      .replace(/([A-Z])/g, ' $1')
      .replace(/^\w/, c => c.toUpperCase())
      .trim()
  }
}

