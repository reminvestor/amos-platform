import { Controller } from "@hotwired/stimulus"
import MarkdownIt from "markdown-it"
import DOMPurify from "dompurify"

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
    "resizeHandle",
    "voiceMode",
    "canvasCloseBtn",
    "canvasToggleBtn"
  ]

  connect() {
    this.currentMode = "conversation"
    this.currentCanvas = null
    this.isResizing = false
    // Initialize markdown parser (safe: HTML disabled, emojis preserved)
    this.md = new MarkdownIt({ 
      html: false, 
      linkify: true, 
      breaks: true,  // Changed to true to handle line breaks better
      typographer: false 
    })
    
    // SECURITY: Safe HTML rendering with DOMPurify as defense-in-depth
    this.safeRender = (content) => {
      const rendered = this.md.render(content || '')
      return DOMPurify.sanitize(rendered, {
        ALLOWED_TAGS: ['p', 'br', 'strong', 'em', 'code', 'pre', 'ul', 'ol', 'li', 'a', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'table', 'thead', 'tbody', 'tr', 'th', 'td', 'hr', 'span', 'div'],
        ALLOWED_ATTR: ['href', 'target', 'rel', 'class'],
        ADD_ATTR: ['target', 'rel'], // Ensure links can have target/rel
        FORBID_TAGS: ['script', 'style', 'iframe', 'form', 'input', 'button'],
        FORBID_ATTR: ['onclick', 'onerror', 'onload', 'onmouseover']
      })
    }
    
    // Initialize streaming TTS state
    this.ttsBuffer = ''
    this.lastTTSPosition = 0
    this.ttsSentenceQueue = []
    this.ttsBufferTimeout = null
    this.ttsMinBufferTime = 500 // Wait 500ms of silence before speaking
    this.ttsLastChunkTime = 0
    
    // Initialize tool thinking UI
    this.toolThinkingElement = null
    this.toolThinkingSteps = []
    this.isShowingToolThinking = false
    this.toolThinkingTimeout = null
    
    // Make controller globally accessible
    window.scoutController = this
    
    // Check if we're in Team Space mode (Hub handles its own UI)
    this.inTeamSpace = document.getElementById('workspace')?.dataset?.inTeamSpace === 'true'
    
    if (this.inTeamSpace) {
      console.log("🌐 Scout in Team Space mode - canvas disabled, Hub handles UI")
      // Still set up globals but skip canvas initialization
      this.setupCanvasGlobals()
      // Don't continue with canvas/mode setup
      return
    }
    
    // Also listen for custom canvas load events
    this.handleCanvasLoadEvent = (event) => {
      const { canvas, data } = event.detail
      console.log("📨 Received canvas load event:", canvas, data)
      this.loadScoutCanvas(canvas, data)
    }
    document.addEventListener('scout:load-canvas', this.handleCanvasLoadEvent)
    
    // Clear canvas viewer on page load
    if (this.canvasViewerTarget) {
      this.canvasViewerTarget.innerHTML = ''
    }
    
    // Ensure we're in conversation mode on page load
    this.switchToMode("conversation")
    
    console.log("Scout controller connected")
    
    // Set up initial canvas functions immediately
    this.setupCanvasGlobals()
    
    // Bind resize events
    this.bindResizeEvents()
    
    // Restore saved chat width
    this.restoreChatWidth()
    
    // Set up mobile viewport listener for canvas overlay behavior
    this.setupMobileViewportListener()
    
    // Focus on chat input with defensive check
    if (this.hasChatInputTarget && this.chatInputTarget) {
      try {
        setTimeout(() => {
          if (this.chatInputTarget && this.chatInputTarget.focus) {
            this.chatInputTarget.focus()
          }
        }, 100)
      } catch (e) {
        console.log("Could not focus on chat input:", e.message)
      }
    }
    
    // Initialize ActionCable subscription for job notifications
    this.setupJobNotifications()
    
    // SECURITY: Clear any old-format localStorage keys that weren't user-specific
    // This prevents cross-user data leakage from before this fix
    this.clearOldFormatCanvasStates()
    
    // Restore canvas state if available
    this.restoreCanvasState()
    
    // Initialize toggle button state
    setTimeout(() => {
      this.updateCanvasToggleButtons()
    }, 100)
  }
  
  disconnect() {
    // Clean up event listener
    if (this.handleCanvasLoadEvent) {
      document.removeEventListener('scout:load-canvas', this.handleCanvasLoadEvent)
    }
    // Clean up resize listener
    if (this.handleResizeForMobile) {
      window.removeEventListener('resize', this.handleResizeForMobile)
    }
  }

  // ========== MOBILE VIEWPORT DETECTION ==========
  
  // Check if viewport is mobile-sized (768px or less)
  isMobileViewport() {
    return window.innerWidth <= 768
  }

  // Set up resize listener for mobile/desktop transitions
  setupMobileViewportListener() {
    this.handleResizeForMobile = () => {
      // If we're in work mode and switch to mobile, convert to overlay
      if (this.currentMode === 'work' && this.isMobileViewport()) {
        this.element.classList.add('mobile-canvas-overlay')
      }
      // If we're in overlay and switch to desktop, convert to work mode
      if (this.element.classList.contains('mobile-canvas-overlay') && !this.isMobileViewport()) {
        this.element.classList.remove('mobile-canvas-overlay')
      }
    }
    window.addEventListener('resize', this.handleResizeForMobile)
  }

  // Get the current space from the page
  getCurrentSpace() {
    // Try to get from data attribute on workspace element first (most reliable)
    const workspaceSpace = this.element?.dataset?.currentSpace
    if (workspaceSpace) return workspaceSpace
    
    // Fallback to body or other elements
    const spaceAttr = document.body.dataset.currentSpace || 
                      document.querySelector('[data-current-space]')?.dataset.currentSpace ||
                      'work'
    return spaceAttr
  }

  // Get user ID from data attribute (for user-specific localStorage keys)
  getUserId() {
    return this.element.dataset.scoutUserId || 'unknown'
  }
  
  // Get storage key with user ID for security (prevents cross-user data leakage)
  getStorageKey(space) {
    const userId = this.getUserId()
    return `scout_canvas_state_${userId}_${space}`
  }
  
  // Save canvas state to localStorage (per-user, per-space)
  saveCanvasState() {
    const currentSpace = this.getCurrentSpace()
    const storageKey = this.getStorageKey(currentSpace)
    
    if (this.currentCanvas) {
      localStorage.setItem(storageKey, JSON.stringify({
        type: this.currentCanvas.type,
        data: this.currentCanvas.data || {},
        title: this.currentCanvas.title,
        mode: this.currentMode
      }))
      console.log(`💾 Saved canvas state for ${currentSpace}:`, this.currentCanvas.type, "mode:", this.currentMode)
    } else if (this.currentMode === 'conversation') {
      // Save conversation mode even without a canvas
      localStorage.setItem(storageKey, JSON.stringify({
        type: null,
        data: {},
        title: null,
        mode: 'conversation'
      }))
      console.log(`💾 Saved conversation mode state for ${currentSpace} (no canvas)`)
    }
  }

  // Restore canvas state from localStorage for the current space
  restoreCanvasState() {
    const currentSpace = this.getCurrentSpace()
    const storageKey = this.getStorageKey(currentSpace)
    
    try {
      const savedState = localStorage.getItem(storageKey)
      if (savedState) {
        const canvasState = JSON.parse(savedState)
        console.log(`🔄 Found saved canvas state for ${currentSpace}:`, canvasState.type, "mode:", canvasState.mode)

        // If user was in conversation mode (no canvas), stay there on refresh
        // They can click the canvas view button when they want to see it
        if (canvasState.mode === 'conversation' || !canvasState.type) {
          console.log("💬 Staying in conversation mode - user can load canvas when ready")
          // Don't auto-load any canvas, just stay in chat view
          return
        }

        // Only restore canvas if user was in work mode with a canvas visible
        console.log("🔄 Restoring canvas:", canvasState.type)
        setTimeout(() => {
          this.loadScoutCanvas(canvasState.type, canvasState.data || {})
        }, 500)
      } else {
        // No saved state for this space
        // Personal space: default to conversation mode (no canvas)
        // Work/Team space: load dashboard as the default home experience
        if (currentSpace === 'personal') {
          console.log(`💬 Personal space - starting in conversation mode (no canvas)`)
          // Stay in conversation mode - user can click Home to see dashboard if they want
        } else {
          console.log(`🏠 No saved canvas state for ${currentSpace}, loading dashboard as home`)
          setTimeout(() => {
            this.loadScoutCanvas('default', {})
          }, 500)
        }
      }
    } catch (e) {
      console.log("Could not restore canvas state:", e.message)
      localStorage.removeItem(storageKey)
      // Stay in conversation mode on error
      console.log("💬 Staying in conversation mode due to error")
    }
  }

  // Clear canvas state for current space
  clearCanvasState() {
    const currentSpace = this.getCurrentSpace()
    const storageKey = this.getStorageKey(currentSpace)
    localStorage.removeItem(storageKey)
    console.log(`🗑️ Cleared canvas state for ${currentSpace}`)
  }
  
  // Clear all canvas states (for logout or reset)
  clearAllCanvasStates() {
    const userId = this.getUserId()
    ;['personal', 'work', 'team'].forEach(space => {
      // Clear user-specific keys
      localStorage.removeItem(`scout_canvas_state_${userId}_${space}`)
      // Also clear old format keys (in case any exist from before this fix)
      localStorage.removeItem(`scout_canvas_state_${space}`)
    })
    console.log("🗑️ Cleared all canvas states")
  }
  
  // SECURITY: Clear old-format localStorage keys that didn't include user ID
  // This prevents data leakage from before the user-specific key fix
  clearOldFormatCanvasStates() {
    let clearedCount = 0
    ;['personal', 'work', 'team'].forEach(space => {
      const oldKey = `scout_canvas_state_${space}`
      if (localStorage.getItem(oldKey)) {
        localStorage.removeItem(oldKey)
        clearedCount++
      }
    })
    if (clearedCount > 0) {
      console.log(`🔒 Security: Cleared ${clearedCount} old-format canvas states (not user-specific)`)
    }
  }

  // Toggle side navigation
  toggleSideNav() {
    this.sideNavTarget.classList.toggle("expanded")
  }

  // Send chat message
  sendMessage(event) {
    event.preventDefault()
    
    // Check if we're in Hub mode (channel or DM) - let hub_sidebar_controller handle it
    const chatMessages = document.getElementById('chat-messages')
    const hubMode = chatMessages?.dataset?.hubMode
    if (hubMode && hubMode !== 'amos' && hubMode !== 'scout') {
      console.log('🌐 Scout: Skipping message - Hub mode active:', hubMode)
      return
    }
    
    const message = this.chatInputTarget.value.trim()
    if (!message) return

    // Allow interrupting an in-flight stream with new context.
    // If Scout is currently streaming, abort it and immediately start a new request.
    this.interruptStreamingIfNeeded()
    
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
  addMessage(content, role, options = {}) {
    // Don't create empty messages unless it's for loading
    if (!content && role !== "ai") {
      console.log("Skipping empty message for role:", role)
      return null
    }
    
    // Ensure chat messages target exists
    if (!this.chatMessagesTarget) {
      console.error("❌ Chat messages target not available in addMessage")
      return null
    }

    const messageDiv = document.createElement("div")
    messageDiv.className = `message ${role}-message`
    const messageId = `msg-${Date.now()}`
    messageDiv.id = messageId

    // Use Lucide icons for avatars
    const avatarIcon = role === "ai" ? "bot" : "user"
    const avatarLabel = role === "ai" ? "AI Assistant" : "You"

    // Parse markdown for AI messages using markdown-it
    let formattedContent = role === "ai" ? this.md.render(content || '') : this.escapeHtml(content)

    // Add loading indicator for empty AI messages (unless it's for streaming)
    if (role === "ai" && !content && !options.streaming) {
      formattedContent = '<span class="loading-dots"><span>.</span><span>.</span><span>.</span></span>'
    }

    messageDiv.innerHTML = `
      <div class="message-content">
        <div class="message-avatar" role="img" aria-label="${avatarLabel}">
          <i data-lucide="${avatarIcon}" aria-hidden="true"></i>
        </div>
        <div class="message-bubble">
          ${formattedContent}
        </div>
      </div>
    `

    this.chatMessagesTarget.appendChild(messageDiv)

    // Also add to voice mode chat if it exists
    const voiceModeChat = document.getElementById('voice-mode-chat-messages')
    if (voiceModeChat) {
      const clonedMessage = messageDiv.cloneNode(true)
      voiceModeChat.appendChild(clonedMessage)
    }

    // Initialize Lucide icons for the new message
    if (typeof lucide !== 'undefined') {
      lucide.createIcons()
    }
    
    // If we are currently streaming another AI message, keep that bubble at the bottom
    if (this.currentStreamingContent !== undefined && this.streamingMessageElement) {
      const streamingContainer = this.streamingMessageElement.closest('.message')
      if (streamingContainer && streamingContainer !== messageDiv) {
        this.chatMessagesTarget.appendChild(streamingContainer)
      }
    }
    this.scrollChatToBottom()
    
    // Return the created message div
    return messageDiv
  }
  
  // Set up ActionCable subscription for job notifications
  setupJobNotifications() {
    console.log("🔌 Setting up ActionCable job notifications")
    console.log("🔍 Checking ActionCable availability...")
    console.log("App object:", typeof App)
    console.log("App.cable:", typeof App?.cable)
    
    if (typeof App === 'undefined' || !App.cable) {
      console.error("❌ ActionCable not available! App:", typeof App, "App.cable:", typeof App?.cable)
      console.log("🔄 Attempting to create ActionCable consumer manually...")
      
      // Try to create consumer manually if App isn't available
      try {
        if (typeof createConsumer !== 'undefined') {
          window.App = { cable: createConsumer() }
          console.log("✅ Manually created ActionCable consumer")
        } else {
          console.error("❌ createConsumer not available either")
          return
        }
      } catch (e) {
        console.error("❌ Failed to create ActionCable consumer:", e)
        return
      }
    }
    
    console.log("🎯 ActionCable consumer available, creating subscription...")
    
    // Subscribe to job notification channel
    try {
      this.jobNotificationSubscription = App.cable.subscriptions.create("JobNotificationChannel", {
        connected() {
          console.log("✅ Connected to JobNotificationChannel")
        },
        
        disconnected() {
          console.log("❌ Disconnected from JobNotificationChannel")
        },
        
        received: (data) => {
          console.log("📢 Job notification received:", data)
          this.handleJobNotification(data)
        }
      })
      console.log("✅ JobNotificationChannel subscription created")
    } catch (e) {
      console.error("❌ Failed to create subscription:", e)
    }
  }
  
  // Handle incoming job notifications
  handleJobNotification(data) {
    const { type, job_type, landing_page_id, message, success, timestamp } = data
    
    console.log(`🔔 Job ${type}: ${job_type} for landing page ${landing_page_id}`)
    
    switch (type) {
      case 'job_started':
        this.showJobStartedFeedback(data)
        break
        
      case 'job_completed':
        this.handleJobCompleted(data)
        break
        
      case 'job_failed':
        this.handleJobFailed(data)
        break
        
      default:
        console.log("Unknown job notification type:", type)
    }
  }
  
  // Show visual feedback when job starts
  showJobStartedFeedback(data) {
    console.log("⏳ Job started:", data.message)
    
    // Add visual indicator to current canvas if it's the affected landing page
    if (this.currentCanvas && 
        this.currentCanvas.type === 'landing_page_details' && 
        this.currentCanvas.data?.landing_page_id == data.landing_page_id) {
      
      console.log("🎨 Adding processing indicator to current canvas")
      this.showCanvasProcessing(data.message)
    }
    
    // Add message to chat
    this.addMessage(`✨ ${data.message}`, "ai")
  }
  
  // Handle successful job completion
  handleJobCompleted(data) {
    console.log("✅ Job completed successfully:", data.message)
    
    // Hide processing indicator
    this.hideCanvasProcessing()
    
    // Refresh canvas if it's the affected landing page
    if (this.currentCanvas && 
        this.currentCanvas.type === 'landing_page_details' && 
        this.currentCanvas.data?.landing_page_id == data.landing_page_id) {
      
      console.log("🔄 Refreshing current canvas with updated content")
      setTimeout(() => {
        this.loadScoutCanvas(this.currentCanvas.type, this.currentCanvas.data)
      }, 500) // Small delay to ensure database is updated
    }
    
    // Add success message to chat
    this.addMessage(`✅ ${data.message}`, "ai")
  }
  
  // Handle job failure
  handleJobFailed(data) {
    console.log("❌ Job failed:", data.message)
    
    // Hide processing indicator
    this.hideCanvasProcessing()
    
    // Add error message to chat
    this.addMessage(`❌ ${data.message}`, "ai")
  }
  
  // Show processing indicator on canvas
  showCanvasProcessing(message) {
    // Add a processing overlay to the canvas
    if (this.hasTemplateContentTarget) {
      const overlay = document.createElement('div')
      overlay.id = 'canvas-processing-overlay'
      overlay.className = 'position-absolute top-0 start-0 w-100 h-100 d-flex align-items-center justify-content-center'
      overlay.style.backgroundColor = 'rgba(255, 255, 255, 0.9)'
      overlay.style.zIndex = '1000'
      overlay.innerHTML = `
        <div class="text-center">
          <div class="spinner-border text-primary mb-3" role="status">
            <span class="visually-hidden">Processing...</span>
          </div>
          <div class="fw-medium">${message}</div>
        </div>
      `
      
      // Add overlay to canvas content
      const canvasContainer = this.templateContentTarget.parentElement
      if (canvasContainer && canvasContainer.style.position !== 'relative') {
        canvasContainer.style.position = 'relative'
      }
      this.templateContentTarget.appendChild(overlay)
    }
  }
  
  // Hide processing indicator
  hideCanvasProcessing() {
    const overlay = document.getElementById('canvas-processing-overlay')
    if (overlay) {
      overlay.remove()
    }
  }

  // Enhanced processMessage to handle canvas actions and file uploads
  async processMessage(message, files = []) {
    try {
      console.log("🔄 Processing message:", message)

      // If a previous request is still streaming, abort it before starting a new one.
      this.interruptStreamingIfNeeded()
      this.isStreaming = true
      this.currentChatAbortController = new AbortController()
      
      // Interrupt any ongoing TTS when user sends a new message
      if (window.ttsManager) {
        console.log("🛑 Interrupting TTS for new message")
        window.ttsManager.interrupt()
      }
      
      // Clear any pending TTS buffer
      this.clearTTSState()
      
      // If there are files, we need to upload them first
      let fileUrls = [];
      if (files && files.length > 0) {
        console.log("📎 Uploading files:", files.map(f => f.name))
        fileUrls = await this.uploadFiles(files);
        console.log("📎 Upload complete, file URLs:", fileUrls)
      } else {
        console.log("📎 No files to upload")
      }
      
      // Get selected model if available
      const selectedModel = window.getSelectedModel ? window.getSelectedModel() : null;

      // Use streaming endpoint for better timeout handling
      const response = await fetch("/scout/chat_stream", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        signal: this.currentChatAbortController.signal,
        body: JSON.stringify({
          message: message,
          current_canvas: this.currentCanvas,
          file_urls: fileUrls,
          model: selectedModel
        })
      })

      console.log("📡 Scout streaming response received:", response.status)
      
      // Handle payment required (insufficient tokens)
      if (response.status === 402) {
        try {
          const errorData = await response.json()
          console.log("💳 Payment required:", errorData)
          
          // Show message to user before redirecting
          this.addMessage(
            "⚠️ " + (errorData.message || "You're out of tokens. Redirecting to billing..."),
            "assistant",
            { error: true }
          )
          
          // Redirect after a brief delay so user sees the message
          setTimeout(() => {
            window.location.href = errorData.redirect_url || '/billing/setup_payment'
          }, 1500)
          
          return
        } catch (e) {
          // If JSON parsing fails, just redirect
          window.location.href = '/billing/setup_payment'
          return
        }
      }
      
      // Handle redirect to billing (in case server returns redirect that fetch followed)
      if (response.url && response.url.includes('/billing')) {
        console.log("💳 Redirected to billing, navigating...")
        this.addMessage(
          "⚠️ You're out of tokens. Redirecting to billing...",
          "assistant",
          { error: true }
        )
        setTimeout(() => {
          window.location.href = response.url
        }, 1500)
        return
      }
      
      if (!response.body) {
        throw new Error("No response body received")
      }
      
      const reader = response.body.getReader()
      this.currentStreamReader = reader
      const decoder = new TextDecoder()
      let finalResponseData = null
      let buffer = '' // Buffer for incomplete SSE events
      
      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          
          const chunk = decoder.decode(value)
          buffer += chunk
          
          // Split by double newline (SSE event boundary)
          const events = buffer.split('\n\n')
          
          // Keep the last part in buffer (might be incomplete)
          buffer = events.pop() || ''
          
          for (const event of events) {
            const lines = event.split('\n')
            for (const line of lines) {
              if (line.startsWith('data: ')) {
                try {
                  const jsonStr = line.slice(6)
                  console.log("Parsing JSON:", jsonStr.length > 200 ? jsonStr.substring(0, 200) + "..." : jsonStr)
                
                const data = JSON.parse(jsonStr)
                console.log("📊 Streaming data:", data.type, data.type === 'response' ? '(Final Response)' : (data.message || data.content))
                
                // Add detailed logging for content chunks
                if (data.type === 'content') {
                  console.log("🔥 CONTENT CHUNK RECEIVED:", data.content, "Current streaming content:", this.currentStreamingContent)
                }
                
                if (data.type === 'update') {
                  // Show progress update in the streaming window
                  console.log("🔄 Progress:", data.message)
                  this.showStreamingProgress(data.message)
                  
                  // Check if this is a SHORT status message (not actual content)
                  // Status messages are brief internal updates, not user-facing content
                  const isShortStatusMessage = data.message && data.message.length < 50 && (
                    data.message.startsWith('💬 Message') || 
                    data.message.startsWith('📋 Processing') ||
                    data.message.startsWith('🔍 Searching') ||
                    data.message === 'streaming' ||
                    data.message === '💬 streaming'
                  )
                  
                  if (!isShortStatusMessage && data.message && data.message.trim()) {
                    // This is actual content from Amos - stream it
                    console.log('📝 Amos content received via update:', data.message)
                    
                    // Initialize streaming if not already started
                    if (this.currentStreamingContent === undefined || this.currentStreamingContent === null) {
                      // Initialize with the current chunk instead of empty string
                      this.currentStreamingContent = data.message
                      
                      // Clean up ALL loading dots everywhere first
                      const allLoadingDots = document.querySelectorAll('.loading-dots')
                      allLoadingDots.forEach(dots => {
                        console.log('🧹 Removing loading dots during streaming init')
                        try {
                          // Get parent element before removing
                          const parent = dots.parentElement
                          dots.remove()
                          // Force parent to reflow if it exists
                          if (parent && parent.style) {
                            parent.style.display = 'none'
                            parent.offsetHeight // Force reflow
                            parent.style.display = ''
                          }
                        } catch (e) {
                          console.warn('⚠️ Error removing loading dots:', e)
                          // Try simple removal as fallback
                          try { dots.remove() } catch (e2) {}
                        }
                      })
                      
                      // Find the last AI message or create a new one
                      if (!this.chatMessagesTarget) {
                        console.error('❌ Chat messages target not found!')
                        return
                      }
                      
                      const messages = this.chatMessagesTarget.querySelectorAll('.message')
                      const lastMessage = messages[messages.length - 1]
                      
                      // Check if we need to create a new message
                      let needNewMessage = true
                      let targetBubble = null
                      
                      if (lastMessage && lastMessage.classList.contains('ai-message')) {
                        const bubble = lastMessage.querySelector('.message-bubble')
                        if (bubble && !bubble.textContent.trim()) {
                          // Empty AI message exists - use it
                          needNewMessage = false
                          targetBubble = bubble
                          console.log('🔄 Reusing existing empty AI message')
                        }
                      }
                      
                      if (needNewMessage) {
                        console.log('📝 Creating new message for streaming')
                        const messageDiv = this.addMessage('', 'ai', { streaming: true })
                        console.log('📝 New message div:', messageDiv)
                        if (messageDiv) {
                          const bubble = messageDiv.querySelector('.message-bubble')
                          console.log('📝 Found bubble in new message:', !!bubble)
                          if (bubble) {
                            this.streamingMessageElement = bubble
                            targetBubble = bubble
                            console.log('✅ Set streamingMessageElement to new bubble')
                          }
                        }
                      } else {
                        // Use existing empty message
                        this.streamingMessageElement = targetBubble
                        console.log('✅ Set streamingMessageElement to existing bubble')
                        // Remove loading dots from existing message
                        if (targetBubble) {
                          const existingDots = targetBubble.querySelector('.loading-dots')
                          if (existingDots) {
                            console.log('🧹 Removing loading dots from existing message bubble')
                            existingDots.remove()
                          }
                        }
                      }
                      
                      // Store reference locally to prevent loss during async operations
                      const streamingElement = this.streamingMessageElement
                      
                      // Now render the first chunk (already included in currentStreamingContent)
                      if (streamingElement) {
                        console.log('✅ Rendering first chunk to streaming element:', this.currentStreamingContent)
                        // Remove any remaining loading dots in the bubble
                        const bubbleDots = streamingElement.querySelector('.loading-dots')
                        if (bubbleDots) {
                          console.log('🧹 Removing loading dots from streaming bubble')
                          bubbleDots.remove()
                        }
                        
                        // Log element state before update
                        console.log('🔍 Streaming element before update:', {
                          element: streamingElement,
                          currentContent: streamingElement.innerHTML,
                          hasLoadingDots: !!streamingElement.querySelector('.loading-dots')
                        })
                        
                        // Force immediate DOM update
                        // Use setTimeout(0) to ensure DOM has updated after loading dots removal
                        setTimeout(() => {
                          if (streamingElement) {
                            const content = this.currentStreamingContent
                            
                            // Safety check: ensure content is a valid string before rendering
                            if (typeof content === 'string' && content.trim()) {
                              // Clear and set content to force repaint
                              streamingElement.style.display = 'none'
                              streamingElement.offsetHeight // Force reflow
                              streamingElement.innerHTML = this.safeRender(content)
                              streamingElement.style.display = 'block'
                              
                              console.log('✅ Initial streaming render complete:', content)
                              console.log('🔍 Element after update:', streamingElement.innerHTML)
                              this.scrollChatToBottom()
                            } else {
                              console.warn('⚠️ No valid content to render:', typeof content, content)
                            }
                          }
                        }, 0)
                        
                        // Handle TTS for voice mode
                        this.handleStreamingTTS(data.message)
                      } else {
                        console.error('❌ No streaming element found! Cannot display streaming content.')
                      }
                    } else {
                      // Update streaming content - append, don't replace!
                      this.currentStreamingContent += data.message
                      
                      console.log('📊 Streaming state check:', {
                        hasStreamingElement: !!this.streamingMessageElement,
                        currentContentLength: this.currentStreamingContent.length,
                        newChunk: data.message
                      })
                      
                      if (this.streamingMessageElement) {
                        console.log('📝 Updating streaming content, total length:', this.currentStreamingContent.length)
                        // Force DOM update with more aggressive approach
                        const element = this.streamingMessageElement
                        const content = this.currentStreamingContent
                        
                        // Safety check: ensure content is a valid string
                        if (typeof content === 'string' && content.trim()) {
                          // Clear and set content to force repaint
                          element.style.display = 'none'
                          element.offsetHeight // Force reflow
                          element.innerHTML = this.safeRender(content)
                          element.style.display = 'block'
                          
                          console.log('📝 DOM update forced, content length:', content.length)
                          this.scrollChatToBottom()
                        }
                      } else {
                        // Try to recover: find the last AI message and use its bubble
                        console.warn('⚠️ Streaming element lost, attempting recovery...')
                        const messages = this.chatMessagesTarget.querySelectorAll('.message.ai-message')
                        const lastAiMessage = messages[messages.length - 1]
                        
                        if (lastAiMessage) {
                          const bubble = lastAiMessage.querySelector('.message-bubble')
                          if (bubble) {
                            console.log('✅ Recovered streaming element from last AI message')
                            this.streamingMessageElement = bubble
                            const content = this.currentStreamingContent
                            
                            if (typeof content === 'string' && content.trim()) {
                              bubble.innerHTML = this.safeRender(content)
                              console.log('📝 Updated recovered element with content length:', content.length)
                              this.scrollChatToBottom()
                            }
                          }
                        } else {
                          // Create a new message for the remaining content
                          console.log('⚠️ No AI message found, creating new one')
                          const newMessage = this.addMessage(this.currentStreamingContent, 'ai')
                          if (newMessage) {
                            this.streamingMessageElement = newMessage.querySelector('.message-bubble')
                          }
                        }
                      }
                      
                      // Handle TTS for voice mode
                      this.handleStreamingTTS(data.message)
                      
                      // Also check if this might be an agent question being streamed
                      if (data.metadata && (data.metadata.from_agent || data.metadata.awaiting_response)) {
                        console.log("🎤 Possible agent content in streaming, metadata:", data.metadata)
                        
                        // If we detect a question mark in streamed content from an agent
                        if (this.currentStreamingContent && this.currentStreamingContent.includes('?')) {
                          console.log("🔍 Question detected in streaming content from agent")
                          // Mark for enhanced TTS handling
                          this.streamingIsAgentQuestion = true
                        }
                      }
                    }
                  } else if (data.message === '💬 streaming') {
                    console.log('📝 Streaming started signal')
                    
                    // Only initialize if we haven't already started streaming
                    if (this.currentStreamingContent === undefined || this.currentStreamingContent === null) {
                      // Initialize empty for the streaming signal (no content yet)
                      this.currentStreamingContent = ''
                      
                      // Find the last AI message or create a new one
                      const messages = this.chatMessagesTarget.querySelectorAll('.message')
                      const lastMessage = messages[messages.length - 1]
                      
                      // Only create new message if last one isn't already an empty AI message
                      if (!lastMessage || !lastMessage.classList.contains('ai-message') || 
                          lastMessage.querySelector('.message-bubble')?.textContent.trim()) {
                        const newMessage = this.addMessage('', 'ai')
                        const bubble = newMessage?.querySelector('.message-bubble')
                        if (bubble) {
                          this.streamingMessageElement = bubble
                          console.log("🔍 Created new message for streaming")
                        }
                      } else {
                        // Use existing empty AI message
                        const bubble = lastMessage.querySelector('.message-bubble')
                        if (bubble) {
                          this.streamingMessageElement = bubble
                          console.log("🔍 Using existing message for streaming")
                        }
                      }
                    } else {
                      console.log("📝 Already streaming, not resetting")
                    }
                  }
                } else if (data.type === 'add_tool_message' || data.type === 'tool_detected') {
                  // Tool messages are now saved server-side and will appear via intermediate_message
                  console.log('🔧 Tool detected:', data.tool_name || data.name)
                  
                  // Show in tool thinking UI if not already streaming
                  if (this.currentStreamingContent === undefined) {
                    const toolName = data.tool_name || data.name
                    this.addToolThinkingStep(`Using ${toolName}...`)
                  }
                } else if (data.type === 'tool_start') {
                  // Tool messages are now saved server-side and will appear via intermediate_message
                  console.log('🔧 Tool started:', data.name)
                  
                  // Show in tool thinking UI if not already streaming
                  if (this.currentStreamingContent === undefined) {
                    this.addToolThinkingStep(`Running ${data.name}...`)
                  }
                } else if (data.type === 'tool_result' || data.type === 'tool_end') {
                  // Tool messages are now saved server-side and will appear via intermediate_message
                  console.log('✅ Tool completed:', data.name || data.tool_name)
                } else if (data.type === 'progress') {
                  // Progress updates from long-running tools with percentage
                  console.log('📊 Progress:', data.tool, data.message, data.percentage + '%')
                  this.updateToolProgress(data)
                } else if (data.type === 'intermediate_message') {
                  // Explanatory assistant messages between tool calls
                  if (data.content) {
                    // Finalize any current streaming bubble so this renders as a separate message
                    if (this.currentStreamingContent !== undefined && this.streamingMessageElement) {
                      try {
                        // Only finalize if there's actual content
                        if (this.currentStreamingContent && this.currentStreamingContent.trim()) {
                          this.streamingMessageElement.innerHTML = this.safeRender(this.currentStreamingContent)
                        } else {
                          // Remove empty streaming bubble
                          const messageContainer = this.streamingMessageElement.closest('.message')
                          if (messageContainer) {
                            messageContainer.remove()
                          }
                        }
                      } catch (e) {
                        console.warn('⚠️ Failed to finalize streaming bubble before intermediate message', e)
                      }
                      this.currentStreamingContent = undefined
                      this.streamingMessageElement = null
                    }
                    this.addMessage(data.content, 'ai')
                  }
                } else if (data.type === 'enable_chat') {
                  // Re-enable chat immediately after parallel processing starts
                  console.log('💬 Enabling chat for continued conversation')
                  this.enableChatInput()
                  if (data.message) {
                    console.log('📢 Chat enabled message:', data.message)
                  }
                } else if (data.type === 'load_canvas') {
                  // Streamed instruction to load a canvas immediately
                  try {
                    console.log('📋 Streaming: load_canvas received:', data.canvas)
                    // Clean up any wizard blocking overlay that may interfere with modals
                    try {
                      const overlay = document.getElementById('wizard-blocking-overlay')
                      if (overlay) overlay.remove()
                    } catch (e) {}
                    // Clean up any stale bootstrap backdrops before loading
                    try {
                      document.body.classList.remove('modal-open')
                      document.querySelectorAll('.modal-backdrop').forEach(b => b.remove())
                    } catch (e) {}
                    this.loadScoutCanvas(data.canvas, data.canvas_data || {})
                  } catch (e) {
                    console.warn('⚠️ Failed direct load_canvas during streaming, dispatching event', e)
                    const evt = new CustomEvent('scout:load-canvas', { detail: { canvas: data.canvas, data: data.canvas_data || {} } })
                    document.dispatchEvent(evt)
                  }
                } else if (data.type === 'canvas_update') {
                  // Handle canvas update events - always force refresh for updates
                  try {
                    console.log('🎨 Streaming: canvas_update received:', data.canvas_type)
                    this.loadScoutCanvas(data.canvas_type, data.canvas_data || {}, true) // Force refresh
                  } catch (e) {
                    console.warn('⚠️ Failed canvas_update during streaming', e)
                  }
                } else if (data.type === 'step_completed') {
                  // Handle step completion events
                  try {
                    console.log('✅ Step completed:', data.step_name || data.step_id)
                    // The canvas update will be sent separately, so we just log here
                    if (data.message) {
                      console.log(data.message)
                    }
                  } catch (e) {
                    console.warn('⚠️ Failed to handle step_completed', e)
                  }
                } else if (data.type === 'content') {
                  console.log("🎯 ENTERING CONTENT HANDLER - data.content:", data.content, "currentStreamingContent defined?", this.currentStreamingContent !== undefined)
                  
                  // Initialize streaming if not already started
                  if (this.currentStreamingContent === undefined) {
                    console.log('📝 First content chunk received - initializing streaming')
                    this.currentStreamingContent = ''
                    
                    // Find the last AI message or create a new one
                    const messages = this.chatMessagesTarget.querySelectorAll('.message')
                    const lastMessage = messages[messages.length - 1]
                    
                    // Only create new message if last one isn't already an empty AI message
                    if (!lastMessage || !lastMessage.classList.contains('ai-message') || 
                        lastMessage.querySelector('.message-bubble')?.textContent.trim()) {
                      const newMessage = this.addMessage('', 'ai')
                      const bubble = newMessage?.querySelector('.message-bubble')
                      if (bubble) {
                        this.streamingMessageElement = bubble
                      }
                    } else {
                      // Use existing empty AI message
                      const bubble = lastMessage.querySelector('.message-bubble')
                      if (bubble) {
                        this.streamingMessageElement = bubble
                      }
                    }
                  }
                  
                  // Handle content chunks for streaming
                  if (data.content && this.currentStreamingContent !== undefined) {
                    this.currentStreamingContent += data.content
                    console.log("📝 Accumulated content:", this.currentStreamingContent.length, "chars")
                    console.log("🔍 Content preview:", JSON.stringify(this.currentStreamingContent.substring(this.currentStreamingContent.length - 50)))
                    
                    // Check for streaming TTS
                    this.handleStreamingTTS(data.content)
                    
                    // Debug: Check for excessive newlines in accumulated content
                    const newlineMatches = this.currentStreamingContent.match(/\n/g)
                    if (newlineMatches && newlineMatches.length > 10) {
                      console.warn(`⚠️ Accumulated content has ${newlineMatches.length} newlines!`)
                    }
                    
                    // Update the current streaming message bubble even if other messages were appended later
                    let targetBubble = this.streamingMessageElement
                    if (!targetBubble) {
                      const messages = this.chatMessagesTarget.querySelectorAll('.message')
                      console.log("🔍 Found", messages.length, "total messages")
                      const lastMessage = messages[messages.length - 1]
                      if (lastMessage && lastMessage.classList.contains('ai-message')) {
                        targetBubble = lastMessage.querySelector('.message-bubble')
                      }
                    }
                    if (targetBubble) {
                      // Render markdown safely during streaming; lists/headings form progressively
                      // Remove loading dots if they exist
                      const loadingDots = targetBubble.querySelector('.loading-dots')
                      if (loadingDots) {
                        loadingDots.remove()
                      }
                      
                      // Only update if we have actual content
                      if (this.currentStreamingContent && this.currentStreamingContent.trim()) {
                        // Debug: Log what we're trying to render
                        if (this.currentStreamingContent.includes('*') || this.currentStreamingContent.includes('-')) {
                          console.log('📝 Rendering markdown with lists:', this.currentStreamingContent.slice(-200))
                        }
                        targetBubble.innerHTML = this.safeRender(this.currentStreamingContent)
                        this.streamingMessageElement = targetBubble
                        
                        // Also update voice mode chat if it exists
                        const messageContainer = targetBubble.closest('.message')
                        if (messageContainer && messageContainer.id) {
                          const voiceModeMessage = document.querySelector(`#voice-mode-chat-messages #${messageContainer.id}`)
                          if (voiceModeMessage) {
                            const voiceModeBubble = voiceModeMessage.querySelector('.message-bubble')
                            if (voiceModeBubble) {
                              voiceModeBubble.innerHTML = this.safeRender(this.currentStreamingContent)
                            }
                          }
                        }
                      } else {
                        // Remove empty message bubble if no content
                        const messageContainer = targetBubble.closest('.message')
                        if (messageContainer && !targetBubble.textContent.trim()) {
                          messageContainer.remove()
                          // Also remove from voice mode chat
                          if (messageContainer.id) {
                            const voiceModeMessage = document.querySelector(`#voice-mode-chat-messages #${messageContainer.id}`)
                            if (voiceModeMessage) {
                              voiceModeMessage.remove()
                            }
                          }
                        }
                      }
                    } else {
                      console.error("❌ No streaming target bubble found for AI content update")
                    }
                    this.scrollChatToBottom()
                  }
                } else if (data.type === 'response') {
                  // Final response received - hide streaming window and show message
                  console.log("🎯 RESPONSE TYPE DETECTED!")
                  console.log("🔍 Raw data object:", data)
                  finalResponseData = data.data
                  console.log("✅ Final response received, message length:", finalResponseData?.message?.length || 0)
                  console.log("📚 Sources in response:", finalResponseData?.sources)
                  console.log("📦 Full finalResponseData keys:", Object.keys(finalResponseData || {}))
                  console.log("📋 Full finalResponseData object:", finalResponseData)

                  // Hide streaming window first
                  this.hideStreamingWindow()
                }
              } catch (e) {
                console.log("JSON parse error for line:", e.message)
                console.log("Line length:", line.length)
                console.log("Line sample:", line.substring(0, 100) + "...")
                
                // Try to extract data manually if JSON parsing fails
                if (line.includes('"type":"response"')) {
                  try {
                    // Extract the response data manually
                    const match = line.match(/"data":\s*({.*})}\s*$/)
                    if (match) {
                      const dataStr = match[1] + '}'
                      finalResponseData = JSON.parse(dataStr)
                      console.log("✅ Manually extracted final response")
                      this.hideStreamingWindow()
                    }
                  } catch (manualError) {
                    console.log("Manual extraction also failed:", manualError.message)
                  }
                }
              } // end catch
            } // end if line.startsWith
          } // end for line
        } // end for event
        } // End of while loop
      } finally {
        reader.releaseLock()
      }
      
      // Process the final response data
      if (finalResponseData && finalResponseData.message) {
        // Add AI response (streaming window should already be hidden)
        // Only add a new message if we weren't streaming
        if (!this.currentStreamingContent) {
          this.addMessage(finalResponseData.message, "ai")
        } else {
          console.log("✅ Message was streamed, not adding duplicate")
          // Apply markdown formatting to the completed message
          const messages = this.chatMessagesTarget.querySelectorAll('.message')
          const lastMessage = messages[messages.length - 1]
            if (lastMessage && lastMessage.classList.contains('ai-message')) {
              const messageBubble = lastMessage.querySelector('.message-bubble')
              if (messageBubble && this.currentStreamingContent) {
                // Apply final markdown parsing with markdown-it (consistent with streaming)
                messageBubble.innerHTML = this.safeRender(this.currentStreamingContent)
                console.log("✅ Applied final markdown formatting")
                
                // Finalize any remaining TTS content
                this.finalizeStreamingTTS()
              }
            }
        }
        
        // Clear streaming content for next message
        this.currentStreamingContent = undefined
        this.streamingMessageElement = null

        // Render source attribution badges if sources are available
        console.log("🔍 Checking for sources in finalResponseData...")
        console.log("📊 finalResponseData:", finalResponseData)
        if (finalResponseData && finalResponseData.sources && finalResponseData.sources.length > 0) {
          console.log("✅ Found sources! Rendering badges:", finalResponseData.sources)
          this.renderSourceBadges(finalResponseData.sources)
        } else {
          console.log("⚠️ No sources found. finalResponseData.sources:", finalResponseData?.sources)
        }

        // Check if Scout suggested a canvas to load (handle both 'canvas' and 'canvas_type' keys)
        const suggestedCanvas = finalResponseData.canvas || finalResponseData.canvas_type
        const canvasData = finalResponseData.canvas_data || {}
        
        if (suggestedCanvas && suggestedCanvas !== 'conversation') {
          console.log(`🎨 Scout suggested canvas: ${suggestedCanvas}`)
          if (canvasData) {
            console.log("📊 Canvas data:", canvasData)
          }
          
          // Check if we're already on this exact canvas
          const isAlreadyOnCanvas = this.currentCanvas && 
                                   this.currentCanvas.type === suggestedCanvas &&
                                   JSON.stringify(this.currentCanvas.data || {}) === JSON.stringify(canvasData || {})
          
          if (isAlreadyOnCanvas) {
            console.log("✅ Already on the requested canvas, no need to reload")
          } else {
            console.log("🎯 Loading different canvas...")
            setTimeout(() => {
              this.loadScoutCanvas(suggestedCanvas, canvasData)
            }, 1000)
          }
        } else {
          console.log("ℹ️ No canvas suggested in response")
          // Only handle data changes if we have tools that modified data
          if (finalResponseData.tools_used && finalResponseData.tools_used.length > 0) {
            // Check if any tools actually modified data (not just queries)
            const dataModifyingTools = ['create_object', 'update_object', 'delete_object', 'update_landing_page_content']
            const hasDataChanges = finalResponseData.tools_used.some(tool => 
              dataModifyingTools.includes(tool)
            )
            
            if (hasDataChanges) {
              this.handleDataChanges(finalResponseData)
            }
          }
        }
        
        // Check if workflow approval is needed
        if (finalResponseData.workflow_approval) {
          console.log("🔧 Workflow approval needed")
          this.showWorkflowApproval(finalResponseData.workflow_approval)
        }
        
        // Re-enable input after successful response
        this.enableChatInput()
      } else if (this.currentStreamingContent) {
        // Amos response - content was streamed
        console.log("✅ Amos response streamed successfully")
        
        // Apply final markdown formatting if needed
        const messages = this.chatMessagesTarget.querySelectorAll('.message')
        const lastMessage = messages[messages.length - 1]
        if (lastMessage && lastMessage.classList.contains('ai-message')) {
          const messageBubble = lastMessage.querySelector('.message-bubble')
          if (messageBubble && this.currentStreamingContent) {
            messageBubble.innerHTML = this.safeRender(this.currentStreamingContent)
            console.log("✅ Applied final markdown formatting to Amos response")
            
            // Finalize any remaining TTS content
            this.finalizeStreamingTTS()
          }
        }
        
        // Clear streaming content for next message
        this.currentStreamingContent = undefined
        this.streamingMessageElement = null
        
        // Re-enable input after successful response
        this.enableChatInput()
        this.hideStreamingWindow()
      } else {
        // Clean up any orphaned loading dots
        const allLoadingDots = this.chatMessagesTarget.querySelectorAll('.loading-dots')
        allLoadingDots.forEach(dots => {
          console.log("🧹 Removing orphaned loading dots")
          dots.remove()
        })
        // Hide streaming window even if no final response
        this.hideStreamingWindow()
        console.log("📝 No immediate message (agent may be handling the request)")
        // Re-enable input
        this.enableChatInput()
      }
    
    } catch (error) {
      if (error?.name === 'AbortError') {
        console.log("🛑 Chat stream aborted by user")
        return
      }
      console.error("❌ Error sending message:", error)
      this.hideStreamingWindow()
      this.addMessage("Sorry, something went wrong. Please try again.", "ai")
    } finally {
      this.isStreaming = false
      this.currentStreamReader = null
      this.currentChatAbortController = null

      // Re-enable the chat input
      this.enableChatInput()
    }
  }

  // Abort any active streaming response (lets the user interrupt Scout mid-stream).
  interruptStreamingIfNeeded() {
    try {
      if (this.currentStreamReader) {
        try { this.currentStreamReader.cancel() } catch (e) {}
      }
      if (this.currentChatAbortController) {
        try { this.currentChatAbortController.abort() } catch (e) {}
      }
    } catch (e) {}
  }
  
  // Helper to re-enable chat input
  enableChatInput() {
    // Re-enable via DOM elements
    const messageInput = document.getElementById('message-input')
    const sendButton = document.getElementById('send-button')

    if (messageInput) {
      messageInput.disabled = false
      messageInput.focus()
    }
    if (sendButton) {
      sendButton.disabled = false
    }
  }

  // Render source attribution badges below the AI message
  renderSourceBadges(sources) {
    try {
      console.log("🎭 RENDERSOURCEBADGES CALLED!")
      console.log("📊 Rendering source badges:", sources)
      console.log("📊 Sources array length:", sources?.length || 0)

      // Find the last AI message
      const messages = this.chatMessagesTarget.querySelectorAll('.message')
      let lastAiMessage = null
      for (let i = messages.length - 1; i >= 0; i--) {
        if (messages[i].classList.contains('ai-message')) {
          lastAiMessage = messages[i]
          break
        }
      }

      if (!lastAiMessage) {
        console.warn("⚠️ No AI message found to attach source badges")
        return
      }

      // Create source badges container
      const sourcesContainer = document.createElement('div')
      sourcesContainer.className = 'message-sources'

      // Add label with icon
      const labelContainer = document.createElement('span')
      labelContainer.className = 'source-label'
      labelContainer.innerHTML = '<i data-lucide="book-open" class="source-label-icon" aria-hidden="true"></i> Data sources:'
      sourcesContainer.appendChild(labelContainer)

      // Create badges list
      const badgesList = document.createElement('div')
      badgesList.className = 'sources-list'

      // Icon map for different source types
      const iconMap = {
        documents: 'file-text',
        rag: 'book',
        session: 'message-square',
        uploaded: 'upload',
        generated: 'sparkles'
      }

      // Add a badge for each source
      sources.forEach(source => {
        const badge = document.createElement('span')
        badge.className = `source-badge ${source.type}`

        // Get appropriate icon for source type
        const iconName = iconMap[source.type] || 'file'

        // Format the badge text with source name and count
        const sourceLabel = source.type.charAt(0).toUpperCase() + source.type.slice(1)
        const countText = source.count > 1 ? ` (${source.count})` : ''

        // Create badge content with icon and text
        badge.innerHTML = `<i data-lucide="${iconName}" class="source-badge-icon" aria-hidden="true"></i> ${sourceLabel}${countText}`

        badgesList.appendChild(badge)
      })

      sourcesContainer.appendChild(badgesList)

      // Add to the message
      lastAiMessage.appendChild(sourcesContainer)

      // Render lucide icons - need to target the specific container
      if (typeof lucide !== 'undefined') {
        // Use requestAnimationFrame to ensure DOM is updated before creating icons
        requestAnimationFrame(() => {
          lucide.createIcons({ target: sourcesContainer })
        })
      }

      console.log("✅ Source badges rendered successfully with icons")
    } catch (error) {
      console.error("❌ Error rendering source badges:", error)
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

  // Show workflow approval buttons in chat
  showWorkflowApproval(approvalData) {
    const { task_session_id, workflow_spec } = approvalData
    const steps = workflow_spec.steps || []
    
    // Create approval card
    const approvalCard = document.createElement('div')
    approvalCard.className = 'workflow-approval-card bg-white rounded-lg shadow-md p-4 mb-4 border border-gray-200'
    
    // Add workflow summary
    const summaryHtml = `
      <div class="mb-4">
        <h3 class="text-lg font-semibold text-gray-800 mb-2">Workflow Plan</h3>
        <p class="text-sm text-gray-600 mb-3">I'll execute the following ${steps.length} steps:</p>
        <ol class="space-y-2">
          ${steps.map((step, index) => `
            <li class="text-sm text-gray-700">
              <span class="font-medium">${index + 1}.</span> ${step.config?.description || step.id}
            </li>
          `).join('')}
        </ol>
      </div>
      
      <div class="flex gap-3">
        <button class="approve-workflow-btn px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
                data-task-session-id="${task_session_id}">
          <i data-lucide="check" class="mr-2" aria-hidden="true"></i>Approve & Start
        </button>
        <button class="reject-workflow-btn px-4 py-2 bg-gray-300 text-gray-700 rounded-lg hover:bg-gray-400 transition-colors"
                data-task-session-id="${task_session_id}">
          <i data-lucide="x" class="mr-2" aria-hidden="true"></i>Cancel
        </button>
      </div>
    `
    
    approvalCard.innerHTML = summaryHtml
    
    // Add to chat as a special message
    const messageDiv = document.createElement('div')
    messageDiv.className = 'message ai-message mb-4 animate-fade-in'
    messageDiv.appendChild(approvalCard)
    
    this.chatMessagesTarget.appendChild(messageDiv)
    this.scrollToBottom()
    
    // Add event listeners
    approvalCard.querySelector('.approve-workflow-btn').addEventListener('click', (e) => {
      this.approveWorkflow(task_session_id)
      approvalCard.classList.add('opacity-50', 'pointer-events-none')
    })
    
    approvalCard.querySelector('.reject-workflow-btn').addEventListener('click', (e) => {
      this.rejectWorkflow(task_session_id)
      approvalCard.classList.add('opacity-50', 'pointer-events-none')
    })
  }
  
  // Approve workflow
  async approveWorkflow(taskSessionId) {
    try {
      console.log("✅ Approving workflow for task session:", taskSessionId)
      
      // Send approval to backend
      const response = await fetch('/scout/approve_workflow', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          task_session_id: taskSessionId,
          approved: true
        })
      })
      
      if (!response.ok) {
        throw new Error('Failed to approve workflow')
      }
      
      // Add confirmation message
      this.addMessage("Great! I'm starting the workflow now. I'll keep you updated on the progress.", "ai")
      
      // Load task progress canvas
      setTimeout(() => {
        this.loadScoutCanvas('task_progress', { task_session_id: taskSessionId })
      }, 500)
      
    } catch (error) {
      console.error("Error approving workflow:", error)
      this.addMessage("Sorry, there was an error approving the workflow. Please try again.", "ai")
    }
  }
  
  // Reject workflow
  async rejectWorkflow(taskSessionId) {
    try {
      console.log("❌ Rejecting workflow for task session:", taskSessionId)
      
      // Send rejection to backend
      const response = await fetch('/scout/approve_workflow', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          task_session_id: taskSessionId,
          approved: false
        })
      })
      
      if (!response.ok) {
        throw new Error('Failed to reject workflow')
      }
      
      // Add confirmation message
      this.addMessage("No problem! Let me know if you'd like me to try a different approach.", "ai")
      
    } catch (error) {
      console.error("Error rejecting workflow:", error)
      this.addMessage("Sorry, there was an error canceling the workflow.", "ai")
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
      
      // Update toggle button to show X (close mode)
      this.updateCanvasToggleButtons()
      
    } else if (mode === "conversation" && this.currentMode === "work") {
      workspace.classList.remove("work-mode")
      workspace.classList.remove("mobile-canvas-overlay") // Remove mobile overlay if present
      workspace.classList.add("conversation-mode")
      this.currentMode = "conversation"

      // Store current canvas before clearing so we can restore it
      if (this.currentCanvas && this.currentCanvas.type) {
        this.lastClosedCanvas = { ...this.currentCanvas }
      }

      // Clear current canvas reference
      this.currentCanvas = null

      // Save conversation mode state so refresh stays in chat
      this.saveCanvasState()
      console.log("💬 Switched to conversation mode, saved state")
      
      // Reset chat width to full when exiting work mode
      const chatArea = this.element.querySelector('.chat-area')
      if (chatArea) {
        chatArea.style.width = ''
      }
      
      // Reset chat header
      this.updateChatHeader("What can I help you with today?")
      
      // Update toggle button visibility
      this.updateCanvasToggleButtons()
    }
  }

  // Go to conversation mode (pure chat, no canvas) - close current canvas
  goToConversation(event) {
    if (event) this.setActiveNavItem(event)
    console.log("💬 Going to conversation mode (pure chat)")
    
    // Store current canvas before closing so we can restore it
    if (this.currentCanvas && this.currentCanvas.type) {
      this.lastClosedCanvas = { ...this.currentCanvas }
      console.log("💾 Saved last canvas for restoration:", this.lastClosedCanvas.type)
    }
    
    this.switchToMode("conversation")
    
    // Update button visibility
    this.updateCanvasToggleButtons()
  }

  // Load dashboard canvas (default home view)
  loadDashboardCanvas(event) {
    if (event) this.setActiveNavItem(event)
    console.log("🏠 Loading dashboard canvas")
    this.loadScoutCanvas("default", {})
  }

  // Restore the last canvas that was closed
  restoreLastCanvas(event) {
    if (event) event.preventDefault()
    
    if (this.lastClosedCanvas && this.lastClosedCanvas.type) {
      console.log("🔄 Restoring last canvas:", this.lastClosedCanvas.type)
      this.loadScoutCanvas(this.lastClosedCanvas.type, this.lastClosedCanvas.data || {})
    } else {
      // No last canvas, load dashboard instead
      console.log("ℹ️ No last canvas to restore, loading dashboard")
      this.loadScoutCanvas("default", {})
    }
  }

  // Update visibility of canvas toggle buttons
  // Toggle canvas mode - load dashboard when in chat, close canvas when viewing canvas
  toggleCanvasMode(event) {
    if (event) event.preventDefault()
    
    if (this.currentMode === 'conversation') {
      // In chat mode - load dashboard
      console.log("🏠 Loading dashboard from toggle button")
      this.loadScoutCanvas('default', {})
    } else {
      // In work mode - close canvas and go to conversation
      console.log("❌ Closing canvas from toggle button")
      this.goToConversation()
    }
  }

  updateCanvasToggleButtons() {
    // Try target first, then fallback to getElementById
    let toggleBtn = this.hasCanvasToggleBtnTarget ? this.canvasToggleBtnTarget : document.getElementById('canvas-toggle-btn')
    
    if (!toggleBtn) {
      console.log("⚠️ Canvas toggle button not found")
      return
    }
    
    const homeIcon = toggleBtn.querySelector('.toggle-icon-home')
    const closeIcon = toggleBtn.querySelector('.toggle-icon-close')
    
    console.log(`🔄 Updating toggle button - mode: ${this.currentMode}`)
    
    if (this.currentMode === 'conversation') {
      // In conversation mode - show home icon, clicking loads dashboard
      if (homeIcon) homeIcon.style.display = ''
      if (closeIcon) closeIcon.style.display = 'none'
      toggleBtn.title = 'Dashboard'
      toggleBtn.classList.remove('close-mode')
      toggleBtn.classList.add('home-mode')
    } else {
      // In work mode - show X icon, clicking closes canvas
      if (homeIcon) homeIcon.style.display = 'none'
      if (closeIcon) closeIcon.style.display = ''
      toggleBtn.title = 'Close canvas'
      toggleBtn.classList.remove('home-mode')
      toggleBtn.classList.add('close-mode')
    }
    
    // Re-render lucide icons for the visible one
    if (typeof lucide !== 'undefined') {
      lucide.createIcons()
    }
  }

  // Helper to update active nav item
  // DISABLED: Nav highlighting removed in chat mode because Amos constantly 
  // renders canvases that don't map to nav items, making highlighting confusing
  setActiveNavItem(event) {
    // Only handle mobile sidebar collapse, no active state changes
    if (this.isMobileViewport() && this.hasSideNavTarget) {
      this.sideNavTarget.classList.remove('expanded')
    }
  }

  // Nav handler methods
  loadLandingPagesCanvas(event) {
    this.setActiveNavItem(event)
    console.log("🌐 Loading landing pages canvas")
    this.loadScoutCanvas("landing_page_viewer", {})
  }

  loadCampaignsCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📧 Loading campaigns canvas")
    this.loadScoutCanvas("campaign_viewer", {})
  }

  loadEmailTemplatesCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📄 Loading email templates canvas")
    this.loadScoutCanvas("email_template_viewer", {})
  }

  loadAnalyticsCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📊 Loading analytics canvas")
    this.loadScoutCanvas("analytics_dashboard", {})
  }

  loadIntegrationsCanvas(event) {
    this.setActiveNavItem(event)
    console.log("🔌 Loading integrations canvas")
    this.loadScoutCanvas("integrations_manager", {})
  }

  loadAgentMarketplaceCanvas(event) {
    this.setActiveNavItem(event)
    console.log("🏪 Loading agent marketplace canvas")
    this.loadScoutCanvas("agent_marketplace", {})
  }

  loadModuleManagerCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📦 Loading module manager canvas")
    this.loadScoutCanvas("module_manager", {})
  }

  loadAppsCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📱 Loading app store canvas")
    this.loadScoutCanvas("module_marketplace", {})
  }

  loadInstalledAppsCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📦 Loading installed apps canvas")
    this.loadScoutCanvas("module_manager", {})
  }

  loadPipelineCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📊 Loading pipeline canvas")
    this.loadScoutCanvas("pipeline_viewer", {})
  }

  loadAppDesignerCanvas(event) {
    this.setActiveNavItem(event)
    console.log("🎨 Loading app designer canvas")
    this.loadScoutCanvas("app_designer", {})
  }

  loadSavedVisualizationsCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📊 Loading saved visualizations canvas")
    this.loadScoutCanvas("saved_visualizations", {})
  }

  loadModuleMarketplaceCanvas(event) {
    this.setActiveNavItem(event)
    console.log("🛒 Loading module marketplace canvas")
    this.loadScoutCanvas("module_marketplace", {})
  }

  loadDocumentViewerCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📄 Loading document viewer canvas")
    this.loadScoutCanvas("document_viewer", {})
  }

  loadContactsCanvas(event) {
    this.setActiveNavItem(event)
    console.log("👥 Loading contacts canvas")
    this.loadScoutCanvas("contact_viewer", {})
  }
  
  loadParallelTasksCanvas(event) {
    this.setActiveNavItem(event)
    console.log("🔄 Loading parallel tasks canvas")
    const sessionId = document.querySelector('[data-scout-session-id]')?.dataset.scoutSessionId ||
                      this.chatMessagesTarget?.dataset.sessionId ||
                      'current_session'
    this.loadScoutCanvas("parallel_tasks", { session_id: sessionId })
  }

  loadScheduledTasksCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📅 Loading scheduled tasks canvas")
    const sessionId = document.querySelector('[data-scout-session-id]')?.dataset.scoutSessionId ||
                      this.chatMessagesTarget?.dataset.sessionId ||
                      'current_session'
    this.loadScoutCanvas("scheduled_tasks", { session_id: sessionId })
  }

  loadWorkInboxCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📥 Loading work inbox canvas")
    this.loadScoutCanvas("work_inbox", {})
  }

  loadOperationsDashboardCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📊 Loading operations dashboard canvas")
    this.loadScoutCanvas("operations_dashboard", {})
  }

  // Personal Space canvas loaders
  loadNotesCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📝 Loading notes canvas")
    this.loadScoutCanvas("notes", {})
  }

  loadBookmarksCanvas(event) {
    this.setActiveNavItem(event)
    console.log("🔖 Loading bookmarks canvas")
    this.loadScoutCanvas("bookmarks", {})
  }

  loadRemindersCanvas(event) {
    this.setActiveNavItem(event)
    console.log("🔔 Loading reminders canvas")
    this.loadScoutCanvas("reminders", {})
  }

  loadChannelsCanvas(event) {
    this.setActiveNavItem(event)
    console.log("📢 Loading channels canvas")
    this.loadScoutCanvas("channels", {})
  }

  loadScheduledTaskEditorCanvas(taskId = null) {
    console.log("📝 Loading scheduled task editor canvas, taskId:", taskId)
    this.loadScoutCanvas("scheduled_task_editor", { task_id: taskId })
  }

  // Profile and settings methods
  openSettings(event) {
    this.setActiveNavItem(event)
    console.log("⚙️ Opening business settings")
    // Load business profile canvas instead of redirecting
    this.loadScoutCanvas("business_profile", {})
  }

  openProfile(event) {
    this.setActiveNavItem(event)
    console.log("👤 Opening user profile")
    // Load user profile canvas instead of redirecting
    this.loadScoutCanvas("user_profile", {})
  }

  openVoiceSettings(event) {
    this.setActiveNavItem(event)
    try {
      console.log("🎤 Opening voice settings")

      // Load user profile canvas and scroll to voice settings
      this.loadScoutCanvas("user_profile", {})

      // Mark that we should scroll to voice settings after load
      this.scrollToVoiceSettingsOnLoad = true

      console.log("✅ Voice settings load initiated successfully")
    } catch (error) {
      console.error("❌ Error opening voice settings:", error)
      window.showError("Error opening voice settings: " + error.message)
    }
  }

  async logout() {
    console.log("🚪 Logging out")
    const confirmed = await window.showConfirm('Are you sure you want to logout?', {
      title: 'Logout',
      confirmText: 'Logout',
      cancelText: 'Cancel'
    })

    if (confirmed) {
      // SECURITY: Clear all user-specific localStorage to prevent cross-user data leakage
      this.clearAllCanvasStates()
      
      // Also clear any other user-specific cached data
      try {
        // Clear all scout-related localStorage keys
        const keysToRemove = []
        for (let i = 0; i < localStorage.length; i++) {
          const key = localStorage.key(i)
          if (key && (key.startsWith('scout_') || key.startsWith('amos_') || key.startsWith('hub_'))) {
            keysToRemove.push(key)
          }
        }
        keysToRemove.forEach(key => localStorage.removeItem(key))
        console.log(`🗑️ Cleared ${keysToRemove.length} user-specific localStorage items`)
      } catch (e) {
        console.warn("Could not clear localStorage:", e)
      }
      
      // Create a form and submit it with DELETE method (required by Devise)
      const form = document.createElement('form')
      form.method = 'POST'
      form.action = '/users/sign_out'

      // Add CSRF token
      const csrfToken = this.getCSRFToken()
      if (csrfToken) {
        const csrfInput = document.createElement('input')
        csrfInput.type = 'hidden'
        csrfInput.name = 'authenticity_token'
        csrfInput.value = csrfToken
        form.appendChild(csrfInput)
      }

      // Add method override for DELETE
      const methodInput = document.createElement('input')
      methodInput.type = 'hidden'
      methodInput.name = '_method'
      methodInput.value = 'delete'
      form.appendChild(methodInput)

      // Submit the form
      document.body.appendChild(form)
      form.submit()
    }
  }

  // Close current template
  closeTemplate() {
    // Remove mobile overlay class if present
    this.element.classList.remove('mobile-canvas-overlay')
    
    // Switch back to conversation mode
    this.switchToMode("conversation")
    
    // Save conversation mode so refresh stays in chat
    this.saveCanvasState()
    this.addMessage("Canvas closed. What else can I help you with?", "ai")
  }

  // ========== SCOUT CANVAS FUNCTIONALITY ==========

  // Load a Scout canvas
  async loadScoutCanvas(canvasType, canvasData = {}, forceRefresh = false) {
    try {
      // Don't load canvas in Team Space mode - Hub handles its own UI
      if (this.inTeamSpace) {
        console.log("🌐 Canvas disabled in Team Space mode")
        return
      }
      
      console.log(`🎨 Loading Scout canvas: ${canvasType}`)
      console.log(`📦 Canvas data:`, canvasData)
      console.log(`🔄 Force refresh:`, forceRefresh)

      // If canvasType is null, undefined, or empty, don't change the canvas
      if (!canvasType || canvasType === null || canvasType === '') {
        console.log("⚠️ Canvas type is empty/null, keeping current canvas")
        return
      }
      
      // Check if we're already on this exact canvas (skip check if forceRefresh is true)
      if (!forceRefresh && this.currentCanvas && 
          this.currentCanvas.type === canvasType && 
          JSON.stringify(this.currentCanvas.data || {}) === JSON.stringify(canvasData || {})) {
        console.log("✅ Already on this canvas, skipping reload")
        return
      }
      
      // Check if wizard is waiting for completion
      if (window.landingPageWizard?.waitingForCompletion && canvasType === 'landing_page_viewer') {
        console.log('🎯 Landing page creation completed - wizard detected canvas change')
        window.landingPageWizard.waitingForCompletion = false;
        // The wizard step 3 will be replaced when the new canvas loads
        
        // Trigger auto-refresh for newly created page after canvas loads
        setTimeout(() => {
          console.log('🔄 Triggering auto-refresh for newly created landing page');
          if (window.initLandingPageAutoRefresh) {
            window.initLandingPageAutoRefresh();
          }
        }, 1500); // Give canvas time to load content
      }
      
      this.showCanvasLoading(canvasType)

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
        
        // On mobile, show canvas as overlay; on desktop, use split work mode
        if (this.isMobileViewport()) {
          console.log("📱 Mobile viewport detected - showing canvas as overlay")
          this.element.classList.add('mobile-canvas-overlay')
          this.element.classList.remove('conversation-mode')
          this.element.classList.add('work-mode')
          this.currentMode = 'work'
        } else {
          console.log("🖥️ Desktop viewport - switching to work mode")
          this.switchToMode("work")
        }
        
        // Update canvas area
        console.log("📝 Updating canvas content")
        console.log("🎯 Setting title to:", data.canvas.title)
        this.templateTitleTarget.textContent = data.canvas.title
        console.log("🎯 Setting content HTML (length:", data.canvas.content.length, ")")
        this.templateContentTarget.innerHTML = data.canvas.content

        // Execute any inline <script> tags from the injected canvas content
        this.executeInlineScripts(this.templateContentTarget)

        // Re-initialize Lucide icons for dynamically loaded canvas content
        if (typeof lucide !== 'undefined') {
          lucide.createIcons()
        }
        
        // Check if we need to scroll to voice settings
        if (this.scrollToVoiceSettingsOnLoad && canvasType === 'user_profile') {
          this.scrollToVoiceSettingsOnLoad = false
          setTimeout(() => {
            const voiceSettingsCard = document.querySelector('[data-controller="voice-settings"]')?.closest('.card')
            if (voiceSettingsCard) {
              voiceSettingsCard.scrollIntoView({ behavior: 'smooth', block: 'start' })
              // Add a highlight effect
              voiceSettingsCard.style.boxShadow = '0 0 0 3px rgba(124, 58, 237, 0.5)'
              setTimeout(() => {
                voiceSettingsCard.style.transition = 'box-shadow 0.5s ease'
                voiceSettingsCard.style.boxShadow = ''
              }, 2000)
            }
          }, 500)
        }

        // Store current canvas info
        this.currentCanvas = {
          type: canvasType,
          data: canvasData,
          title: data.canvas.title
        }
        console.log("💾 Stored current canvas:", this.currentCanvas)

        // Save canvas state for persistence
        this.saveCanvasState()

        // Set up global canvas functions for the loaded content
        console.log("⚙️ Setting up canvas globals")
        this.setupCanvasGlobals()

        console.log(`✅ Canvas loaded successfully: ${data.canvas.title}`)
        
        // Dispatch event so other components can track canvas changes
        window.dispatchEvent(new CustomEvent('canvas-loaded', {
          detail: {
            type: canvasType,
            data: canvasData,
            title: data.canvas.title
          }
        }))
        
        // Show/hide close button based on canvas type (hide for default/dashboard)
        this.updateCanvasCloseButton(canvasType)
        
        // No need for confirmation message - canvas loading is visually obvious
        
      } else {
        console.error("❌ Failed to load canvas:", data.error)
        this.addMessage(`Sorry, I couldn't load that view: ${data.error}`, "ai")
      }

    } catch (error) {
      console.error("❌ Canvas loading error:", error)
      this.addMessage("Sorry, I couldn't load that view. Please try again.", "ai")
    } finally {
      console.log("🔄 Hiding loading overlay")
      this.hideCanvasLoading()
    }
  }

  // Update canvas toggle button based on canvas type and mode
  updateCanvasCloseButton(canvasType) {
    // Update the toggle button state
    this.updateCanvasToggleButtons()
  }

  // Set up global functions that canvas content can call
  setupCanvasGlobals() {
    // Make functions available globally for canvas content
    window.scoutSendMessage = (message) => {
      this.sendScoutMessage(message)
    }

    window.scoutLoadCanvas = (canvasType, canvasData = {}, forceRefresh = false) => {
      this.loadScoutCanvas(canvasType, canvasData, forceRefresh)
    }
    
    // SECURITY: Global function to clear user-specific localStorage on logout
    // Called from logout buttons in other layouts (customer_admin, etc.)
    window.clearScoutLocalStorage = () => {
      console.log("🗑️ Clearing scout localStorage on logout...")
      try {
        const keysToRemove = []
        for (let i = 0; i < localStorage.length; i++) {
          const key = localStorage.key(i)
          if (key && (key.startsWith('scout_') || key.startsWith('amos_') || key.startsWith('hub_'))) {
            keysToRemove.push(key)
          }
        }
        keysToRemove.forEach(key => localStorage.removeItem(key))
        console.log(`🗑️ Cleared ${keysToRemove.length} scout localStorage items`)
      } catch (e) {
        console.warn("Could not clear localStorage:", e)
      }
    }

    // Hybrid login helpers (used by browser canvases)
    // These need to exist globally because the interactive proxy login happens in the
    // `web_page_viewer` canvas, not the `browser_session` canvas.
    window.requestBrowserSessionSyncLogin = window.requestBrowserSessionSyncLogin || ((proxySessionId, proxyHost, currentUrl = "") => {
      const host = (proxyHost || "").trim()
      const psid = (typeof proxySessionId === "string") ? proxySessionId : String(proxySessionId || "")
      if (!host || !psid) return

      // Try to derive the upstream URL from the interactive proxy iframe (best effort).
      const deriveUpstreamUrlFromProxyFrame = () => {
        const frame =
          document.querySelector(".web-page-viewer iframe.wpv-interactive-frame") ||
          document.querySelector(".web-page-viewer [data-web-page-viewer-target='proxyFrame']")
        if (!frame) return ""

        // First, try to get the original URL from our injected globals (set by intercept script)
        try {
          const proxyOriginalUrl = frame.contentWindow?.__PROXY_ORIGINAL_URL__
          if (proxyOriginalUrl) {
            console.log("[HybridLogin] Got original URL from __PROXY_ORIGINAL_URL__:", proxyOriginalUrl)
            return proxyOriginalUrl
          }
          
          // Also check history.state which we set during replaceState
          const stateOriginalUrl = frame.contentWindow?.history?.state?.originalUrl
          if (stateOriginalUrl) {
            console.log("[HybridLogin] Got original URL from history.state:", stateOriginalUrl)
            return stateOriginalUrl
          }
        } catch (e) {
          // Cross-origin or other error, continue to fallback
        }

        let href = ""
        try {
          // Same-origin in our proxy iframe, so this often works.
          href = frame.contentWindow?.location?.href || ""
        } catch (e) {
          // Ignore; fall back to src.
        }
        if (!href) href = frame.getAttribute("src") || ""
        if (!href) return ""

        try {
          const u = new URL(href, window.location.origin)
          // Check for url param (old proxy URL structure)
          const upstream = u.searchParams.get("url") || ""
          if (upstream) return upstream
          
          // If no url param, the iframe might be using replaceState'd path
          // In this case, we need to reconstruct from host + pathname
          // But we need the original host - check sessionStorage
          const storedBaseUrl = frame.contentWindow?.sessionStorage?.getItem?.('__proxy_base_url__')
          if (storedBaseUrl) {
            const baseUrlObj = new URL(storedBaseUrl)
            const fullUrl = baseUrlObj.origin + u.pathname + u.search + u.hash
            console.log("[HybridLogin] Reconstructed URL from sessionStorage:", fullUrl)
            return fullUrl
          }
          
          return ""
        } catch (e) {
          return ""
        }
      }

      // Fallback: if we have a browser_session canvas loaded, use its dataset URL.
      const deriveCurrentUrlFromBrowserSessionCanvas = () => {
        const container = document.querySelector(".browser-session")
        const ds = container?.dataset || {}
        return (ds.browserSessionUrlValue || "").toString()
      }

      const resolvedCurrentUrl =
        (currentUrl || "").trim() ||
        deriveUpstreamUrlFromProxyFrame() ||
        deriveCurrentUrlFromBrowserSessionCanvas()

      const csrfToken =
        window.Rails?.csrfToken ||
        document.querySelector("meta[name='csrf-token']")?.getAttribute("content") ||
        document.querySelector("[name='csrf-token']")?.value ||
        document.querySelector("[name='authenticity_token']")?.value ||
        ""

      fetch("/scout/browser_session_sync_proxy", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        body: JSON.stringify({
          session_id: psid,
          proxy_session_id: psid,
          proxy_host: host,
          current_url: resolvedCurrentUrl
        })
      })
        .then(async (resp) => {
          const data = await resp.json().catch(() => ({}))
          if (!resp.ok || !data.success) {
            const msg = data.error || "Failed to sync login session"
            console.warn("[HybridLogin] Sync proxy session failed:", msg)
            alert(msg)
            return
          }
          console.log("[HybridLogin] Sync proxy session success")

          // Ensure we switch back to the agent browser canvas even if ActionCable is flaky.
          window.scoutLoadCanvas?.("browser_session", { session_id: psid }, true)
        })
        .catch((err) => {
          console.warn("[HybridLogin] Sync proxy session request failed:", err)
          alert("Failed to sync login session")
        })
    })

    window.requestBrowserSessionTakeOver = window.requestBrowserSessionTakeOver || ((sessionId) => {
      const sid = (typeof sessionId === "string") ? sessionId : String(sessionId || "")
      if (!sid) return

      const csrfToken =
        window.Rails?.csrfToken ||
        document.querySelector("meta[name='csrf-token']")?.getAttribute("content") ||
        document.querySelector("[name='csrf-token']")?.value ||
        document.querySelector("[name='authenticity_token']")?.value ||
        ""

      fetch("/scout/browser_session_close", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        body: JSON.stringify({ session_id: sid })
      }).catch(() => {})
    })

    window.scoutRefreshCanvas = () => {
      if (this.currentCanvas) {
        this.loadScoutCanvas(this.currentCanvas.type, this.currentCanvas.data)
      }
    }

    // Set up user profile form handling
    this.setupUserProfileForm()
    
    // Set up business profile form handling
    this.setupBusinessProfileForms()

    // Canvas-specific functions
    window.scoutSwitchView = (view) => {
      const editorView = document.getElementById('editorView');
      const previewView = document.getElementById('previewView');
      const buttons = document.querySelectorAll('.btn-group button');
      
      if (!editorView || !previewView) return;
      
      buttons.forEach(btn => btn.classList.remove('active'));
      
      if (view === 'editor') {
        editorView.classList.remove('d-none');
        previewView.classList.add('d-none');
        buttons[0]?.classList.add('active');
      } else {
        editorView.classList.add('d-none');
        previewView.classList.remove('d-none');
        buttons[1]?.classList.add('active');
        // Trigger preview refresh if function exists
        if (window.scoutRefreshPreview) {
          window.scoutRefreshPreview();
        }
      }
    }

    window.scoutRefreshPreview = () => {
      // Canvas preview refresh functionality
      const previewFrame = document.getElementById('previewFrame');
      if (previewFrame) {
        previewFrame.src = previewFrame.src; // Force refresh
      }
    }

    // Quick action functions for default canvas
    window.scoutQuickAction = (action) => {
      const actionMap = {
        'landing_pages': 'landing_page_viewer',
        'contacts': 'contact_viewer', 
        'campaigns': 'campaign_viewer',
        'analytics': 'analytics_dashboard'
      }
      if (actionMap[action]) {
        this.loadScoutCanvas(actionMap[action], {})
      }
    }

    window.scoutSendExample = (message) => {
      this.sendScoutMessage(message)
    }
    
    // Make sendMessage available globally for canvas interactions
    window.scoutSendMessage = (message) => {
      this.sendScoutMessage(message)
    }
    
    // Listen for custom scout:send-message events from canvases
    window.addEventListener('scout:send-message', (event) => {
      console.log('📨 Received scout:send-message event:', event.detail)
      if (event.detail && event.detail.message) {
        this.sendScoutMessage(event.detail.message)
      }
    })

    // Navigation functions
    window.scoutBackToLandingPages = () => this.loadScoutCanvas('landing_page_viewer', {})
    window.scoutBackToContacts = () => this.loadScoutCanvas('contact_viewer', {})

    // Create functions
    window.scoutCreateContact = () => this.sendScoutMessage("Please help me create a new contact")
    window.scoutCreateCampaign = () => this.sendScoutMessage("Please help me create a new email campaign")  
    // Create functions - use interactive workflow via chat
    window.scoutCreateLandingPage = () => this.sendScoutMessage('Create a landing page')

    // Edit functions
    window.scoutEditContact = (id) => this.sendScoutMessage(`Please help me edit contact ID ${id}`)
    window.scoutEditCampaign = (id) => this.sendScoutMessage(`Please help me edit campaign ID ${id}`)
    // Edit landing page - use interactive workflow via chat
    window.scoutEditLandingPage = (id) => this.sendScoutMessage(`Please help me edit landing page ID ${id}`)

    // View functions  
    window.scoutViewContact = (id) => this.sendScoutMessage(`Please show me details for contact ID ${id}`)
    window.scoutViewCampaign = (id) => this.sendScoutMessage(`Please show me campaign ID ${id} details`)
    window.scoutViewLandingPage = (id) => this.loadScoutCanvas('landing_page_details', { landing_page_id: id })
    window.scoutPreviewLandingPageInTab = (id) => window.open(`/landing_pages/${id}/preview`, '_blank', 'noopener,noreferrer')
    
    // Landing page preview toggle functions
    window.switchToVisualMode = () => {
      console.log('Switching to visual mode');
      const visualPreview = document.getElementById('visual-preview');
      const htmlPreview = document.getElementById('html-preview');
      const visualBtn = document.getElementById('visual-mode-btn');
      const htmlBtn = document.getElementById('html-mode-btn');
      
      if (visualPreview && htmlPreview && visualBtn && htmlBtn) {
        // Show visual, hide HTML
        visualPreview.classList.remove('d-none');
        htmlPreview.classList.add('d-none');
        
        // Update button states
        visualBtn.classList.remove('btn-outline-primary');
        visualBtn.classList.add('btn-primary');
        htmlBtn.classList.remove('btn-primary');
        htmlBtn.classList.add('btn-outline-primary');
      }
    }
    
    window.switchToHtmlMode = () => {
      console.log('Switching to HTML mode');
      const visualPreview = document.getElementById('visual-preview');
      const htmlPreview = document.getElementById('html-preview');
      const visualBtn = document.getElementById('visual-mode-btn');
      const htmlBtn = document.getElementById('html-mode-btn');
      
      if (visualPreview && htmlPreview && visualBtn && htmlBtn) {
        // Show HTML, hide visual
        htmlPreview.classList.remove('d-none');
        visualPreview.classList.add('d-none');
        
        // Update button states
        htmlBtn.classList.remove('btn-outline-primary');
        htmlBtn.classList.add('btn-primary');
        visualBtn.classList.remove('btn-primary');
        visualBtn.classList.add('btn-outline-primary');
      }
    }
    
    window.saveHtmlChanges = (landingPageId) => {
      console.log('saveHtmlChanges called for landing page:', landingPageId);
      const htmlEditor = document.getElementById('html-editor');

      if (!htmlEditor) {
        console.error('HTML editor not found');
        window.showError('HTML editor not found');
        return;
      }

      const htmlContent = htmlEditor.value;
      console.log('HTML content length:', htmlContent.length);

      if (!htmlContent.trim()) {
        window.showWarning('HTML content cannot be empty');
        return;
      }
      
      // Show saving indicator
      const saveBtn = event.target;
      const originalText = saveBtn.innerHTML;
      saveBtn.innerHTML = '<i data-lucide="loader-circle" class="me-1 icon-spin" aria-hidden="true"></i> Saving...';
      saveBtn.disabled = true;

      // Re-initialize Lucide icons
      if (typeof lucide !== 'undefined') {
        lucide.createIcons()
      }
      
      console.log('Sending PATCH request to update landing page...');
      
      // Get CSRF token safely - try Rails global first, then fallback to meta tags
      let csrfToken = window.Rails?.csrfToken ||
                      document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ||
                      document.querySelector('[name="csrf-token"]')?.value ||
                      document.querySelector('[name="authenticity_token"]')?.value;
      
      if (!csrfToken) {
        console.error('CSRF token not found');
        window.showError('Security token not found. Please refresh the page and try again.');
        saveBtn.innerHTML = originalText;
        saveBtn.disabled = false;
        return;
      }
      
      console.log('CSRF token found and ready for request');
      
      // Send PATCH request to update landing page
      fetch(`/landing_pages/${landingPageId}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({
          landing_page: {
            html_content: htmlContent
          }
        })
      })
      .then(response => response.json())
      .then(data => {
        if (data.success) {
          saveBtn.innerHTML = '<i data-lucide="check" class="me-1" aria-hidden="true"></i> Saved!';
          saveBtn.classList.remove('btn-success');
          saveBtn.classList.add('btn-success');

          // Re-initialize Lucide icons
          if (typeof lucide !== 'undefined') {
            lucide.createIcons()
          }
          
          // Refresh visual preview if visible
          const visualPreview = document.getElementById('visual-preview');
          if (visualPreview && !visualPreview.classList.contains('d-none')) {
            const iframe = visualPreview.querySelector('iframe');
            if (iframe) {
              iframe.src = iframe.src; // Reload iframe
            }
          }
          
          setTimeout(() => {
            saveBtn.innerHTML = originalText;
            saveBtn.classList.remove('btn-success');
            saveBtn.classList.add('btn-success');
            saveBtn.disabled = false;
          }, 2000);
        } else {
          throw new Error(data.error || 'Failed to save');
        }
      })
      .catch(error => {
        console.error('Save error:', error);
        saveBtn.innerHTML = '<i data-lucide="alert-triangle" class="me-1" aria-hidden="true"></i> Error';
        saveBtn.classList.add('btn-danger');

        // Re-initialize Lucide icons
        if (typeof lucide !== 'undefined') {
          lucide.createIcons()
        }
        
        setTimeout(() => {
          saveBtn.innerHTML = originalText;
          saveBtn.classList.remove('btn-danger');
          saveBtn.disabled = false;
        }, 3000);
      });
    }
    
    // Landing page management functions
    window.scoutPublishLandingPage = async (id) => {
      const confirmed = await window.showConfirm('Are you sure you want to publish this landing page?', {
        title: 'Publish Landing Page',
        confirmText: 'Publish',
        confirmClass: 'btn-success'
      })
      if (confirmed) {
        this.sendScoutMessage(`Please publish landing page ID ${id}`)
      }
    }
    window.scoutUnpublishLandingPage = async (id) => {
      const confirmed = await window.showConfirm('Are you sure you want to unpublish this landing page?', {
        title: 'Unpublish Landing Page',
        confirmText: 'Unpublish',
        confirmClass: 'btn-warning'
      })
      if (confirmed) {
        this.sendScoutMessage(`Please unpublish landing page ID ${id}`)
      }
    }

    // Delete functions
    window.scoutDeleteContact = async (id) => {
      const confirmed = await window.showConfirm('Are you sure you want to delete this contact? This action cannot be undone.', {
        title: 'Delete Contact',
        confirmText: 'Delete',
        dangerous: true
      })
      if (confirmed) {
        this.sendScoutMessage(`Please delete contact ID ${id}`)
      }
    }
    window.scoutDeleteCampaign = async (id) => {
      const confirmed = await window.showConfirm('Are you sure you want to delete this campaign? This action cannot be undone.', {
        title: 'Delete Campaign',
        confirmText: 'Delete',
        dangerous: true
      })
      if (confirmed) {
        this.sendScoutMessage(`Please delete campaign ID ${id}`)
      }
    }
    window.scoutDeleteLandingPage = async (id) => {
      const confirmed = await window.showConfirm('Are you sure you want to delete this landing page? This action cannot be undone.', {
        title: 'Delete Landing Page',
        confirmText: 'Delete',
        dangerous: true
      })
      if (confirmed) {
        this.sendScoutMessage(`Please delete landing page ID ${id}`)
      }
    }

    // Import/Export functions
    // Note: scoutImportContacts is now defined locally in contact_viewer canvas to open modal
    window.scoutExportContacts = () => this.sendScoutMessage("Please export my contacts")
    window.scoutExportCampaigns = () => this.sendScoutMessage("Please export my campaigns")

    // Analysis functions
    window.scoutAnalyzeCampaign = (id) => this.sendScoutMessage(`Please analyze campaign ID ${id}`)
    window.scoutAnalyzeCampaigns = () => this.sendScoutMessage("Please analyze all my campaigns")

    // Chart/View functions
    window.scoutChangeChart = (chartType) => {
      // Simple chart switching for analytics
      const buttons = document.querySelectorAll('[onclick*="scoutChangeChart"]')
      buttons.forEach(btn => btn.classList.remove('active'))
      event?.target?.classList.add('active')
    }

    // Template and form functions
    window.scoutAddFormTemplate = (template) => this.sendScoutMessage(`Please add ${template} form template`)
    window.scoutSaveLandingPage = () => this.sendScoutMessage("Please save this landing page")
    window.scoutGenerateContent = () => this.sendScoutMessage("Please generate content for this landing page")

    // Contact management functions
    window.scoutSaveContact = () => this.sendScoutMessage("Please save this contact")
    window.scoutSaveAndAdd = () => this.sendScoutMessage("Please save this contact and add another")
    window.scoutClearForm = () => {
      const form = document.querySelector('form')
      if (form) form.reset()
    }

    // Utility functions
    window.scoutValidateEmail = () => this.sendScoutMessage("Please validate this email address")
    window.scoutFindSocial = () => this.sendScoutMessage("Please find social media profiles for this contact")
    window.scoutCheckDuplicates = () => this.sendScoutMessage("Please check for duplicate contacts")

    // Load more functions
    window.scoutLoadMoreContacts = () => this.sendScoutMessage("Please load more contacts")

    // ===== AMOS INTEGRATION FUNCTIONS =====
    // Handle Amos responses from ActionCable
    window.streamAmosResponse = (data) => {
      console.log("📨 streamAmosResponse called:", {
        contentLength: data.content?.length,
        metadata: data.metadata,
        hasStreaming: data.metadata?.streaming,
        hasComplete: data.metadata?.complete,
        fromAgent: data.metadata?.from_agent,
        alreadySaved: data.metadata?.already_saved
      })
      
      // Check if this is a streaming message
      if (data.metadata && data.metadata.streaming) {
        // This is handled by SSE already, just log it
        console.log("⏩ Streaming chunk via ActionCable - SSE handles display, skipping")
      } else if (data.metadata && data.metadata.complete && !data.metadata.from_agent && !data.metadata.awaiting_response) {
        // This is the complete message after streaming - already displayed via SSE
        // BUT: Agent messages should still be displayed even if marked complete
        // NOTE: Do NOT clear streaming state here - SSE might still be streaming!
        console.log("⏩ Complete message marker - SSE handles display, not clearing streaming state")
      } else if (data.content && data.content.trim() && !data.metadata?.already_saved) {
        // This is a standalone agent message, not part of streaming
        // Remove any loading dots first
        const loadingElements = this.chatMessagesTarget.querySelectorAll('.loading-dots')
        loadingElements.forEach(el => el.remove())
        
        console.log("🤖 Displaying agent message:", data.content)
        this.addMessage(data.content, 'ai')
        
        // Handle TTS for voice mode
        const voiceModeToggle = document.getElementById('voice-toggle-checkbox')
        if (voiceModeToggle?.checked) {
          console.log("🎤 Voice mode is enabled, speaking agent message")
          this.speakText(data.content)
        }
        
        // Check if this message is awaiting user response
        if (data.metadata && data.metadata.awaiting_response) {
          console.log("🔓 Agent is awaiting response - unlocking chat input")
          
          // For voice mode, ensure we speak the question
          const shouldSpeakQuestion = voiceModeToggle?.checked && (
            data.metadata.voice_priority || 
            data.metadata.from_agent ||
            data.content.includes('?')  // Fallback: questions often contain ?
          )
          
          if (shouldSpeakQuestion) {
            console.log("🎤 Agent question detected, ensuring TTS playback")
            // Small delay to ensure previous TTS is complete
            setTimeout(() => {
              if (window.ttsManager && window.ttsManager.isEnabled) {
                if (!window.ttsManager.isPlaying) {
                  console.log("🔊 Speaking agent question to user")
                  this.speakText(data.content)
                } else {
                  console.log("⏸️ TTS is playing, queuing agent question")
                  // TTS manager should queue it automatically
                  this.speakText(data.content)
                }
              } else if (voiceModeToggle?.checked) {
                // Fallback if TTS manager isn't ready
                console.log("🔊 TTS manager not ready, using direct speak")
                this.speakText(data.content)
              }
            }, 200)
          }
          
          // Re-enable chat input since agent is waiting for user response
          const messageInput = this.messageInputTarget || document.getElementById('message-input')
          const sendButton = this.sendButtonTarget || document.getElementById('send-button')
          
          if (messageInput) {
            messageInput.disabled = false
            messageInput.focus()
          }
          if (sendButton) {
            sendButton.disabled = false
          }
        }
      }
    }

    // Stream task content (used by both legacy and Amos)
    window.streamTaskContent = (data) => {
      console.log("📝 Streaming task content:", data.content)
      if (data.content && data.type === 'assistant') {
        // If we have the controller instance, add the message
        if (window.scoutController) {
          // We assume ActionCable messages are for async events (like agent questions) 
          // that aren't covered by the main SSE stream
          window.scoutController.addMessage(data.content, "ai")
          console.log("✅ Displayed task content in Scout chat")
        } else {
          console.warn("⚠️ scoutController not available to display task content")
        }
      }
    }

    // Handle job status updates from Amos
    window.handleJobStatus = (data) => {
      console.log("📊 Job status update:", data)
      // Could update a job status panel here if needed
    }

    // Handle input requests from Amos agents
    window.handleAmosInputRequest = (data) => {
      console.log("❓ Amos agent requesting input:", data)

      // Display the question in Scout's chat as an AI message
      if (data.prompt && window.scoutController) {
        // Strip out agent communication tags if present (format: [AGENT: name][JOB_ID: id][STATUS: status][REQUEST_TYPE: type] content)
        const cleanPrompt = data.prompt.replace(/\[AGENT:.*?\]\[JOB_ID:.*?\]\[STATUS:.*?\]\[REQUEST_TYPE:.*?\]\s*/, '')

        window.scoutController.addMessage(cleanPrompt, "ai")
        console.log("✅ Displayed agent question in Scout chat")
      } else {
        console.warn("⚠️ No prompt or scoutController available for input request")
      }
    }
    
    // Handle parallel task updates
    window.handleParallelTaskUpdate = (data) => {
      console.log("📈 Task update:", data)
      
      // Check if the parallel tasks canvas has the new handleCanvasUpdate function
      if (window.handleCanvasUpdate && typeof window.handleCanvasUpdate === 'function') {
        console.log("✅ Delegating to new canvas update handler")
        window.handleCanvasUpdate(data)
        return
      }
      
      // Fallback: Find any task monitor canvas
      const taskMonitor = document.querySelector('[data-canvas-type="parallel_tasks"]')
      if (!taskMonitor) {
        console.log("No task monitor canvas found")
        return
      }
      
      // If we have the new addOrUpdateTask function, use it
      if (window.addOrUpdateTask && typeof window.addOrUpdateTask === 'function') {
        console.log("✅ Using new addOrUpdateTask function")
        
        // Map the data to the format expected by addOrUpdateTask
        const taskData = {
          task_id: data.task_id,
          task_type: data.task_type,
          agent_type: data.agent_type,
          description: data.description,
          status: data.status || (data.type === 'task_completed' ? 'completed' : data.type === 'task_failed' ? 'failed' : 'running'),
          progress: data.progress,
          message: data.message || data.error,
          error: data.error,
          started_at: data.started_at
        }
        
        // Handle specific task types
        if (data.type === 'task_completed') {
          taskData.status = 'completed'
          taskData.progress = 100
          taskData.message = taskData.message || 'Task completed successfully'
        } else if (data.type === 'task_failed') {
          taskData.status = 'failed'
          taskData.error = data.error
        }
        
        window.addOrUpdateTask(taskData)
      }
    }
    
    // Utility to get CSRF token
    window.getCSRFToken = () => {
      return document.querySelector('meta[name="csrf-token"]')?.content || 
             document.querySelector('[name="authenticity_token"]')?.value || ""
    }
    window.scoutLoadMoreCampaigns = () => this.sendScoutMessage("Please load more campaigns")

    // Group management
    window.scoutCreateGroup = () => this.sendScoutMessage("Please help me create a new contact group")
    window.scoutAddToGroup = (contactId) => this.sendScoutMessage(`Please add contact ${contactId} to a group`)

    // Campaign actions
    window.scoutSendCampaign = (id) => this.sendScoutMessage(`Please send campaign ID ${id}`)
    window.scoutScheduleCampaign = (id) => this.sendScoutMessage(`Please schedule campaign ID ${id}`)
    window.scoutDuplicateCampaign = (id) => this.sendScoutMessage(`Please duplicate campaign ID ${id}`)

    // Reports and exports
    window.scoutExportReport = () => this.sendScoutMessage("Please export analytics report")
    window.scoutCustomReport = () => this.sendScoutMessage("Please create a custom report")
    
    // Landing Page Wizard Functions
    window.landingPageWizard = {
      currentStep: 1,
      selectedFormType: null,
      waitingForCompletion: false,
      selectedImages: {},
      
      init() {
        this.currentStep = 1
        this.selectedFormType = null
        this.waitingForCompletion = false
        this.selectedImages = {}
        this.setupFormSelection();
      },
      
      setupFormSelection() {
        // Handle form option selection
        document.querySelectorAll('.form-option').forEach(option => {
          option.addEventListener('click', () => {
            // Remove selection from all options
            document.querySelectorAll('.form-option').forEach(opt => 
              opt.classList.remove('selected'));
            
            // Select clicked option
            option.classList.add('selected');
            this.selectedFormType = option.dataset.formType;
            
            // Enable create button
            const createBtn = document.getElementById('createPageBtn');
            if (createBtn) createBtn.disabled = false;
          });
        });
      }
    }
    
    window.goToStep1 = () => {
      const step1 = document.getElementById('wizard-step-1');
      const step2 = document.getElementById('wizard-step-2');
      const indicator1 = document.getElementById('step-indicator-1');
      const indicator2 = document.getElementById('step-indicator-2');
      
      if (step1 && step2 && indicator1 && indicator2) {
        step2.classList.add('d-none');
        step1.classList.remove('d-none');
        
        // Update step indicators
        indicator2.classList.remove('active');
        indicator1.classList.add('active');
        
        window.landingPageWizard.currentStep = 1;
      }
    }
    
    window.goToStep2 = () => {
      const title = document.getElementById('pageTitle')?.value.trim();
      let description = document.getElementById('pageDescription')?.value.trim();
      // Enforce backend limits to prevent validation failures downstream
      if (description && description.length > 1000) {
        description = description.slice(0, 1000);
        document.getElementById('pageDescription').value = description;
      }
      
      if (!title || !description) {
        window.showWarning('Please fill in both the title and description fields.');
        return;
      }
      
      const step1 = document.getElementById('wizard-step-1');
      const step2 = document.getElementById('wizard-step-2');
      const indicator1 = document.getElementById('step-indicator-1');
      const indicator2 = document.getElementById('step-indicator-2');
      
      if (step1 && step2 && indicator1 && indicator2) {
        step1.classList.add('d-none');
        step2.classList.remove('d-none');
        
        // Update step indicators
        indicator1.classList.remove('active');
        indicator1.classList.add('completed');
        indicator2.classList.add('active');
        
        window.landingPageWizard.currentStep = 2;
      }
    }
    
    window.goToStep3 = () => {
      const step2 = document.getElementById('wizard-step-2');
      const step3 = document.getElementById('wizard-step-3');
      const indicator2 = document.getElementById('step-indicator-2');
      const indicator3 = document.getElementById('step-indicator-3');

      if (step2 && step3 && indicator2 && indicator3) {
        step2.classList.add('d-none');
        step3.classList.remove('d-none');

        indicator2.classList.remove('active');
        indicator2.classList.add('completed');
        indicator3.classList.add('active');

        window.landingPageWizard.currentStep = 3;
        window.landingPageWizard.setupFormSelection();
      }
    }

    window.createLandingPage = () => {
      const title = document.getElementById('pageTitle')?.value.trim();
      let description = document.getElementById('pageDescription')?.value.trim();
      if (description && description.length > 1000) {
        description = description.slice(0, 1000);
      }
      const formType = window.landingPageWizard.selectedFormType;
      
      if (!title || !description || !formType) {
        window.showWarning('Please complete all steps before creating the page.');
        return;
      }
      
      const step3 = document.getElementById('wizard-step-3');
      const step4 = document.getElementById('wizard-step-4');
      const indicator3 = document.getElementById('step-indicator-3');
      const indicator4 = document.getElementById('step-indicator-4');
      
      if (step3 && step4 && indicator3 && indicator4) {
        // Show creation step
        step3.classList.add('d-none');
        step4.classList.remove('d-none');
        
        // Update step indicators
        indicator3.classList.remove('active');
        indicator3.classList.add('completed');
        indicator4.classList.add('active');
        
        window.landingPageWizard.currentStep = 4;
        
        // Update status message
        const statusElement = document.getElementById('creationStatus');
        if (statusElement) {
          statusElement.textContent = 'Creating your landing page with AI-powered content generation...';
        }
        
        // Set up detection for when canvas changes (indicating success)
        window.landingPageWizard.waitingForCompletion = true;
        
        // Fallback timeout in case canvas detection fails
        setTimeout(() => {
          if (window.landingPageWizard?.waitingForCompletion) {
            console.log('⚠️ Landing page wizard timeout - forcing redirect to viewer');
            window.landingPageWizard.waitingForCompletion = false;
            window.scoutLoadCanvas?.('landing_page_viewer');
          }
        }, 30000); // 30 second timeout (more reasonable with auto-refresh)
        
        // Build the creation message
        let message = `Create a landing page titled "${title}". ${description}`;
        
        if (formType === 'none') {
          message += ' This page should not include any contact forms.';
        } else if (formType === 'custom') {
          message += ' Please ask me what type of custom contact form I need for this page.';
        } else {
          message += ` Include a ${formType.replace('_', ' ')} form to collect visitor information.`;
        }

        // Pass any selected/generated images as hints (encode as JSON block too)
        const imgs = window.landingPageWizard.selectedImages;
        const hero = imgs.hero;
        const f1 = imgs.feature1; const f2 = imgs.feature2;
        const imageHints = [];
        if (hero) imageHints.push(`Use this hero image URL: ${hero}`);
        if (f1) imageHints.push(`Use this feature image URL: ${f1}`);
        if (f2) imageHints.push(`Use this feature image URL: ${f2}`);
        if (imageHints.length) {
          message += ` Images: ${imageHints.join(' ')}.`;
        }
        const imagesJson = { hero: hero || null, feature1: f1 || null, feature2: f2 || null };
        message += `\n\nSELECTED_IMAGES_JSON: ${JSON.stringify(imagesJson)}`;

        // Include structured form selection for deterministic handling server-side
        if (formType) {
          message += `\n\nSELECTED_FORM: ${formType}`;
        }
        
        // Send to Scout
        this.sendScoutMessage(message);
      }
    }

    // === Pictures step helpers ===
    // Delegates to the Bootstrap modal-based image picker defined in the wizard template
    window.loadImageLibrary = (targetImgId) => {
      if (window.openImageLibraryModal) {
        window.openImageLibraryModal(targetImgId)
      } else {
        window.showInfo('Image library not available yet. Please try again.')
      }
    }

    // Upload image from local disk to library and set preview
    window.openImageFilePicker = (targetImgId, inputId) => {
      const input = document.getElementById(inputId)
      if (input) {
        // Attach a one-time change handler
        input.onchange = () => {
          window.uploadImageFromInput(inputId, targetImgId)
        }
        input.click()
      }
    }

    window.uploadImageFromInput = async (inputId, targetImgId) => {
      const input = document.getElementById(inputId)
      if (!input || !input.files || !input.files[0]) { return }
      const file = input.files[0]

      const formData = new FormData()
      formData.append('image_asset[file]', file)
      formData.append('image_asset[title]', file.name)
      formData.append('image_asset[source]', 'upload')

      try {
        const res = await fetch('/image_assets.json', {
          method: 'POST',
          headers: { 'X-CSRF-Token': this.getCSRFToken() },
          body: formData
        })
        const data = await res.json()
        if (data.image?.url) {
          const imgEl = document.getElementById(targetImgId)
          if (imgEl) imgEl.src = data.image.url
          rememberSelectedImage(targetImgId, data.image.url)
        } else {
          window.showError(data.error || 'Upload failed.')
        }
      } catch (e) {
        window.showError('Upload failed.')
      } finally {
        // reset input so same file can be picked again if needed
        input.value = ''
      }
    }

    window.generateAiImage = async (promptInputId, targetImgId, size) => {
      const prompt = document.getElementById(promptInputId)?.value.trim();
      if (!prompt) { window.showWarning('Enter a description first.'); return; }
      const btn = event?.currentTarget; if (btn) btn.disabled = true;
      try {
        // Map requested sizes to OpenAI-supported sizes
        const sizeMap = (s) => {
          if (!s) return '1024x1024'
          const [w, h] = s.split('x').map(Number)
          if (!w || !h) return '1024x1024'
          if (w === h) return '1024x1024'
          return w > h ? '1792x1024' : '1024x1792'
        }
        const res = await fetch('/image_assets/generate', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': this.getCSRFToken() },
          body: JSON.stringify({ prompt, size: sizeMap(size) })
        });
        const data = await res.json();
        if (data.image?.url) {
          const imgEl = document.getElementById(targetImgId);
          if (imgEl) imgEl.src = data.image.url;
          rememberSelectedImage(targetImgId, data.image.url);
        } else {
          window.showError('Image generation failed.');
        }
      } catch (e) {
        window.showError('Image generation failed.');
      } finally {
        if (btn) btn.disabled = false;
      }
    }

    // Expose so modal (inline script) can call it
    window.rememberSelectedImage = function rememberSelectedImage(targetId, url) {
      if (!window.landingPageWizard) return;
      if (targetId.includes('hero')) window.landingPageWizard.selectedImages.hero = url;
      if (targetId.includes('feature1')) window.landingPageWizard.selectedImages.feature1 = url;
      if (targetId.includes('feature2')) window.landingPageWizard.selectedImages.feature2 = url;
    }

    console.log("🌐 Canvas globals initialized")
  }

  // Execute inline scripts contained within dynamically injected HTML
  executeInlineScripts(container) {
    try {
      const scripts = container.querySelectorAll('script')
      scripts.forEach(oldScript => {
        const newScript = document.createElement('script')
        // Copy attributes
        Array.from(oldScript.attributes).forEach(attr => newScript.setAttribute(attr.name, attr.value))
        // Copy inline code
        newScript.text = oldScript.textContent
        // Replace to execute
        oldScript.parentNode.replaceChild(newScript, oldScript)
      })
    } catch (e) {
      console.warn('Failed to execute inline scripts for canvas:', e)
    }
  }

  // Send a message from canvas to Scout
  sendScoutMessage(message) {
    console.log(`💬 Canvas sending message: ${message}`)
    
    // Use the new streaming handler if available
    if (window.handleStreamingChat && typeof window.handleStreamingChat === 'function') {
      // Add user message
      if (window.addMessage && typeof window.addMessage === 'function') {
        window.addMessage(message, 'user');
      } else {
        this.addMessage(message, "user");
      }
      
      // Show typing indicator
      if (window.showTypingIndicator && typeof window.showTypingIndicator === 'function') {
        window.showTypingIndicator();
      }
      
      // Use the new streaming handler
      window.handleStreamingChat(message).catch(error => {
        console.error('Streaming chat error:', error);
        if (window.hideTypingIndicator) window.hideTypingIndicator();
        if (window.addMessage) {
          window.addMessage('Sorry, I encountered an error. Please try again.', 'assistant');
        }
      });
    } else {
      // Fallback to old method
      this.addMessage(message, "user");
      this.showLoading();
      this.processMessage(message);
    }
  }

  // Update chat header
  updateChatHeader(title) {
    const chatTitle = this.chatAreaTarget.querySelector(".chat-title h2")
    if (chatTitle) {
      chatTitle.textContent = title
    }
  }

  // Render a tool call message inline in chat (no avatar, subtle style)
  addToolMessage(toolName, phase, data = {}) {
    try {
      const toolText = phase === 'start' ? `Utilizing ${toolName} tool` : (phase === 'end' ? `${toolName} completed` : `${toolName} detected`)
      const hasDetails = data && Object.keys(data).length > 0
      const collapseId = `tool-details-${Date.now()}-${Math.random().toString(36).slice(2,7)}`
      const detailsToggle = hasDetails ? `
          <button class="btn btn-link btn-sm p-0 ms-2 align-baseline text-white-50" type="button" 
                  data-bs-toggle="collapse" data-bs-target="#${collapseId}" aria-expanded="false" aria-controls="${collapseId}"
                  title="Show details">
            <i class="bi bi-chevron-down"></i>
          </button>
        ` : ''
      const details = hasDetails ? `
          <div id="${collapseId}" class="collapse mt-2">
            <pre class="mt-2 mb-0" style="white-space: pre-wrap; word-break: break-word;">${this.escapeForPre(JSON.stringify(data, null, 2))}</pre>
          </div>
        ` : ''
      const wrapper = document.createElement('div')
      wrapper.className = 'message tool-message'
      wrapper.innerHTML = `
        <div class="message-content">
          <div class="message-bubble" style="font-style: italic; color: #fff; background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.08);">
            <div class="tool-bubble d-flex align-items-center justify-content-between" style="width:100%">
              <span>${this.escapeHtmlInline(toolText)}</span>${detailsToggle}
            </div>
            ${details}
          </div>
        </div>
      `
      this.chatMessagesTarget.appendChild(wrapper)
      
      // If we are in the middle of streaming an AI message, keep that bubble at the bottom
      if (this.currentStreamingContent !== undefined && this.streamingMessageElement) {
        const streamingContainer = this.streamingMessageElement.closest('.message')
        if (streamingContainer) {
          // Move the streaming message to the end so narrative order stays correct
          this.chatMessagesTarget.appendChild(streamingContainer)
        }
      }
      
      this.scrollChatToBottom()
    } catch (e) {
      console.warn('Failed to render tool message', e)
    }
  }

  // Escape inline text (no wrapping tags)
  escapeHtmlInline(text) {
    const div = document.createElement('div')
    div.textContent = text || ''
    return div.innerHTML
  }

  // Escape for <pre>
  escapeForPre(text) {
    return (text || '').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  }

  // Update template content
  updateTemplateContent(content) {
    if (this.hasTemplateContentTarget) {
      this.templateContentTarget.innerHTML = content
    }
  }

  // Utility methods
  // Loading methods for different use cases
  showLoading() {
    // No-op: streaming is handled in the main chat UI
    // Legacy streaming window removed
  }

  hideLoading() {
    // Hide the streaming window when done
    this.hideStreamingWindow()
  }

  // Separate loading overlay methods for canvas operations
  showCanvasLoading(canvasType = 'canvas') {
    // Don't show blocking overlay for parallel tasks canvas
    if (canvasType === 'parallel_tasks') {
      console.log("⚡ Non-blocking load for parallel tasks canvas")
      return
    }
    
    if (this.hasLoadingOverlayTarget) {
      this.loadingOverlayTarget.classList.add("active")

      // Set context-specific loading messages
      const messages = {
        landing_page_viewer: 'Preparing your landing pages...',
        landing_page_generator: 'Setting up the builder...',
        campaign_viewer: 'Loading campaigns...',
        contact_viewer: 'Fetching contacts...',
        integrations_manager: 'Loading integrations...',
        integration_connect: 'Connecting service...',
        analytics_dashboard: 'Building dashboard...',
        campaign_editor: 'Opening editor...',
        email_template_editor: 'Opening template editor...',
        email_template_viewer: 'Loading templates...',
        parallel_tasks: 'Loading task monitor...'
      }

      const message = messages[canvasType] || 'Preparing canvas...'

      // Update title
      let titleElement = this.loadingOverlayTarget.querySelector('.loading-title')
      if (titleElement) {
        titleElement.textContent = "Scout is working..."
      }

      // Update message
      let messageElement = this.loadingOverlayTarget.querySelector('.loading-message')
      if (messageElement) {
        messageElement.textContent = message
      }

      // Reinitialize Lucide icons in the overlay
      if (typeof lucide !== 'undefined') {
        lucide.createIcons()
      }
    }
  }

  hideCanvasLoading() {
    if (this.hasLoadingOverlayTarget) {
      this.loadingOverlayTarget.classList.remove("active")
    }
  }

  // Tool Thinking UI Methods
  showToolThinking(initialStep = null) {
    if (this.isShowingToolThinking) return
    
    this.isShowingToolThinking = true
    this.toolThinkingSteps = []
    
    // Create the tool thinking UI element
    const thinkingUI = document.createElement('div')
    thinkingUI.className = 'tool-thinking-window'
    thinkingUI.innerHTML = `
      <div class="tool-thinking-header">
        <i data-lucide="cpu" style="width: 16px; height: 16px;"></i>
        <span>Working on your request...</span>
      </div>
      <div class="tool-thinking-steps" id="tool-thinking-steps">
        ${initialStep ? `<div class="thinking-step">${initialStep}</div>` : ''}
      </div>
      <div class="tool-thinking-progress">
        <div class="thinking-progress-bar"></div>
      </div>
    `
    
    // Add styles if not already present
    if (!document.querySelector('#tool-thinking-styles')) {
      const styles = document.createElement('style')
      styles.id = 'tool-thinking-styles'
      styles.textContent = `
        .tool-thinking-window {
          background: var(--scout-bg-secondary, #1a1d2e);
          border: 1px solid var(--scout-border, #2a2d3e);
          border-radius: 8px;
          margin: 1rem 1rem 0.5rem 1rem;
          padding: 0;
          max-height: 120px;
          overflow: hidden;
          animation: slideDown 0.3s ease-out;
        }
        
        @keyframes slideDown {
          from {
            opacity: 0;
            transform: translateY(-10px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
        
        .tool-thinking-header {
          display: flex;
          align-items: center;
          gap: 8px;
          padding: 8px 12px;
          background: var(--scout-bg-tertiary, #141722);
          border-bottom: 1px solid var(--scout-border, #2a2d3e);
          font-size: 0.875rem;
          color: var(--scout-text-secondary, #a0a6bb);
        }
        
        .tool-thinking-steps {
          padding: 8px 12px;
          max-height: 60px;
          overflow-y: auto;
        }
        
        .thinking-step {
          font-size: 0.813rem;
          color: var(--scout-text-primary, #e2e8f0);
          padding: 2px 0;
          opacity: 0;
          animation: fadeIn 0.3s ease-out forwards;
        }
        
        @keyframes fadeIn {
          to {
            opacity: 1;
          }
        }
        
        .tool-thinking-progress {
          height: 2px;
          background: var(--scout-bg-tertiary, #141722);
          position: relative;
          overflow: hidden;
        }
        
        .thinking-progress-bar {
          height: 100%;
          background: var(--scout-primary, #7c3aed);
          width: 0%;
          animation: progress 2s ease-in-out infinite;
        }
        
        @keyframes progress {
          0% { width: 0%; }
          50% { width: 70%; }
          100% { width: 100%; }
        }
        
        /* Hide scrollbar but keep functionality */
        .tool-thinking-steps::-webkit-scrollbar {
          width: 0px;
        }

        /* Determinate progress mode (when percentage is known) */
        .tool-thinking-window.has-percentage .thinking-progress-bar {
          animation: none;
        }

        .progress-percentage {
          position: absolute;
          right: 8px;
          top: -18px;
          font-size: 0.75rem;
          font-weight: 600;
          color: var(--scout-text-secondary, #a0a6bb);
        }
      `
      document.head.appendChild(styles)
    }
    
    // Insert before the last message or at the end
    const messages = this.chatMessagesTarget.querySelectorAll('.message')
    const lastMessage = messages[messages.length - 1]
    
    if (lastMessage && lastMessage.classList.contains('ai-message')) {
      lastMessage.parentNode.insertBefore(thinkingUI, lastMessage)
    } else {
      this.chatMessagesTarget.appendChild(thinkingUI)
    }
    
    this.toolThinkingElement = thinkingUI
    
    // Initialize Lucide icons
    if (typeof lucide !== 'undefined') {
      lucide.createIcons()
    }
    
    // For voice mode, announce once
    const voiceModeToggle = document.getElementById('voice-toggle-checkbox')
    if (voiceModeToggle?.checked) {
      this.speakText("One moment, let me work on that for you.")
    }
    
    if (initialStep) {
      this.toolThinkingSteps.push(initialStep)
    }
    
    this.scrollChatToBottom()
  }
  
  addToolThinkingStep(step) {
    if (!this.isShowingToolThinking || !this.toolThinkingElement) {
      this.showToolThinking(step)
      return
    }
    
    this.toolThinkingSteps.push(step)
    
    // Keep only the last 3 steps
    if (this.toolThinkingSteps.length > 3) {
      this.toolThinkingSteps.shift()
    }
    
    const stepsContainer = this.toolThinkingElement.querySelector('#tool-thinking-steps')
    if (stepsContainer) {
      stepsContainer.innerHTML = this.toolThinkingSteps
        .map(s => `<div class="thinking-step">${s}</div>`)
        .join('')
      
      // Scroll to show latest step
      stepsContainer.scrollTop = stepsContainer.scrollHeight
    }
  }
  
  hideToolThinking(delay = 300) {
    if (!this.isShowingToolThinking || !this.toolThinkingElement) return
    
    // Clear any pending timeout
    if (this.toolThinkingTimeout) {
      clearTimeout(this.toolThinkingTimeout)
    }
    
    // Fade out and remove after delay
    this.toolThinkingTimeout = setTimeout(() => {
      if (this.toolThinkingElement) {
        this.toolThinkingElement.style.opacity = '0'
        this.toolThinkingElement.style.transform = 'translateY(-10px)'
        this.toolThinkingElement.style.transition = 'all 0.3s ease-out'
        
        setTimeout(() => {
          if (this.toolThinkingElement) {
            this.toolThinkingElement.remove()
            this.toolThinkingElement = null
          }
        }, 300)
      }
      
      this.isShowingToolThinking = false
      this.toolThinkingSteps = []
    }, delay)
  }

  // Update tool progress with percentage for long-running operations
  updateToolProgress(progressData) {
    const { tool, message, percentage } = progressData

    // Start tool thinking UI if not visible
    if (!this.isShowingToolThinking) {
      this.showToolThinking(message)
    }

    if (this.toolThinkingElement) {
      // Switch to determinate mode with actual percentage
      if (percentage !== null && percentage !== undefined) {
        this.toolThinkingElement.classList.add('has-percentage')

        const progressBar = this.toolThinkingElement.querySelector('.thinking-progress-bar')
        if (progressBar) {
          progressBar.style.animation = 'none'
          progressBar.style.width = `${Math.min(100, Math.max(0, percentage))}%`
          progressBar.style.transition = 'width 0.4s ease-out'
        }

        // Add/update percentage label
        let percentLabel = this.toolThinkingElement.querySelector('.progress-percentage')
        if (!percentLabel) {
          percentLabel = document.createElement('span')
          percentLabel.className = 'progress-percentage'
          const progressContainer = this.toolThinkingElement.querySelector('.tool-thinking-progress')
          if (progressContainer) {
            progressContainer.style.position = 'relative'
            progressContainer.appendChild(percentLabel)
          }
        }
        percentLabel.textContent = `${Math.round(percentage)}%`
      }

      // Update status message
      if (message) {
        this.addToolThinkingStep(message)
      }
    }
  }

  showStreamingProgress(message) {
    // No-op: streaming is handled in the main chat UI
    // Legacy streaming window removed
    console.log('Legacy showStreamingProgress called (disabled):', message)
  }

  showStreamingWindow(message) {
    // No-op: streaming is handled in the main chat UI
    // Legacy streaming window removed
    console.log('Legacy showStreamingWindow called (disabled):', message)
  }

  hideStreamingWindow() {
    // No-op: streaming is handled in the main chat UI
    // Legacy streaming window removed
  }

  scrollChatToBottom() {
    if (this.hasChatMessagesTarget) {
      this.chatMessagesTarget.scrollTop = this.chatMessagesTarget.scrollHeight
    }
  }

  

  getCSRFToken() {
    // Check for CSRF token in multiple possible locations
    
    // Method 1: Meta tag (most common)
    const metaToken = document.querySelector('meta[name="csrf-token"]')
    if (metaToken) {
      const content = metaToken.getAttribute('content') || metaToken.content
      if (content) {
        console.log('✅ CSRF token found in meta tag')
        return content
      }
    }
    
    // Method 2: Alternative meta tag name
    const altMetaToken = document.querySelector('meta[name="authenticity_token"]')
    if (altMetaToken) {
      const content = altMetaToken.getAttribute('content') || altMetaToken.content
      if (content) {
        console.log('✅ CSRF token found in alt meta tag')
        return content
      }
    }
    
    // Method 3: From Rails form input
    const formToken = document.querySelector('input[name="authenticity_token"]')
    if (formToken && formToken.value) {
      console.log('✅ CSRF token found in form input')
      return formToken.value
    }
    
    // Method 4: From the Scout form specifically
    const scoutForm = document.querySelector('#message-form input[name="authenticity_token"]')
    if (scoutForm && scoutForm.value) {
      console.log('✅ CSRF token found in Scout form')
      return scoutForm.value
    }
    
    // Debug output
    console.error("❌ CSRF token not found! Upload will fail.")
    console.log("Debug - All meta tags:", Array.from(document.querySelectorAll('meta')).map(m => m.getAttribute('name')))
    console.log("Debug - CSRF meta element:", document.querySelector('meta[name="csrf-token"]'))
    console.log("Debug - Form inputs:", Array.from(document.querySelectorAll('input[name="authenticity_token"]')).length)
    
    return ""
  }
  
  // Upload files to the server
  async uploadFiles(files) {
    console.log('📎 uploadFiles called with', files.length, 'files')

    const formData = new FormData()
    files.forEach((file, index) => {
      console.log(`📎 Appending file[${index}]:`, file.name, file.type, file.size)
      formData.append(`files[${index}]`, file)
    })

    // Add storage choice from modal - use captured value to avoid race conditions
    const storageChoice = window.capturedStorageChoice || window.documentStorageChoice || 'long-term';
    formData.append('storage_type', storageChoice);
    console.log('📎 Storage type:', storageChoice);
    
    // Clear captured choice after use
    window.capturedStorageChoice = null;

    try {
      console.log('📎 Sending POST to /scout/upload_files')
      const response = await fetch('/scout/upload_files', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: formData
      })

      console.log('📎 Upload response status:', response.status)

      if (!response.ok) {
        // Try to get error details from response
        let errorDetails = 'File upload failed'
        try {
          const errorData = await response.json()
          console.error('📎 Upload error response:', errorData)
          errorDetails = errorData.error || errorDetails
          if (errorData.details) {
            console.error('📎 Error details:', errorData.details)
          }
        } catch (e) {
          console.error('📎 Could not parse error response')
        }
        throw new Error(errorDetails)
      }

      const result = await response.json()
      console.log('📎 Upload result:', result)

      if (result.rag_stores_created && result.rag_stores_created.length > 0) {
        console.log('✅ RAG stores created:', result.rag_stores_created)
        console.log('✅ Message:', result.message)
      }
      
      // Check for duplicate uploads
      const duplicateUploads = result.urls ? result.urls.filter(u => u.duplicate) : []
      if (duplicateUploads.length > 0) {
        console.log('ℹ️ Duplicate documents found:', duplicateUploads.map(u => u.filename))
      }

      // If a document was uploaded successfully, try to open it in the viewer
      if (result.urls && result.urls.length > 0) {
        const documentUploads = result.urls.filter(u => u.asset_type === 'document' && u.asset_id)
        if (documentUploads.length > 0) {
          console.log('📄 Opening document viewer for uploaded document:', documentUploads[0])
          // Add a message to let the user know what's happening
          this.addMessage('I\'ll open the document viewer for you...', 'ai')
          // Small delay to ensure the document is ready
          setTimeout(() => {
            this.loadScoutCanvas('document_viewer', { 
              asset_id: documentUploads[0].asset_id 
            })
          }, 1000)
        }
      }

      return result.urls || []
    } catch (error) {
      console.error('❌ File upload error:', error)
      this.addMessage('Failed to upload files. Please try again.', 'ai')
      return []
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
    
    // Get sidebar width (hub-sidebar or side-nav)
    const hubSidebar = this.element.querySelector('.hub-sidebar')
    const sideNav = this.sideNavTarget
    const sidebarWidth = hubSidebar?.offsetWidth || sideNav?.offsetWidth || 0
    
    // Calculate mouse position relative to content area (after sidebar)
    const mouseX = event.clientX - workspaceRect.left - sidebarWidth
    
    // Get chat area element
    const chatArea = this.chatAreaTarget
    if (!chatArea) return
    
    // Calculate available width (everything after sidebar)
    const availableWidth = workspaceRect.width - sidebarWidth
    
    // Calculate new chat width in pixels
    const minWidth = 320
    const maxWidth = Math.min(600, availableWidth * 0.5) // Max 50% of available
    const newWidth = Math.max(minWidth, Math.min(maxWidth, mouseX))
    
    // Apply the new width directly to chat area
    chatArea.style.flex = `0 0 ${newWidth}px`
    chatArea.style.maxWidth = `${newWidth}px`
    
    console.log(`🔄 Resizing chat to ${newWidth}px`)
    
    // Save to localStorage
    localStorage.setItem('scout-chat-width', newWidth)
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

  restoreChatWidth() {
    // Restore saved chat width from localStorage
    const savedWidth = localStorage.getItem('scout-chat-width')
    if (savedWidth && this.hasChatAreaTarget) {
      const width = parseInt(savedWidth, 10)
      if (width >= 320 && width <= 600) {
        this.chatAreaTarget.style.flex = `0 0 ${width}px`
        this.chatAreaTarget.style.maxWidth = `${width}px`
        console.log(`📐 Restored chat width: ${width}px`)
      }
    }
  }
  
  loadChatWidth() {
    const isDesignMode = this.element.classList.contains('design-space')
    
    if (isDesignMode) {
      const savedWidth = localStorage.getItem('scout-design-chat-width')
      const widthToApply = savedWidth || '400px'
      
      console.log(`📐 Loading design chat width: ${widthToApply}`)
      this.element.style.setProperty('--design-chat-width', widthToApply)
    } else {
      const savedWidth = localStorage.getItem('scout-chat-width')
      const widthToApply = savedWidth ? parseFloat(savedWidth) : 18
      
      console.log(`📐 Loading chat width for work mode: ${widthToApply}%`)
      this.setChatWidth(widthToApply)
      
      // Update active preset to match loaded width
      setTimeout(() => {
        this.updateActivePreset(widthToApply)
      }, 100)
    }
  }

  saveChatWidth() {
    const isDesignMode = this.element.classList.contains('design-space')
    
    if (isDesignMode) {
      const designWidth = getComputedStyle(this.element).getPropertyValue('--design-chat-width')
      if (designWidth) {
        localStorage.setItem('scout-design-chat-width', designWidth)
        console.log(`💾 Saved design chat width: ${designWidth}`)
      }
    } else {
      const currentWidth = getComputedStyle(this.element).getPropertyValue('--chat-width')
      if (currentWidth) {
        const widthValue = parseFloat(currentWidth)
        localStorage.setItem('scout-chat-width', widthValue.toString())
        console.log(`💾 Saved chat width: ${widthValue}%`)
      }
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

  

  // Escape HTML for user messages
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return `<p>${div.innerHTML}</p>`
  }

  // Handle user profile form submission in canvas
  setupUserProfileForm() {
    console.log("🚀 Setting up user profile form handling");
    
    // Wait for canvas content to be loaded
    setTimeout(() => {
      const form = document.querySelector('#user-profile-form');
      console.log("📝 User profile form found:", !!form);
      
      if (form) {
        // Remove any existing event listeners
        form.removeEventListener('submit', this.handleUserProfileSubmit);
        form.addEventListener('submit', this.handleUserProfileSubmit.bind(this), true);
        console.log("✅ User profile form handlers attached");
      } else {
        console.log("❌ User profile form not found");
        console.log("❌ Available forms:", document.querySelectorAll('form'));
      }
    }, 200);
  }
  
  // Handle user profile form submission
  handleUserProfileSubmit(e) {
    console.log("📤 User profile form submitted via AJAX - PREVENTING DEFAULT!");
    e.preventDefault();
    e.stopImmediatePropagation();
    e.stopPropagation();
    
    const form = e.target;
    const formData = new FormData(form);
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    
    // Show visual feedback
    const submitBtn = form.querySelector('button[type="submit"]');
    if (submitBtn) {
      submitBtn.disabled = true;
      submitBtn.innerHTML = '<i data-lucide="loader-circle" class="icon-spin" aria-hidden="true"></i> Saving...';

      // Re-initialize Lucide icons
      if (typeof lucide !== 'undefined') {
        lucide.createIcons()
      }
    }
    
    console.log("🌐 Making AJAX request to:", form.action);
    
    fetch(form.action, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': csrfToken,
        'Accept': 'application/json'
      },
      body: formData
    })
    .then(response => {
      console.log("📡 Response received:", response.status, response.statusText);
      return response.json();
    })
    .then(data => {
      console.log("✅ Profile update response:", data);
      if (data.success !== false) {
        this.addMessage('✅ Profile updated successfully!', 'ai');
        window.scoutRefreshCanvas();
      } else {
        this.addMessage('❌ Sorry, there was an error updating your profile. Please try again.', 'ai');
      }
    })
    .catch(error => {
      console.error('Profile update error:', error);
      this.addMessage('❌ Sorry, there was an error updating your profile. Please try again.', 'ai');
    })
    .finally(() => {
      // Restore button state
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.innerHTML = '<i data-lucide="save" aria-hidden="true"></i> Save Changes';

        // Re-initialize Lucide icons
        if (typeof lucide !== 'undefined') {
          lucide.createIcons()
        }
      }
    });
    
    return false;
  }

  // Handle business profile forms submission in canvas
  setupBusinessProfileForms() {
    console.log("🏢 Setting up business profile form handling");
    
    // Wait for canvas content to be loaded
    setTimeout(() => {
      const formIds = ['#basic-info-form', '#brand-form', '#knowledge-form'];
      
      formIds.forEach(formId => {
        const form = document.querySelector(formId);
        console.log(`📝 Business profile form ${formId} found:`, !!form);
        
        if (form) {
          // Remove any existing event listeners
          form.removeEventListener('submit', this.handleBusinessProfileSubmit);
          form.addEventListener('submit', this.handleBusinessProfileSubmit.bind(this), true);
          console.log(`✅ Business profile form ${formId} handlers attached`);
        }
      });
      
      if (document.querySelectorAll('#basic-info-form, #brand-form, #knowledge-form').length === 0) {
        console.log("❌ No business profile forms found");
        console.log("❌ Available forms:", document.querySelectorAll('form'));
      }
    }, 200);
  }
  
  // Handle business profile form submission
  handleBusinessProfileSubmit(e) {
    console.log("📤 Business profile form submitted via AJAX - PREVENTING DEFAULT!");
    e.preventDefault();
    e.stopImmediatePropagation();
    e.stopPropagation();
    
    const form = e.target;
    const formData = new FormData(form);
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    
    // Show visual feedback
    const submitBtn = form.querySelector('button[type="submit"]');
    const originalBtnContent = submitBtn ? submitBtn.innerHTML : '';
    if (submitBtn) {
      submitBtn.disabled = true;
      submitBtn.innerHTML = '<i data-lucide="loader-circle" class="icon-spin" aria-hidden="true"></i> Saving...';

      // Re-initialize Lucide icons
      if (typeof lucide !== 'undefined') {
        lucide.createIcons()
      }
    }
    
    console.log("🌐 Making AJAX request to:", form.action);
    
    fetch(form.action, {
      method: form.method.toUpperCase(),
      headers: {
        'X-CSRF-Token': csrfToken,
        'Accept': 'application/json'
      },
      body: formData
    })
    .then(response => {
      console.log("📡 Response received:", response.status, response.statusText);
      return response.json();
    })
    .then(data => {
      console.log("✅ Business profile update response:", data);
      if (data.success !== false) {
        this.addMessage('✅ Business profile updated successfully!', 'ai');
        // Refresh canvas after a short delay to show updates
        setTimeout(() => window.scoutRefreshCanvas(), 1000);
      } else {
        this.addMessage('❌ Sorry, there was an error updating your business profile. Please try again.', 'ai');
      }
    })
    .catch(error => {
      console.error('Business profile update error:', error);
      this.addMessage('❌ Sorry, there was an error updating your business profile. Please try again.', 'ai');
    })
    .finally(() => {
      // Restore button state
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.innerHTML = originalBtnContent;
      }
    });
    
    return false;
  }
  
  // Handle streaming TTS - speak completed thoughts with smart buffering
  handleStreamingTTS(newContent) {
    if (!window.ttsManager || !window.ttsManager.isEnabled) {
      return
    }
    
    // Add new content to buffer
    this.ttsBuffer += newContent
    this.ttsLastChunkTime = Date.now()
    
    // Clear any existing timeout
    if (this.ttsBufferTimeout) {
      clearTimeout(this.ttsBufferTimeout)
    }
    
    // Process buffer for natural pause points
    this.processTTSBuffer()
    
    // Set a timeout to speak whatever's left after a pause in streaming
    this.ttsBufferTimeout = setTimeout(() => {
      this.flushTTSBuffer()
    }, this.ttsMinBufferTime)
  }
  
  // Process the TTS buffer looking for natural pause points
  processTTSBuffer() {
    // Natural pause patterns to look for
    const pausePatterns = [
      // Complete sentences
      /[.!?][\s\n]+/,
      // Before lists or examples
      /:\s*\n/,
      // After "For example" type phrases
      /(?:For example|Such as|Including|Like):\s*/i,
      // Complete list items (with content after the marker)
      /^[-*•]\s*.+$/m,
      // After a paragraph break
      /\n\n/
    ]
    
    let speakableContent = ''
    let remainingBuffer = this.ttsBuffer
    
    // Check each pattern
    for (const pattern of pausePatterns) {
      const match = remainingBuffer.match(pattern)
      if (match) {
        const pauseIndex = match.index + match[0].length
        
        // Check if we have enough content before the pause
        const beforePause = remainingBuffer.substring(0, pauseIndex).trim()
        
        // Only speak if we have substantial content (not just fragments)
        if (beforePause.length > 15 && this.isCompleteThought(beforePause)) {
          speakableContent = beforePause
          remainingBuffer = remainingBuffer.substring(pauseIndex)
          break
        }
      }
    }
    
    // If we found speakable content, speak it
    if (speakableContent) {
      // Clean up the text for speaking
      const cleanedText = this.cleanTextForTTS(speakableContent)
      
      if (cleanedText.length > 0) {
        console.log('🎤 Speaking natural pause:', cleanedText)
        window.ttsManager.speak(cleanedText, {
          messageId: `streaming-${Date.now()}`,
          immediate: false
        })
      }
      
      // Update buffer with remaining content
      this.ttsBuffer = remainingBuffer
    }
  }
  
  // Check if text appears to be a complete thought
  isCompleteThought(text) {
    // Incomplete if it ends with certain words
    const incompleteEndings = /\b(the|a|an|to|for|with|and|or|but|of|in|on|at|by)\s*$/i
    if (incompleteEndings.test(text)) {
      return false
    }
    
    // Incomplete if it has unmatched parentheses or quotes
    const openParens = (text.match(/\(/g) || []).length
    const closeParens = (text.match(/\)/g) || []).length
    if (openParens !== closeParens) {
      return false
    }
    
    // Check for common incomplete patterns
    if (text.endsWith('help me') || text.endsWith('can you')) {
      return false
    }
    
    return true
  }
  
  // Clean text for TTS (remove markdown, etc.)
  cleanTextForTTS(text) {
    return text
      // Remove markdown bold/italic
      .replace(/\*{1,2}([^*]+)\*{1,2}/g, '$1')
      // Remove list markers
      .replace(/^[-*•]\s*/gm, '')
      // Remove extra whitespace
      .replace(/\s+/g, ' ')
      .trim()
  }
  
  // Flush any remaining buffer content
  flushTTSBuffer() {
    if (this.ttsBuffer.trim().length > 0) {
      const cleanedText = this.cleanTextForTTS(this.ttsBuffer)
      
      if (cleanedText.length > 0 && this.isCompleteThought(cleanedText)) {
        console.log('🎤 Flushing TTS buffer:', cleanedText)
        window.ttsManager.speak(cleanedText, {
          messageId: `streaming-flush-${Date.now()}`,
          immediate: false
        })
      }
      
      this.ttsBuffer = ''
    }
  }
  
  // Clean up any remaining TTS buffer when streaming completes
  finalizeStreamingTTS() {
    // Check if this was an agent question that needs special handling
    if (this.streamingIsAgentQuestion) {
      console.log("🎤 Finalizing agent question TTS")
      const voiceModeToggle = document.getElementById('voice-toggle-checkbox')
      
      // If we have content that looks like a question and voice mode is on
      if (voiceModeToggle?.checked && this.currentStreamingContent && this.currentStreamingContent.includes('?')) {
        console.log("🔊 Ensuring agent question is spoken:", this.currentStreamingContent.substring(0, 100))
        // Give a small delay to ensure streaming is done
        setTimeout(() => {
          if (!window.ttsManager?.isPlaying) {
            this.speakText(this.currentStreamingContent)
          }
        }, 100)
      }
      
      // Reset the flag
      this.streamingIsAgentQuestion = false
    }
    
    if (!window.ttsManager || !window.ttsManager.isEnabled) {
      return
    }
    
    // Clear any pending timeout
    if (this.ttsBufferTimeout) {
      clearTimeout(this.ttsBufferTimeout)
      this.ttsBufferTimeout = null
    }
    
    // Flush any remaining content
    this.flushTTSBuffer()
    
    // Reset all TTS state
    this.ttsBuffer = ''
    this.lastTTSPosition = 0
    this.ttsLastChunkTime = 0
  }
  
  // Clear all TTS state (used when interrupting)
  clearTTSState() {
    // Clear any pending timeout
    if (this.ttsBufferTimeout) {
      clearTimeout(this.ttsBufferTimeout)
      this.ttsBufferTimeout = null
    }
    
    // Reset all buffers
    this.ttsBuffer = ''
    this.lastTTSPosition = 0
    this.ttsLastChunkTime = 0
    
    console.log("🧹 Cleared TTS state")
  }
} 