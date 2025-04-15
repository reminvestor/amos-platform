import { Controller } from "@hotwired/stimulus"

// LandingPageChat controller for handling chat interactions with AI
export default class extends Controller {
  static targets = ["messages", "input", "loading", "rollbackOption", "sectionSelector"]
  static values = {
    landingPageId: Number,
    refreshInterval: { type: Number, default: 2000 },
    pollTimeout: { type: Number, default: 120000 }, // 2 minutes
    rollbackTimeout: { type: Number, default: 60000 } // 1 minute
  }

  connect() {
    console.log("Landing page chat controller connected")
    this.pollInterval = null
    this.fetchMessages()
    
    // Load sections when preview frame loads
    const previewFrame = document.getElementById('previewFrame')
    if (previewFrame) {
      previewFrame.addEventListener('load', () => this.loadSectionsFromPreview())
    }
    
    // Connect refresh sections button
    const refreshSectionsBtn = document.getElementById('refreshSections')
    if (refreshSectionsBtn) {
      refreshSectionsBtn.addEventListener('click', () => this.loadSectionsFromPreview())
    }
    
    // Initial load of sections
    this.loadSectionsFromPreview()
  }

  disconnect() {
    this.stopPolling()
  }

  // Submit the chat form
  submit(event) {
    event.preventDefault()

    const message = this.inputTarget.value.trim()
    if (!message) return

    // Disable input while processing
    this.inputTarget.disabled = true

    // Show user message immediately
    this.addMessageToUI({
      role: 'user',
      content: message,
      timestamp: new Date().toISOString()
    })

    // Show loading indicator
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove('d-none')
    }
    
    // Get selected section index if available
    const requestData = { instruction: message }
    
    // Check if we have a section selector target and it has a value
    if (this.hasSectionSelectorTarget && this.sectionSelectorTarget.value !== '') {
      requestData.section_index = parseInt(this.sectionSelectorTarget.value, 10)
    } else {
      // If using the DOM ID as fallback (for backward compatibility)
      const selectorElement = document.getElementById('sectionSelector')
      if (selectorElement && selectorElement.value !== '') {
        requestData.section_index = parseInt(selectorElement.value, 10)
      }
    }

    // Send message to server
    fetch(`/landing_pages/${this.landingPageIdValue}/apply_change`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify(requestData)
    })
    .then(response => response.json())
    .then(data => {
      // Clear input and re-enable it
      this.inputTarget.value = ''
      this.inputTarget.disabled = false
      this.inputTarget.focus()

      // Handle the response
      if (data.status === 'processing') {
        // Add system message
        this.addSystemMessage(data.message || "Processing your request...")
        
        // Message accepted, now poll for new messages
        this.pollForNewMessages(data.message_id)
      } else {
        // Error or other status
        if (this.hasLoadingTarget) {
          this.loadingTarget.classList.add('d-none')
        }
        this.addSystemMessage("Error processing your request. Please try again.")
        console.error('Error:', data)
      }
    })
    .catch(error => {
      this.inputTarget.disabled = false
      if (this.hasLoadingTarget) {
        this.loadingTarget.classList.add('d-none')
      }
      this.addSystemMessage("An error occurred. Please try again.")
      console.error('Error:', error)
    })
  }

  // Add a system message to the chat
  addSystemMessage(content) {
    this.addMessageToUI({
      role: 'system',
      content: content,
      timestamp: new Date().toISOString()
    })
  }

  // Fetch all messages for this landing page
  fetchMessages() {
    if (!this.landingPageIdValue) return

    fetch(`/landing_pages/${this.landingPageIdValue}/get_chat_messages`)
      .then(response => response.json())
      .then(data => {
        // Clear existing messages
        this.messagesTarget.innerHTML = ''

        // Add all messages to the UI
        data.messages.forEach(message => {
          this.addMessageToUI(message)
        })
        
        // If no messages, add a welcome message
        if (data.messages.length === 0) {
          this.addSystemMessage("Hi there! I'm your AI design assistant. I can help you improve this landing page. Try asking me to make changes to specific sections.")
        }

        // Scroll to bottom
        this.scrollToBottom()
      })
      .catch(error => {
        console.error('Error fetching messages:', error)
        // Add a welcome message if history can't be loaded
        this.addSystemMessage("Hi there! I'm your AI design assistant. I can help you improve this landing page.")
      })
  }
  
  // Load sections from the preview
  loadSectionsFromPreview() {
    try {
      // Get landing page data from the preview
      fetch(`/landing_pages/${this.landingPageIdValue}/preview.json`)
        .then(response => response.json())
        .then(data => {
          // Get the selector element
          const selectorElement = this.hasSectionSelectorTarget ? 
            this.sectionSelectorTarget : 
            document.getElementById('sectionSelector')
            
          if (!selectorElement) return
              
          // Clear existing options except the first one (General)
          while (selectorElement.options.length > 1) {
            selectorElement.remove(1)
          }
          
          // Add sections to the selector
          if (data.content && Array.isArray(data.content)) {
            data.content.forEach((section, index) => {
              const option = document.createElement('option')
              option.value = index
              option.textContent = `Section ${index + 1}: ${section.title || 'Untitled Section'}`
              selectorElement.appendChild(option)
            })
          }
        })
    } catch (error) {
      console.error('Error loading sections:', error)
    }
  }

  // Poll for new messages after sending a request
  pollForNewMessages(lastMessageId) {
    this.stopPolling() // Clear any existing poll

    this.pollInterval = setInterval(() => {
      fetch(`/landing_pages/${this.landingPageIdValue}/get_chat_messages`)
        .then(response => response.json())
        .then(data => {
          const newMessages = data.messages.filter(msg => 
            msg.id > lastMessageId && msg.role === 'assistant'
          )

          if (newMessages.length > 0) {
            // We have new response(s)
            this.stopPolling()
            if (this.hasLoadingTarget) {
              this.loadingTarget.classList.add('d-none')
            }

            // Add new messages to UI
            newMessages.forEach(message => {
              this.addMessageToUI(message)
            })

            // Scroll to bottom
            this.scrollToBottom()

            // Show rollback option after AI responds
            if (this.hasRollbackOptionTarget) {
              this.rollbackOptionTarget.classList.remove('d-none')
              
              // Auto-hide after timeout
              setTimeout(() => {
                this.rollbackOptionTarget.classList.add('d-none')
              }, this.rollbackTimeoutValue)
            }

            // Refresh the preview and sections
            this.refreshPreview()
            this.loadSectionsFromPreview()
          }
        })
        .catch(error => {
          console.error('Error polling for messages:', error)
          this.stopPolling()
          if (this.hasLoadingTarget) {
            this.loadingTarget.classList.add('d-none')
          }
        })
    }, this.refreshIntervalValue)

    // Stop polling after timeout
    setTimeout(() => {
      this.stopPolling()
      if (this.hasLoadingTarget) {
        this.loadingTarget.classList.add('d-none')
      }
    }, this.pollTimeoutValue)
  }

  // Add a message to the UI
  addMessageToUI(message) {
    const messageElement = document.createElement('div')
    messageElement.classList.add('message', `message-${message.role}`)

    const timestamp = new Date(message.timestamp).toLocaleTimeString()
    
    // Convert newlines to <br> for proper display
    const content = message.content.replace(/\n/g, '<br>')

    if (message.role === 'system') {
      messageElement.innerHTML = content
    } else {
      messageElement.innerHTML = `
        <div class="chat-bubble">
          <div class="chat-content">${content}</div>
          <div class="chat-timestamp">${timestamp}</div>
        </div>
      `
    }

    this.messagesTarget.appendChild(messageElement)
    this.scrollToBottom()
  }

  // Scroll chat to bottom
  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  // Refresh the preview iframe if available
  refreshPreview() {
    const previewFrame = document.getElementById('previewFrame')
    if (previewFrame) {
      previewFrame.src = previewFrame.src
    }
  }

  // Stop polling for messages
  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
      this.pollInterval = null
    }
  }
} 