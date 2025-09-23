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
    this.currentMode = "conversation"
    this.currentCanvas = null
    this.isResizing = false
    
    // Make controller globally accessible
    window.scoutController = this
    
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
    
    // Don't automatically restore canvas state - let user start fresh
    // this.restoreCanvasState()
  }
  
  disconnect() {
    // Clean up event listener
    if (this.handleCanvasLoadEvent) {
      document.removeEventListener('scout:load-canvas', this.handleCanvasLoadEvent)
    }
  }

  // Save canvas state to localStorage
  saveCanvasState() {
    if (this.currentCanvas) {
      localStorage.setItem('scout_canvas_state', JSON.stringify({
        type: this.currentCanvas.type,
        data: this.currentCanvas.data || {},
        title: this.currentCanvas.title,
        mode: this.currentMode
      }))
      console.log("💾 Saved canvas state:", this.currentCanvas.type)
    }
  }

  // Restore canvas state from localStorage
  restoreCanvasState() {
    try {
      const savedState = localStorage.getItem('scout_canvas_state')
      if (savedState) {
        const canvasState = JSON.parse(savedState)
        console.log("🔄 Restoring canvas state:", canvasState.type)
        
        // Restore the canvas after a short delay to ensure DOM is ready
        setTimeout(() => {
          this.loadScoutCanvas(canvasState.type, canvasState.data || {})
        }, 500)
      }
    } catch (e) {
      console.log("Could not restore canvas state:", e.message)
      localStorage.removeItem('scout_canvas_state')
    }
  }

  // Clear canvas state
  clearCanvasState() {
    localStorage.removeItem('scout_canvas_state')
    console.log("🗑️ Cleared canvas state")
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
    
    // Parse markdown for AI messages - use simple parser to match DB messages
    const formattedContent = role === "ai" ? this.parseSimpleMarkdown(content) : this.escapeHtml(content)
    
    messageDiv.innerHTML = `
      <div class="message-avatar">
        <i class="${avatar}"></i>
      </div>
      <div class="message-content">
        ${formattedContent}
      </div>
    `
    
    this.chatMessagesTarget.appendChild(messageDiv)
    this.scrollChatToBottom()
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

  // Enhanced processMessage to handle canvas actions
  async processMessage(message) {
    try {
      console.log("🔄 Processing message:", message)
      
      // Legacy streaming window removed - handled in main chat UI
      
      // Use streaming endpoint for better timeout handling
      const response = await fetch("/scout/chat_stream", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify({ 
          message: message,
          current_canvas: this.currentCanvas
        })
      })

      console.log("📡 Scout streaming response received:", response.status)
      
      if (!response.body) {
        throw new Error("No response body received")
      }
      
      const reader = response.body.getReader()
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
                
                if (data.type === 'update') {
                  // Show progress update in the streaming window
                  console.log("🔄 Progress:", data.message)
                  this.showStreamingProgress(data.message)
                  
                  // Initialize streaming when we see the streaming message
                  if (data.message === '💬 streaming') {
                    console.log('📝 Streaming started - initializing message')
                    // Find the last AI message or create a new one
                    const messages = this.chatMessagesTarget.querySelectorAll('.message')
                    const lastMessage = messages[messages.length - 1]
                    
                    // Only create new message if last one isn't already an empty AI message
                    if (!lastMessage || !lastMessage.classList.contains('ai-message') || 
                        lastMessage.querySelector('.message-content')?.textContent.trim()) {
                      this.addMessage('', 'ai')
                    }
                    this.currentStreamingContent = ''
                  }
                } else if (data.type === 'content') {
                  // Handle content chunks for streaming
                  if (data.content && this.currentStreamingContent !== undefined) {
                    this.currentStreamingContent += data.content
                    console.log("📝 Accumulated content:", this.currentStreamingContent.length, "chars")
                    console.log("🔍 Content preview:", JSON.stringify(this.currentStreamingContent.substring(this.currentStreamingContent.length - 50)))
                    
                    // Debug: Check for excessive newlines in accumulated content
                    const newlineMatches = this.currentStreamingContent.match(/\n/g)
                    if (newlineMatches && newlineMatches.length > 10) {
                      console.warn(`⚠️ Accumulated content has ${newlineMatches.length} newlines!`)
                    }
                    
                    // Update the last message with the accumulated content
                    const messages = this.chatMessagesTarget.querySelectorAll('.message')
                    console.log("🔍 Found", messages.length, "total messages")
                    
                    const lastMessage = messages[messages.length - 1]
                    if (lastMessage && lastMessage.classList.contains('ai-message')) {
                      const messageContent = lastMessage.querySelector('.message-content')
                      if (messageContent) {
                        // During streaming, use textContent to avoid HTML parsing issues
                        messageContent.textContent = this.currentStreamingContent
                        console.log("✅ Updated message content")
                        console.log("📝 Streaming text:", this.currentStreamingContent.substring(0, 100) + "...")
                      } else {
                        console.error("❌ No .message-content found in last message")
                      }
                    } else {
                      console.error("❌ Last message is not an AI message or no messages found")
                    }
                    this.scrollChatToBottom()
                  }
                } else if (data.type === 'response') {
                  // Final response received - hide streaming window and show message
                  finalResponseData = data.data
                  console.log("✅ Final response received, message length:", finalResponseData?.message?.length || 0)
                  
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
            const messageContent = lastMessage.querySelector('.message-content')
            if (messageContent && this.currentStreamingContent) {
              // Apply simple markdown parsing to match how DB messages are displayed
              messageContent.innerHTML = this.parseSimpleMarkdown(this.currentStreamingContent)
              console.log("✅ Applied final markdown formatting")
            }
          }
        }
        // Clear streaming content
        this.currentStreamingContent = null
        
        // Check if Scout suggested a canvas to load
        if (finalResponseData.canvas) {
          console.log(`🎨 Scout suggested canvas: ${finalResponseData.canvas}`)
          if (finalResponseData.canvas_data) {
            console.log("📊 Canvas data:", finalResponseData.canvas_data)
          }
          
          // Check if suggested canvas is the same as current (stay and refresh vs navigate)
          const isSameCanvas = this.currentCanvas && 
                              this.currentCanvas.type === finalResponseData.canvas &&
                              this.currentCanvas.data?.landing_page_id === finalResponseData.canvas_data?.landing_page_id
          
          if (isSameCanvas) {
            console.log("🔄 Staying on same canvas - refreshing immediately since job is complete")
            // Job is already done by the time final response arrives, refresh now!
            setTimeout(() => {
              this.loadScoutCanvas(finalResponseData.canvas, finalResponseData.canvas_data || {})
            }, 500)
          } else {
            console.log("🎯 Loading different canvas...")
            setTimeout(() => {
              this.loadScoutCanvas(finalResponseData.canvas, finalResponseData.canvas_data || {})
            }, 1000)
          }
        } else {
          console.log("ℹ️ No canvas suggested in response")
          // Handle data changes that might require canvas refresh
          this.handleDataChanges(finalResponseData)
        }
        
        // Re-enable input after successful response
        this.enableChatInput()
      } else {
        // Hide streaming window even if no final response
        this.hideStreamingWindow()
        console.log("❌ No message in response data")
        this.addMessage("Sorry, I couldn't process that request. Please try again.", "ai")
      }
    
    } catch (error) {
      console.error("❌ Error sending message:", error)
      this.hideStreamingWindow()
      this.addMessage("Sorry, something went wrong. Please try again.", "ai")
    } finally {
      // Re-enable the chat input
      this.enableChatInput()
    }
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
      
      // Clear current canvas reference
      this.currentCanvas = null
      
      // Reset chat header
      this.updateChatHeader("What can I help you with today?")
    }
  }

  // Go to conversation mode
  goToConversation() {
    console.log("🏠 Going to conversation mode")
    this.switchToMode("conversation")
    this.clearCanvasState()
    this.addMessage("Scout here! What would you like to work on?", "ai")
  }

  // Nav handler methods
  loadLandingPagesCanvas() {
    console.log("🌐 Loading landing pages canvas")
    this.loadScoutCanvas("landing_page_viewer", {})
  }

  loadCampaignsCanvas() {
    console.log("📧 Loading campaigns canvas")  
    this.loadScoutCanvas("campaign_viewer", {})
  }

  loadEmailTemplatesCanvas() {
    console.log("📄 Loading email templates canvas")
    this.loadScoutCanvas("email_template_viewer", {})
  }

  loadAnalyticsCanvas() {
    console.log("📊 Loading analytics canvas")
    this.loadScoutCanvas("analytics_dashboard", {})
  }

  loadContactsCanvas() {
    console.log("👥 Loading contacts canvas")
    this.loadScoutCanvas("contact_viewer", {})
  }

  // Profile and settings methods
  openSettings() {
    console.log("⚙️ Opening business settings")
    // Load business profile canvas instead of redirecting
    this.loadScoutCanvas("business_profile", {})
  }

  openProfile() {
    console.log("👤 Opening user profile")
    // Load user profile canvas instead of redirecting
    this.loadScoutCanvas("user_profile", {})
  }

  logout() {
    console.log("🚪 Logging out")
    if (confirm('Are you sure you want to logout?')) {
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
    this.switchToMode("conversation")
    this.addMessage("Canvas closed. What else can I help you with?", "ai")
  }

  // ========== SCOUT CANVAS FUNCTIONALITY ==========

  // Load a Scout canvas
  async loadScoutCanvas(canvasType, canvasData = {}) {
    try {
      console.log(`🎨 Loading Scout canvas: ${canvasType}`)
      console.log(`📦 Canvas data:`, canvasData)
      
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
      
      this.showCanvasLoading()

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

        // Execute any inline <script> tags from the injected canvas content
        this.executeInlineScripts(this.templateContentTarget)
        
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
        
        // Add confirmation message to chat (skip for task progress canvas)
        if (canvasType !== 'task_progress') {
          this.addMessage(`Loaded ${data.canvas.title}. You can interact with the data on the right while we continue our conversation here.`, "ai")
        }
        
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
    window.scoutPreviewLandingPageInTab = (id) => window.open(`/landing_pages/${id}/preview`, '_blank')
    
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
        alert('HTML editor not found');
        return;
      }
      
      const htmlContent = htmlEditor.value;
      console.log('HTML content length:', htmlContent.length);
      
      if (!htmlContent.trim()) {
        alert('HTML content cannot be empty');
        return;
      }
      
      // Show saving indicator
      const saveBtn = event.target;
      const originalText = saveBtn.innerHTML;
      saveBtn.innerHTML = '<i class="fas fa-spinner fa-spin me-1"></i> Saving...';
      saveBtn.disabled = true;
      
      console.log('Sending PATCH request to update landing page...');
      
      // Get CSRF token safely - try Rails global first, then fallback to meta tags
      let csrfToken = window.Rails?.csrfToken ||
                      document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ||
                      document.querySelector('[name="csrf-token"]')?.value ||
                      document.querySelector('[name="authenticity_token"]')?.value;
      
      if (!csrfToken) {
        console.error('CSRF token not found');
        alert('Security token not found. Please refresh the page and try again.');
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
          saveBtn.innerHTML = '<i class="fas fa-check me-1"></i> Saved!';
          saveBtn.classList.remove('btn-success');
          saveBtn.classList.add('btn-success');
          
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
        saveBtn.innerHTML = '<i class="fas fa-exclamation-triangle me-1"></i> Error';
        saveBtn.classList.add('btn-danger');
        
        setTimeout(() => {
          saveBtn.innerHTML = originalText;
          saveBtn.classList.remove('btn-danger');
          saveBtn.disabled = false;
        }, 3000);
      });
    }
    
    // Landing page management functions
    window.scoutPublishLandingPage = (id) => {
      if (confirm('Are you sure you want to publish this landing page?')) {
        this.sendScoutMessage(`Please publish landing page ID ${id}`)
      }
    }
    window.scoutUnpublishLandingPage = (id) => {
      if (confirm('Are you sure you want to unpublish this landing page?')) {
        this.sendScoutMessage(`Please unpublish landing page ID ${id}`)
      }
    }

    // Delete functions
    window.scoutDeleteContact = (id) => {
      if (confirm('Are you sure you want to delete this contact?')) {
        this.sendScoutMessage(`Please delete contact ID ${id}`)
      }
    }
    window.scoutDeleteCampaign = (id) => {
      if (confirm('Are you sure you want to delete this campaign?')) {
        this.sendScoutMessage(`Please delete campaign ID ${id}`)
      }
    }
    window.scoutDeleteLandingPage = (id) => {
      if (confirm('Are you sure you want to delete this landing page?')) {
        this.sendScoutMessage(`Please delete landing page ID ${id}`)
      }
    }

    // Import/Export functions
    window.scoutImportContacts = () => this.sendScoutMessage("Please help me import contacts")
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
        alert('Please fill in both the title and description fields.');
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
        alert('Please complete all steps before creating the page.');
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
        alert('Image library not available yet. Please try again.')
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
          alert(data.error || 'Upload failed.')
        }
      } catch (e) {
        alert('Upload failed.')
      } finally {
        // reset input so same file can be picked again if needed
        input.value = ''
      }
    }

    window.generateAiImage = async (promptInputId, targetImgId, size) => {
      const prompt = document.getElementById(promptInputId)?.value.trim();
      if (!prompt) { alert('Enter a description first.'); return; }
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
          alert('Image generation failed.');
        }
      } catch (e) {
        alert('Image generation failed.');
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
  showCanvasLoading() {
    if (this.hasLoadingOverlayTarget) {
      this.loadingOverlayTarget.classList.add("active")
      // Set canvas loading message
      let messageElement = this.loadingOverlayTarget.querySelector('.loading-spinner p')
      if (messageElement) {
        messageElement.textContent = "🎨 Loading canvas..."
      }
    }
  }

  hideCanvasLoading() {
    if (this.hasLoadingOverlayTarget) {
      this.loadingOverlayTarget.classList.remove("active")
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

  parseSimpleMarkdown(text) {
    if (!text) return ''
    
    // Simple markdown parsing - display exactly what the LLM sends
    let parsed = text
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/`([^`]+)`/g, '<code>$1</code>')
    
    // Convert newlines to breaks exactly as sent by LLM
    parsed = parsed.replace(/\n/g, '<br>')
    
    return parsed
  }

  getCSRFToken() {
    // Check for CSRF token in multiple possible locations
    const csrfToken = document.querySelector('meta[name="csrf-token"]') || 
                     document.querySelector('meta[name="authenticity_token"]')
    
    if (csrfToken) {
      return csrfToken.getAttribute('content')
    } else {
      // Try to get from Rails UJS if available
      const railsToken = document.querySelector('input[name="authenticity_token"]')
      if (railsToken) {
        return railsToken.value
      }
      
      console.warn("⚠️ CSRF token not found! Request may fail.")
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

  // Simple markdown parser for Scout messages
  parseMarkdown(text) {
    // Split into lines for better processing
    let lines = text.split('\n')
    let html = []
    let inList = false
    
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i]
      
      // Skip empty lines
      if (line.trim() === '') {
        if (inList) {
          html.push('</ul>')
          inList = false
        }
        html.push('<br>')
        continue
      }
      
      // Headers
      if (line.startsWith('### ')) {
        if (inList) { html.push('</ul>'); inList = false }
        html.push(`<h3>${line.substr(4)}</h3>`)
      } else if (line.startsWith('## ')) {
        if (inList) { html.push('</ul>'); inList = false }
        html.push(`<h2>${line.substr(3)}</h2>`)
      } else if (line.startsWith('# ')) {
        if (inList) { html.push('</ul>'); inList = false }
        html.push(`<h1>${line.substr(2)}</h1>`)
      }
      // Blockquotes
      else if (line.startsWith('> ')) {
        if (inList) { html.push('</ul>'); inList = false }
        html.push(`<blockquote>${line.substr(2)}</blockquote>`)
      }
      // Lists
      else if (line.startsWith('- ') || /^\d+\. /.test(line)) {
        if (!inList) {
          html.push('<ul>')
          inList = true
        }
        const content = line.startsWith('- ') ? line.substr(2) : line.replace(/^\d+\. /, '')
        html.push(`<li>${this.parseInlineMarkdown(content)}</li>`)
      }
      // Regular paragraphs
      else {
        if (inList) {
          html.push('</ul>')
          inList = false
        }
        html.push(`<p>${this.parseInlineMarkdown(line)}</p>`)
      }
    }
    
    // Close any open lists
    if (inList) {
      html.push('</ul>')
    }
    
    return html.join('')
  }

  // Parse inline markdown (bold, code, etc.)
  parseInlineMarkdown(text) {
    return text
      // Bold
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      // Code
      .replace(/`(.*?)`/g, '<code>$1</code>')
      // Escape remaining HTML
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
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
      submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
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
        submitBtn.innerHTML = '<i class="fas fa-save"></i> Save Changes';
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
      submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
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
} 