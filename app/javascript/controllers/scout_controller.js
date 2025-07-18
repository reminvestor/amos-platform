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
    this.currentCanvas = null // Track current canvas
    this.isResizing = false
    
    // Auto-focus chat input
    if (this.hasChatInputTarget) {
      this.chatInputTarget.focus()
    }
    
    // Bind resize events
    this.bindResizeEvents()
    
    // Set up canvas globals immediately
    this.setupCanvasGlobals()
    
    console.log("🤖 Scout AI ready with intelligent canvas! (Powered by Claude 4)")
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
    
    // Process with Scout
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

  // Enhanced processMessage to handle canvas actions
  async processMessage(message) {
    try {
      console.log("🔄 Processing message:", message)
      
      const response = await fetch("/scout/chat", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify({ message: message })
      })

      console.log("📡 Scout response received:", response.status)
      const data = await response.json()
      console.log("📊 Scout response data:", data)
      
      // Hide loading
      this.hideLoading()
      
      if (data.message) {
        // Add AI response
        this.addMessage(data.message, "ai")
        
        // Check if Claude suggested a canvas to load
        if (data.canvas) {
          console.log(`🎨 Scout suggested canvas: ${data.canvas}`)
          console.log("🕐 Loading canvas in 1 second...")
          setTimeout(() => {
            console.log("🎯 Actually loading canvas now:", data.canvas)
            this.loadScoutCanvas(data.canvas, {})
          }, 1000)
        } else {
          console.log("ℹ️ No canvas suggested in response")
        }
        
        // Handle data changes that might require canvas refresh
        this.handleDataChanges(data)
      } else {
        console.log("❌ No message in response data")
        this.addMessage("Sorry, I couldn't process that request. Please try again.", "ai")
      }
      
    } catch (error) {
      console.error("❌ Error sending message:", error)
      this.hideLoading()
      this.addMessage("Sorry, something went wrong. Please try again.", "ai")
    }
  }

  // Handle data changes that should refresh current canvas
  handleDataChanges(data) {
    if (this.currentCanvas && data.tools_used) {
      console.log("🔄 Data changed, refreshing current canvas")
      setTimeout(() => {
        if (this.currentCanvas) {
          this.loadScoutCanvas(this.currentCanvas.type, this.currentCanvas.data)
        }
      }, 2000)
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
      this.currentCanvas = null
      
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
    this.addMessage("Canvas closed. What else can I help you with?", "ai")
  }

  // ========== SCOUT CANVAS FUNCTIONALITY ==========

  // Load a Scout canvas
  async loadScoutCanvas(canvasType, canvasData = {}) {
    try {
      console.log(`🎨 Loading Scout canvas: ${canvasType}`)
      console.log(`📦 Canvas data:`, canvasData)
      this.showLoading()

      console.log("📡 Making request to /scout/load_canvas")
      const response = await fetch("/scout/load_canvas", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify({ 
          canvas_type: canvasType, 
          canvas_data: canvasData 
        })
      })

      console.log(`📡 Canvas response status: ${response.status}`)
      const data = await response.json()
      console.log(`📊 Canvas response data:`, data)

      if (data.success) {
        console.log("✅ Canvas loading successful")
        
        // Switch to work mode to show the canvas
        console.log("🔄 Switching to work mode")
        this.switchToMode("work")
        
        // Update canvas area
        console.log("📝 Updating canvas content")
        console.log("🎯 Setting title to:", data.canvas.title)
        this.templateTitleTarget.textContent = data.canvas.title
        console.log("🎯 Setting content HTML (length:", data.canvas.content.length, ")")
        this.templateContentTarget.innerHTML = data.canvas.content
        
        // Store current canvas info
        this.currentCanvas = {
          type: canvasType,
          data: canvasData,
          title: data.canvas.title
        }
        console.log("💾 Stored current canvas:", this.currentCanvas)

        // Set up global canvas functions for the loaded content
        console.log("⚙️ Setting up canvas globals")
        this.setupCanvasGlobals()

        console.log(`✅ Canvas loaded successfully: ${data.canvas.title}`)
        
        // Add confirmation message to chat
        this.addMessage(`Loaded ${data.canvas.title}. You can interact with the data on the right while we continue our conversation here.`, "ai")
        
      } else {
        console.error("❌ Failed to load canvas:", data.error)
        this.addMessage(`Sorry, I couldn't load that view: ${data.error}`, "ai")
      }

    } catch (error) {
      console.error("❌ Canvas loading error:", error)
      this.addMessage("Sorry, I couldn't load that view. Please try again.", "ai")
    } finally {
      console.log("🔄 Hiding loading overlay")
      this.hideLoading()
    }
  }

  // Set up global functions that canvas content can call
  setupCanvasGlobals() {
    // Make functions available globally for canvas content
    window.scoutSendMessage = (message) => {
      this.sendScoutMessage(message)
    }

    window.scoutLoadCanvas = (canvasType, canvasData = {}) => {
      this.loadScoutCanvas(canvasType, canvasData)
    }

    window.scoutRefreshCanvas = () => {
      if (this.currentCanvas) {
        this.loadScoutCanvas(this.currentCanvas.type, this.currentCanvas.data)
      }
    }

    console.log("🔧 Canvas global functions set up")
  }

  // Send a message from canvas to Scout
  sendScoutMessage(message) {
    console.log(`💬 Canvas sending message: ${message}`)
    
    // Add user message to chat
    this.addMessage(message, "user")
    
    // Show loading and process with Scout
    this.showLoading()
    this.processMessage(message)
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
    const savedWidth = localStorage.getItem('scout-chat-width')
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
      localStorage.setItem('scout-chat-width', widthValue.toString())
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