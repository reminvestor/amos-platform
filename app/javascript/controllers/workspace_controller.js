import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "sideNav", 
    "navToggle", 
    "chatArea", 
    "templateArea", 
    "chatMessages", 
    "chatInput", 
    "chatForm", 
    "templateTitle", 
    "templateContent", 
    "templateList", 
    "loadingOverlay",
    "resizeHandle"
  ]

  connect() {
    this.currentMode = "conversation" // conversation or work
    this.currentTemplate = null
    this.isResizing = false
    
    // Auto-focus chat input
    if (this.hasChatInputTarget) {
      this.chatInputTarget.focus()
    }
    
    // Load user templates
    this.loadTemplates()
    
    // Bind resize events
    this.bindResizeEvents()
    
    console.log("🤖 Scout AI workspace ready! (Powered by Claude 4)")
  }

  // Toggle side navigation
  toggleSideNav() {
    this.sideNavTarget.classList.toggle("expanded")
  }

  // Send chat message
  sendMessage(event) {
    event.preventDefault()
    
    const message = this.chatInputTarget.value.trim()
    if (!message) return
    
    // Add user message to chat
    this.addMessage(message, "user")
    
    // Clear input
    this.chatInputTarget.value = ""
    
    // Show loading
    this.showLoading()
    
    // Send to Scout AI (now powered by Claude 4)
    this.processMessage(message)
  }

  // Send suggestion message
  sendSuggestion(event) {
    const suggestion = event.target.dataset.suggestion
    
    this.chatInputTarget.value = suggestion
    this.sendMessage({ preventDefault: () => {} })
  }

  // Add message to chat
  addMessage(content, role) {
    const messageDiv = document.createElement("div")
    messageDiv.className = `message ${role}-message`
    
    const avatar = role === "ai" ? "fas fa-robot" : "fas fa-user"
    
    messageDiv.innerHTML = `
      <div class="message-avatar">
        <i class="${avatar}"></i>
      </div>
      <div class="message-content">
        <p>${content}</p>
      </div>
    `
    
    this.chatMessagesTarget.appendChild(messageDiv)
    this.scrollChatToBottom()
  }

  // Process message with AI
  async processMessage(message) {
    try {
      const response = await fetch("/workspace/chat", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify({ message: message })
      })

      const data = await response.json()
      
      // Hide loading
      this.hideLoading()
      
      if (data.success) {
        // Add AI response
        this.addMessage(data.response, "ai")
        
        // Handle any actions (like loading templates)
        if (data.action) {
          this.handleAction(data.action, data.payload)
        }
      } else {
        this.addMessage("Sorry, I couldn't process that request. Please try again.", "ai")
      }
      
    } catch (error) {
      console.error("Error sending message:", error)
      this.hideLoading()
      this.addMessage("Sorry, something went wrong. Please try again.", "ai")
    }
  }

  // Handle AI actions
  handleAction(action, payload) {
    switch (action) {
      case "load_template":
        this.loadTemplate(payload.template_id, payload.template_name)
        break
      case "switch_mode":
        this.switchToMode(payload.mode)
        break
      case "update_template":
        this.updateTemplateContent(payload.content)
        break
    }
  }

  // Switch between conversation and work modes
  switchToMode(mode) {
    const workspace = this.element
    
    if (mode === "work" && this.currentMode === "conversation") {
      workspace.classList.remove("conversation-mode")
      workspace.classList.add("work-mode")
      this.currentMode = "work"
      
      // Apply saved chat width when switching to work mode
      setTimeout(() => {
        this.loadChatWidth()
      }, 10)
      
      // Update chat header
      this.updateChatHeader("Scout")
      
    } else if (mode === "conversation" && this.currentMode === "work") {
      workspace.classList.remove("work-mode")
      workspace.classList.add("conversation-mode")
      this.currentMode = "conversation"
      this.currentTemplate = null
      
      // Reset chat area to full width in conversation mode
      if (this.hasChatAreaTarget) {
        this.chatAreaTarget.style.removeProperty('width')
        this.chatAreaTarget.style.removeProperty('flex')
        console.log("🔄 Reset chat area to full width for conversation mode")
      }
      
      // Update chat header
      this.updateChatHeader("What can I help you with today?")
    }
  }

  // Go to conversation mode
  goToConversation() {
    this.switchToMode("conversation")
    this.addMessage("Scout here! What would you like to work on?", "ai")
  }

  // Close current template
  closeTemplate() {
    this.switchToMode("conversation")
    this.addMessage("Template closed. What else can I help you with?", "ai")
  }

  // Load a template
  async loadTemplate(templateId, templateName) {
    try {
      this.showLoading()
      
      const response = await fetch("/workspace/load_template", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify({ template_id: templateId })
      })

      const data = await response.json()
      
      if (data.success) {
        // Switch to work mode
        this.switchToMode("work")
        
        // Update template area
        this.templateTitleTarget.textContent = templateName || data.template.name
        this.templateContentTarget.innerHTML = data.template.content
        
        this.currentTemplate = templateId
        
        // Add confirmation message
        this.addMessage(`Loaded ${templateName || data.template.name}. What would you like to change?`, "ai")
      }
      
    } catch (error) {
      console.error("Error loading template:", error)
      this.addMessage("Sorry, I couldn't load that template. Please try again.", "ai")
    } finally {
      this.hideLoading()
    }
  }

  // Update chat header
  updateChatHeader(title) {
    const chatTitle = this.chatAreaTarget.querySelector(".chat-title h2")
    if (chatTitle) {
      chatTitle.textContent = title
    }
  }

  // Update template content
  updateTemplateContent(content) {
    if (this.hasTemplateContentTarget) {
      this.templateContentTarget.innerHTML = content
    }
  }

  // Load user templates
  async loadTemplates() {
    try {
      console.log("📋 Loading templates...")
      const response = await fetch("/workspace/templates")
      console.log("📋 Templates response:", response)
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }
      
      const data = await response.json()
      console.log("📋 Templates data:", data)
      
      if (data.templates && this.hasTemplateListTarget) {
        this.renderTemplateList(data.templates)
        console.log("📋 Templates rendered successfully")
      } else {
        console.warn("📋 No templates data or template list target not found")
      }
    } catch (error) {
      console.error("📋 Error loading templates:", error)
      
      // Load default templates as fallback
      const defaultTemplates = [
        { id: 'landing_page', name: 'Landing Pages', type: 'builder' },
        { id: 'campaign', name: 'Email Campaigns', type: 'builder' },
        { id: 'analytics', name: 'Analytics', type: 'dashboard' }
      ]
      
      if (this.hasTemplateListTarget) {
        this.renderTemplateList(defaultTemplates)
        console.log("📋 Default templates loaded as fallback")
      }
    }
  }

  // Render template list in sidebar
  renderTemplateList(templates) {
    const listHTML = templates.map(template => `
      <div class="nav-item" data-action="click->workspace#selectTemplate" data-template-id="${template.id}">
        <i class="fas fa-file"></i>
        <span class="nav-text">${template.name}</span>
      </div>
    `).join("")
    
    this.templateListTarget.innerHTML = listHTML
  }

  // Select template from sidebar
  selectTemplate(event) {
    const templateId = event.target.closest("[data-template-id]").dataset.templateId
    const templateName = event.target.closest("[data-template-id]").querySelector(".nav-text").textContent
    
    this.loadTemplate(templateId, templateName)
  }

  // Utility methods
  showLoading() {
    if (this.hasLoadingOverlayTarget) {
      this.loadingOverlayTarget.classList.add("active")
    }
  }

  hideLoading() {
    if (this.hasLoadingOverlayTarget) {
      this.loadingOverlayTarget.classList.remove("active")
    }
  }

  scrollChatToBottom() {
    if (this.hasChatMessagesTarget) {
      this.chatMessagesTarget.scrollTop = this.chatMessagesTarget.scrollHeight
    }
  }

  getCSRFToken() {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')
    if (csrfToken) {
      return csrfToken.getAttribute('content')
    } else {
      console.warn("⚠️ CSRF token not found!")
      return ""
    }
  }

  // Resize functionality
  bindResizeEvents() {
    document.addEventListener('mousemove', this.handleResize.bind(this))
    document.addEventListener('mouseup', this.stopResize.bind(this))
  }

  startResize(event) {
    console.log("🔄 Starting resize...")
    this.isResizing = true
    this.resizeHandleTarget.classList.add('resizing')
    
    // Prevent text selection during resize
    document.body.style.userSelect = 'none'
    document.body.style.cursor = 'col-resize'
    
    event.preventDefault()
  }

  handleResize(event) {
    if (!this.isResizing) return
    
    const workspaceRect = this.element.getBoundingClientRect()
    const sideNavWidth = this.sideNavTarget.offsetWidth
    const mouseX = event.clientX - workspaceRect.left - sideNavWidth
    
    // Calculate new chat width as percentage
    const availableWidth = workspaceRect.width - sideNavWidth
    let newChatWidthPercent = (mouseX / availableWidth) * 100
    
    // Enforce min/max constraints
    const minWidth = 15 // 15% minimum
    const maxWidth = 50 // 50% maximum
    
    newChatWidthPercent = Math.max(minWidth, Math.min(maxWidth, newChatWidthPercent))
    
    console.log(`🔄 Resizing: mouseX=${mouseX}, availableWidth=${availableWidth}, newWidth=${newChatWidthPercent.toFixed(1)}%`)
    
    // Apply the new width
    this.setChatWidth(newChatWidthPercent)
  }

  stopResize() {
    if (!this.isResizing) return
    
    console.log("🔄 Stopping resize...")
    this.isResizing = false
    this.resizeHandleTarget.classList.remove('resizing')
    
    // Restore normal cursor and text selection
    document.body.style.userSelect = ''
    document.body.style.cursor = ''
    
    // Save the current width to localStorage
    this.saveChatWidth()
    
    // Update active preset button
    const currentWidth = parseFloat(getComputedStyle(this.element).getPropertyValue('--chat-width'))
    this.updateActivePreset(currentWidth)
  }

  setChatWidth(widthPercent) {
    console.log(`🎨 Setting chat width to: ${widthPercent}%`)
    this.element.style.setProperty('--chat-width', `${widthPercent}%`)
    
    // Also set it directly on the chat area with !important
    if (this.hasChatAreaTarget) {
      this.chatAreaTarget.style.setProperty('width', `${widthPercent}%`, 'important')
      this.chatAreaTarget.style.setProperty('flex', 'none', 'important')
      console.log(`🎨 Applied width directly to chat area: ${widthPercent}%`)
      console.log(`🎨 Chat area computed width:`, getComputedStyle(this.chatAreaTarget).width)
    }
  }

  loadChatWidth() {
    const savedWidth = localStorage.getItem('workspace-chat-width')
    const widthToApply = savedWidth ? parseFloat(savedWidth) : 18
    
    console.log(`📐 Loading chat width for work mode: ${widthToApply}%`)
    this.setChatWidth(widthToApply)
    
    // Update active preset to match loaded width
    setTimeout(() => {
      this.updateActivePreset(widthToApply)
    }, 100)
  }

  saveChatWidth() {
    const currentWidth = getComputedStyle(this.element).getPropertyValue('--chat-width')
    if (currentWidth) {
      const widthValue = parseFloat(currentWidth)
      localStorage.setItem('workspace-chat-width', widthValue.toString())
      console.log(`💾 Saved chat width: ${widthValue}%`)
    }
  }

  setLayoutPreset(event) {
    const width = parseFloat(event.target.closest('[data-width]').dataset.width)
    console.log(`🎯 Setting layout preset: ${width}%`)
    
    this.setChatWidth(width)
    this.saveChatWidth()
    
    // Update active preset button
    this.updateActivePreset(width)
  }

  updateActivePreset(currentWidth) {
    const presetButtons = document.querySelectorAll('.preset-btn')
    presetButtons.forEach(btn => {
      const btnWidth = parseFloat(btn.dataset.width)
      if (Math.abs(btnWidth - currentWidth) < 2) { // Allow 2% tolerance
        btn.classList.add('active')
      } else {
        btn.classList.remove('active')
      }
    })
  }
} 