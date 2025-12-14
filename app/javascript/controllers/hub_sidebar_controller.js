import { Controller } from "@hotwired/stimulus"

// HubSidebarController
// Handles Hub sidebar interactions in Team Space mode
export default class extends Controller {
  static values = {
    entity: Number,
    activeThread: String,
    activeType: { type: String, default: "amos" }
  }

  static targets = ["chatContext", "chatTitle", "chatSubtitle"]

  connect() {
    console.log("🌐 Hub Sidebar connected for entity:", this.entityValue)
    this.highlightActive()
  }

  // Select Amos (main AI chat) - this is the default Scout chat
  selectAmos(event) {
    event.preventDefault()
    this.activeTypeValue = "amos"
    this.activeThreadValue = ""
    this.currentMode = 'amos' // Reset mode so Scout handles messages
    this.currentChannelId = null

    this.highlightActive()
    this.updateChatContext("Amos", "Your AI assistant", "sparkles")

    // Remove channel handlers
    this.removeChannelHandlers()
    
    // Clear hub mode from chat messages
    const chatMessages = document.getElementById('chat-messages')
    if (chatMessages) {
      delete chatMessages.dataset.hubMode
      delete chatMessages.dataset.channelId
    }

    // Reload page to restore full Scout state
    window.location.reload()

    console.log("🌐 Selected Amos chat")
  }
  
  removeChannelHandlers() {
    const chatForm = document.getElementById('message-form')
    const textarea = document.getElementById('message-input')
    const sendButton = document.getElementById('send-button')
    
    if (this.boundChannelSubmit) {
      chatForm?.removeEventListener('submit', this.boundChannelSubmit, true)
    }
    if (this.boundKeyHandler) {
      textarea?.removeEventListener('keydown', this.boundKeyHandler)
    }
    if (this.boundClickHandler) {
      sendButton?.removeEventListener('click', this.boundClickHandler, true)
    }
  }

  // Select a channel
  async selectChannel(event) {
    event.preventDefault()
    const channelId = event.currentTarget.dataset.channelId
    const channelName = event.currentTarget.querySelector('.hub-item-name')?.textContent || 'Channel'
    
    this.activeTypeValue = "channel"
    this.activeThreadValue = channelId
    
    this.highlightActive()
    this.updateChatContext(`#${channelName}`, "Team channel", "hash")
    
    console.log("🌐 Selected channel:", channelId)
    await this.loadChannelMessages(channelId, channelName)
  }
  
  async loadChannelMessages(channelId, channelName) {
    const chatMessages = document.getElementById('chat-messages')
    if (!chatMessages) return
    
    // Completely clear any Scout/Amos messages first
    chatMessages.innerHTML = ''
    
    // Prevent Scout from loading more history
    chatMessages.dataset.hubMode = 'channel'
    chatMessages.dataset.channelId = channelId
    
    // Show loading state
    chatMessages.innerHTML = `
      <div class="hub-loading">
        <i data-lucide="loader" class="spin"></i>
        <span>Loading messages...</span>
      </div>
    `
    if (window.lucide) window.lucide.createIcons()
    
    try {
      const response = await fetch(`/hub/channels/${channelId}/messages`, {
        headers: { 'Accept': 'application/json' }
      })
      
      if (response.ok) {
        const data = await response.json()
        this.renderChannelMessages(data, channelName, channelId)
        this.setupChannelInput(channelId)
      } else {
        throw new Error('Failed to load messages')
      }
    } catch (error) {
      console.error("🌐 Error loading channel:", error)
      this.showChannelWelcome(channelName, channelId)
    }
  }
  
  showChannelWelcome(channelName, channelId) {
    const chatMessages = document.getElementById('chat-messages')
    if (!chatMessages) return
    
    chatMessages.innerHTML = `
      <div class="hub-channel-welcome">
        <div class="hub-welcome-icon channel">
          <i data-lucide="hash"></i>
        </div>
        <h3>#${channelName}</h3>
        <p class="text-muted">This is the beginning of the <strong>#${channelName}</strong> channel.</p>
        <p class="hub-start-prompt">
          <i data-lucide="message-square"></i>
          Start the conversation!
        </p>
      </div>
    `
    if (window.lucide) window.lucide.createIcons()
    this.setupChannelInput(channelId)
  }
  
  renderChannelMessages(data, channelName, channelId) {
    const chatMessages = document.getElementById('chat-messages')
    if (!chatMessages) return
    
    const messages = data.messages || []
    
    if (messages.length === 0) {
      this.showChannelWelcome(channelName, channelId)
      return
    }
    
    let html = '<div class="hub-messages-list">'
    let lastDate = null
    
    messages.forEach(msg => {
      const msgDate = new Date(msg.created_at).toLocaleDateString()
      if (msgDate !== lastDate) {
        html += `<div class="hub-date-divider"><span>${msgDate}</span></div>`
        lastDate = msgDate
      }
      html += this.renderMessage(msg)
    })
    
    html += '</div>'
    chatMessages.innerHTML = html
    chatMessages.scrollTop = chatMessages.scrollHeight
    
    if (window.lucide) window.lucide.createIcons()
  }
  
  renderMessage(msg) {
    const isAgent = msg.sender_type === 'AgentPlugin'
    const time = new Date(msg.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    
    return `
      <div class="hub-message ${isAgent ? 'agent' : 'user'}" data-message-id="${msg.id}">
        <div class="hub-message-avatar ${isAgent ? 'agent' : 'user'}">
          ${isAgent ? '<i data-lucide="bot"></i>' : (msg.sender_name?.charAt(0)?.toUpperCase() || '?')}
        </div>
        <div class="hub-message-content">
          <div class="hub-message-header">
            <span class="hub-message-sender">${msg.sender_name || 'Unknown'}</span>
            <span class="hub-message-time">${time}</span>
          </div>
          <div class="hub-message-text">${this.formatMessageContent(msg.content)}</div>
        </div>
      </div>
    `
  }
  
  formatMessageContent(content) {
    if (!content) return ''
    return content
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/`(.*?)`/g, '<code>$1</code>')
      .replace(/\n/g, '<br>')
  }
  
  setupChannelInput(channelId) {
    this.currentChannelId = channelId
    this.currentMode = 'channel'
    
    const chatForm = document.getElementById('message-form')
    const textarea = document.getElementById('message-input')
    const sendButton = document.getElementById('send-button')
    
    if (chatForm) {
      // Remove old handlers
      if (this.boundChannelSubmit) {
        chatForm.removeEventListener('submit', this.boundChannelSubmit, true)
      }
      if (this.boundKeyHandler) {
        textarea?.removeEventListener('keydown', this.boundKeyHandler)
      }
      if (this.boundClickHandler) {
        sendButton?.removeEventListener('click', this.boundClickHandler)
      }
      
      // Create bound handlers
      this.boundChannelSubmit = (e) => this.handleChannelSubmit(e)
      this.boundKeyHandler = (e) => this.handleChannelKeydown(e)
      this.boundClickHandler = (e) => this.handleChannelClick(e)
      
      // Add handlers with capture to intercept before Scout
      chatForm.addEventListener('submit', this.boundChannelSubmit, true)
      textarea?.addEventListener('keydown', this.boundKeyHandler)
      sendButton?.addEventListener('click', this.boundClickHandler, true)
    }
    
    // Focus the input
    textarea?.focus()
  }
  
  handleChannelKeydown(event) {
    if (this.currentMode !== 'channel') return
    
    // Enter without shift sends message
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault()
      event.stopPropagation()
      this.sendChannelMessage()
    }
  }
  
  handleChannelClick(event) {
    if (this.currentMode !== 'channel') return
    
    event.preventDefault()
    event.stopPropagation()
    this.sendChannelMessage()
  }
  
  handleChannelSubmit(event) {
    if (this.currentMode !== 'channel' || !this.currentChannelId) return
    
    event.preventDefault()
    event.stopPropagation()
    this.sendChannelMessage()
  }
  
  async sendChannelMessage() {
    const textarea = document.getElementById('message-input')
    if (!textarea) return
    
    const content = textarea.value.trim()
    if (!content) return
    
    textarea.value = ''
    this.addOptimisticMessage(content)
    
    try {
      const response = await fetch(`/hub/channels/${this.currentChannelId}/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ content: content })
      })
      
      if (!response.ok) throw new Error('Failed to send')
      
      const data = await response.json()
      this.updateOptimisticMessage(data.message)
    } catch (error) {
      console.error("🌐 Error sending:", error)
      this.showNotification("Couldn't send message", "error")
    }
  }
  
  addOptimisticMessage(content) {
    const chatMessages = document.getElementById('chat-messages')
    let messagesList = chatMessages?.querySelector('.hub-messages-list')
    
    // Create list if it doesn't exist (first message)
    if (!messagesList) {
      chatMessages.innerHTML = '<div class="hub-messages-list"></div>'
      messagesList = chatMessages.querySelector('.hub-messages-list')
    }
    
    const tempId = `temp-${Date.now()}`
    const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    
    const html = `
      <div class="hub-message user sending" data-message-id="${tempId}">
        <div class="hub-message-avatar user">${this.getCurrentUserInitial()}</div>
        <div class="hub-message-content">
          <div class="hub-message-header">
            <span class="hub-message-sender">You</span>
            <span class="hub-message-time">${time}</span>
            <i data-lucide="loader" class="spin hub-sending-indicator"></i>
          </div>
          <div class="hub-message-text">${this.formatMessageContent(content)}</div>
        </div>
      </div>
    `
    
    messagesList.insertAdjacentHTML('beforeend', html)
    chatMessages.scrollTop = chatMessages.scrollHeight
    if (window.lucide) window.lucide.createIcons()
    
    this.pendingMessageId = tempId
  }
  
  updateOptimisticMessage(realMessage) {
    if (!this.pendingMessageId) return
    const tempEl = document.querySelector(`[data-message-id="${this.pendingMessageId}"]`)
    if (tempEl) {
      tempEl.dataset.messageId = realMessage?.id || this.pendingMessageId
      tempEl.classList.remove('sending')
      const indicator = tempEl.querySelector('.hub-sending-indicator')
      if (indicator) indicator.remove()
    }
    this.pendingMessageId = null
  }
  
  getCurrentUserInitial() {
    const userAvatar = document.querySelector('.hub-user-avatar')
    return userAvatar?.textContent?.trim() || 'U'
  }

  // Select a DM
  selectDm(event) {
    event.preventDefault()
    const threadId = event.currentTarget.dataset.threadId
    const participantName = event.currentTarget.querySelector('.hub-item-name')?.textContent || 'Unknown'
    const isAgent = event.currentTarget.querySelector('.hub-avatar-agent') !== null
    
    this.activeTypeValue = "dm"
    this.activeThreadValue = threadId
    
    this.highlightActive()
    this.updateChatContext(participantName, isAgent ? "AI Agent" : "Team member", isAgent ? "bot" : "user")
    
    // TODO: Load DM messages
    console.log("🌐 Selected DM:", threadId)
    this.showDmPlaceholder(participantName, isAgent)
  }

  // Select an agent (start DM)
  async selectAgent(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const target = event.currentTarget
    const agentId = target.dataset.agentId
    const agentName = target.dataset.agentName || target.querySelector('.hub-item-name')?.textContent || 'Agent'
    
    console.log("🌐 Starting DM with agent:", agentId, agentName)
    
    // Highlight the selected agent
    this.element.querySelectorAll('.hub-item.active').forEach(el => el.classList.remove('active'))
    target.classList.add('active')
    
    // Update chat context
    this.updateChatContext(agentName, "AI Agent", "bot")
    
    // Set mode for routing messages
    this.currentMode = 'agent_dm'
    this.currentAgentId = agentId
    this.currentAgentName = agentName
    
    // Create or find DM thread with this agent
    await this.startAgentDm(agentId, agentName)
  }

  // Create a new channel
  createChannel(event) {
    event.preventDefault()
    event.stopPropagation()
    console.log("🌐 Create channel clicked")
    
    this.showCreateChannelModal()
  }
  
  showCreateChannelModal() {
    // Remove any existing modal
    const existingModal = document.getElementById('hub-channel-modal')
    if (existingModal) existingModal.remove()
    
    const modal = document.createElement('div')
    modal.id = 'hub-channel-modal'
    modal.className = 'hub-modal-overlay'
    modal.innerHTML = `
      <div class="hub-modal">
        <div class="hub-modal-header">
          <h3><i data-lucide="hash"></i> Create Channel</h3>
          <button class="hub-modal-close" data-action="click->hub-sidebar#closeModal">
            <i data-lucide="x"></i>
          </button>
        </div>
        <div class="hub-modal-body">
          <label class="hub-modal-label">Channel Name</label>
          <div class="hub-channel-input-wrapper">
            <span class="hub-channel-prefix">#</span>
            <input type="text" 
                   id="hub-channel-name-input" 
                   class="hub-modal-input" 
                   placeholder="e.g. marketing-team"
                   maxlength="50"
                   autocomplete="off">
          </div>
          <p class="hub-modal-hint">Names must be lowercase without spaces. Use dashes to separate words.</p>
        </div>
        <div class="hub-modal-footer">
          <button class="hub-modal-btn hub-modal-btn-secondary" data-action="click->hub-sidebar#closeModal">
            Cancel
          </button>
          <button class="hub-modal-btn hub-modal-btn-primary" data-action="click->hub-sidebar#submitCreateChannel">
            Create Channel
          </button>
        </div>
      </div>
    `
    
    document.body.appendChild(modal)
    
    // Focus the input
    setTimeout(() => {
      const input = document.getElementById('hub-channel-name-input')
      if (input) {
        input.focus()
        // Auto-format input
        input.addEventListener('input', (e) => {
          e.target.value = e.target.value.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '')
        })
        // Submit on Enter
        input.addEventListener('keydown', (e) => {
          if (e.key === 'Enter') {
            this.submitCreateChannel(e)
          } else if (e.key === 'Escape') {
            this.closeModal()
          }
        })
      }
      if (window.lucide) window.lucide.createIcons()
    }, 100)
    
    // Close on overlay click
    modal.addEventListener('click', (e) => {
      if (e.target === modal) this.closeModal()
    })
  }
  
  closeModal() {
    const modal = document.getElementById('hub-channel-modal')
    if (modal) {
      modal.classList.add('closing')
      setTimeout(() => modal.remove(), 200)
    }
  }
  
  submitCreateChannel(event) {
    event.preventDefault()
    const input = document.getElementById('hub-channel-name-input')
    const name = input?.value?.trim()
    
    if (!name) {
      input?.classList.add('error')
      setTimeout(() => input?.classList.remove('error'), 500)
      return
    }
    
    this.closeModal()
    this.createChannelRequest(name)
  }
  
  async createChannelRequest(name) {
    try {
      const response = await fetch('/hub/channels', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ channel: { name: name } })
      })
      
      if (response.ok) {
        const data = await response.json()
        console.log("🌐 Channel created:", data)
        this.showNotification(`Channel #${name} created!`, "success")
        // Reload to show new channel
        setTimeout(() => window.location.reload(), 500)
      } else {
        const error = await response.json()
        this.showNotification(error.message || "Couldn't create channel", "error")
      }
    } catch (error) {
      console.error("🌐 Error creating channel:", error)
      this.showNotification("Couldn't create channel. Try again.", "error")
    }
  }

  // Start a new DM - scroll to agents section
  startDm(event) {
    event.preventDefault()
    console.log("🌐 Start DM clicked - scrolling to agents")
    
    // Find and highlight the agents section
    const agentsSection = this.element.querySelector('#hub-agents')
    if (agentsSection) {
      agentsSection.scrollIntoView({ behavior: 'smooth', block: 'center' })
      
      // Highlight the section briefly
      agentsSection.style.background = 'rgba(124, 58, 237, 0.2)'
      setTimeout(() => {
        agentsSection.style.background = ''
      }, 2000)
      
      this.showNotification("Click on an agent below to start a conversation", "info")
    } else {
      this.showNotification("No agents available. Add agents from the Agent Marketplace.", "info")
    }
  }

  // Browse/Add agents - load agent marketplace canvas in Scout
  browseAgents(event) {
    event.preventDefault()
    event.stopPropagation()
    console.log("🌐 Browse agents clicked")
    
    // Use Scout controller to load agent marketplace canvas
    if (window.scoutController && typeof window.scoutController.loadAgentMarketplaceCanvas === 'function') {
      window.scoutController.loadAgentMarketplaceCanvas()
    } else {
      // Fallback: dispatch event for Scout to handle
      window.dispatchEvent(new CustomEvent('loadCanvas', { 
        detail: { type: 'agent_marketplace' } 
      }))
      this.showNotification("Opening Agent Marketplace...", "info")
    }
  }

  // Search conversations
  search(event) {
    const query = event.target.value.toLowerCase()
    console.log("🌐 Searching:", query)
    
    // Filter visible items
    this.filterItems('.hub-channel', query)
    this.filterItems('.hub-dm', query)
    this.filterItems('.hub-agent', query)
  }

  // Helper methods
  highlightActive() {
    // Remove active from all items
    this.element.querySelectorAll('.hub-item.active').forEach(item => {
      item.classList.remove('active')
    })
    
    // Add active to current selection
    if (this.activeTypeValue === "amos") {
      this.element.querySelector('[data-thread-type="amos"]')?.classList.add('active')
    } else if (this.activeTypeValue === "channel" && this.activeThreadValue) {
      this.element.querySelector(`[data-channel-id="${this.activeThreadValue}"]`)?.classList.add('active')
    } else if (this.activeTypeValue === "dm" && this.activeThreadValue) {
      this.element.querySelector(`[data-thread-id="${this.activeThreadValue}"]`)?.classList.add('active')
    }
  }

  updateChatContext(title, subtitle, icon) {
    if (this.hasChatTitleTarget) {
      this.chatTitleTarget.textContent = title
    }
    if (this.hasChatSubtitleTarget) {
      this.chatSubtitleTarget.textContent = subtitle
    }
    if (this.hasChatContextTarget) {
      const avatarIcon = this.chatContextTarget.querySelector('.hub-chat-avatar i')
      if (avatarIcon) {
        avatarIcon.setAttribute('data-lucide', icon)
        // Re-render lucide icons
        if (window.lucide) {
          window.lucide.createIcons()
        }
      }
    }
  }

  filterItems(selector, query) {
    this.element.querySelectorAll(selector).forEach(item => {
      const name = item.querySelector('.hub-item-name')?.textContent?.toLowerCase() || ''
      if (query && !name.includes(query)) {
        item.style.display = 'none'
      } else {
        item.style.display = ''
      }
    })
  }

  showChannelPlaceholder(channelName, channelId) {
    // Redirect to the welcome screen
    this.showChannelWelcome(channelName, channelId)
  }

  showDmPlaceholder(participantName, isAgent) {
    const chatMessages = document.getElementById('chat-messages')
    if (chatMessages) {
      chatMessages.innerHTML = `
        <div class="hub-placeholder">
          <div class="hub-placeholder-icon ${isAgent ? 'agent' : 'user'}">
            <i data-lucide="${isAgent ? 'bot' : 'user'}"></i>
          </div>
          <h3>${participantName}</h3>
          <p>Direct messages with ${isAgent ? 'agents' : 'team members'} coming soon. For now, continue chatting with Amos!</p>
          <button class="btn btn-primary btn-sm" onclick="document.querySelector('[data-thread-type=amos]').click()">
            <i data-lucide="sparkles" class="me-1"></i>
            Back to Amos
          </button>
        </div>
      `
      if (window.lucide) {
        window.lucide.createIcons()
      }
    }
  }

  async startAgentDm(agentId, agentName) {
    const chatMessages = document.getElementById('chat-messages')
    if (!chatMessages) return
    
    // Show loading state
    chatMessages.innerHTML = ''
    chatMessages.dataset.hubMode = 'agent_dm'
    chatMessages.dataset.agentId = agentId
    
    chatMessages.innerHTML = `
      <div class="hub-loading">
        <i data-lucide="loader" class="spin"></i>
        <span>Loading conversation with ${agentName}...</span>
      </div>
    `
    if (window.lucide) window.lucide.createIcons()
    
    try {
      // Create or find DM thread with this agent
      const response = await fetch('/hub/dms', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ 
          participant_type: 'AgentPlugin',
          participant_id: agentId 
        })
      })
      
      if (!response.ok) {
        throw new Error('Failed to create DM thread')
      }
      
      const data = await response.json()
      console.log("🌐 Agent DM thread:", data)
      
      this.currentThreadId = data.thread.id
      
      // Load messages from this thread
      await this.loadThreadMessages(data.thread.id, agentName)
      
      // Setup input for agent DM
      this.setupAgentDmInput()
      
    } catch (error) {
      console.error("🌐 Error starting agent DM:", error)
      chatMessages.innerHTML = `
        <div class="hub-error">
          <i data-lucide="alert-circle"></i>
          <span>Failed to start conversation with ${agentName}</span>
          <button class="btn btn-sm btn-outline-primary mt-2" onclick="location.reload()">Retry</button>
        </div>
      `
      if (window.lucide) window.lucide.createIcons()
    }
  }
  
  async loadThreadMessages(threadId, participantName) {
    const chatMessages = document.getElementById('chat-messages')
    if (!chatMessages) return
    
    try {
      const response = await fetch(`/hub/thread/${threadId}`, {
        headers: { 'Accept': 'application/json' }
      })
      
      if (!response.ok) {
        throw new Error('Failed to load messages')
      }
      
      const data = await response.json()
      const messages = data.messages || []
      
      if (messages.length === 0) {
        // Show welcome message for empty conversation
        chatMessages.innerHTML = `
          <div class="hub-agent-chat-welcome">
            <div class="hub-welcome-icon">
              <i data-lucide="bot"></i>
            </div>
            <h3>Chat with ${participantName}</h3>
            <p class="text-muted">Start your conversation with ${participantName}.</p>
            <p class="text-muted small">Send a message to get started!</p>
          </div>
        `
      } else {
        // Render existing messages
        this.renderThreadMessages(messages)
      }
      
      if (window.lucide) window.lucide.createIcons()
      
    } catch (error) {
      console.error("🌐 Error loading thread messages:", error)
      chatMessages.innerHTML = `
        <div class="hub-error">
          <i data-lucide="alert-circle"></i>
          <span>Failed to load messages</span>
        </div>
      `
      if (window.lucide) window.lucide.createIcons()
    }
  }
  
  renderThreadMessages(messages) {
    const chatMessages = document.getElementById('chat-messages')
    if (!chatMessages) return
    
    // Use the same rendering as channel messages
    let html = '<div class="hub-messages-list">'
    let lastDate = null
    
    messages.forEach(msg => {
      const msgDate = new Date(msg.created_at).toLocaleDateString()
      if (msgDate !== lastDate) {
        html += `<div class="hub-date-divider"><span>${msgDate}</span></div>`
        lastDate = msgDate
      }
      html += this.renderMessage(msg)
    })
    
    html += '</div>'
    chatMessages.innerHTML = html
    
    // Scroll to bottom
    chatMessages.scrollTop = chatMessages.scrollHeight
  }
  
  setupAgentDmInput() {
    const form = document.getElementById('message-form')
    const textarea = document.getElementById('message-input')
    const sendButton = document.getElementById('send-button')
    
    if (!form || !textarea) {
      console.warn("🌐 Message form not found for agent DM setup")
      return
    }
    
    // Remove existing channel handlers if any
    this.removeChannelHandlers()
    
    // Create bound handlers for agent DM
    this.boundAgentSubmit = (e) => {
      e.preventDefault()
      e.stopPropagation()
      e.stopImmediatePropagation()
      this.handleAgentDmSubmit()
      return false
    }
    
    this.boundAgentKeydown = (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault()
        e.stopPropagation()
        e.stopImmediatePropagation()
        this.handleAgentDmSubmit()
        return false
      }
    }
    
    this.boundAgentClick = (e) => {
      e.preventDefault()
      e.stopPropagation()
      e.stopImmediatePropagation()
      this.handleAgentDmSubmit()
      return false
    }
    
    // Add capture-phase handlers to intercept before Scout
    form.addEventListener('submit', this.boundAgentSubmit, true)
    textarea.addEventListener('keydown', this.boundAgentKeydown, true)
    if (sendButton) {
      sendButton.addEventListener('click', this.boundAgentClick, true)
    }
    
    console.log("🌐 Agent DM input handlers set up")
  }
  
  async handleAgentDmSubmit() {
    const textarea = document.getElementById('message-input')
    const content = textarea?.value?.trim()
    
    if (!content || !this.currentThreadId) {
      console.warn("🌐 No content or thread ID for agent DM")
      return
    }
    
    console.log("🌐 Sending to agent thread:", this.currentThreadId, content)
    
    // Clear input
    textarea.value = ''
    textarea.style.height = 'auto'
    
    // Add optimistic message
    this.addOptimisticMessage(content, 'You')
    
    try {
      const response = await fetch(`/hub/thread/${this.currentThreadId}/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ content: content })
      })
      
      if (!response.ok) {
        const error = await response.text()
        console.error("🌐 Agent DM error:", error)
        throw new Error('Failed to send message')
      }
      
      const data = await response.json()
      console.log("🌐 Agent DM message sent:", data)
      
      // Update the optimistic message with real data
      if (data.message) {
        this.updateOptimisticMessage(data.message)
      }
      
      // Show typing indicator for agent response
      this.showAgentTyping(this.currentAgentName)
      
    } catch (error) {
      console.error("🌐 Error sending agent DM:", error)
      this.showMessageError(content)
    }
  }
  
  showAgentTyping(agentName) {
    const chatMessages = document.getElementById('chat-messages')
    if (!chatMessages) return
    
    // Remove any existing typing indicator
    chatMessages.querySelector('.hub-typing-indicator')?.remove()
    
    const typingDiv = document.createElement('div')
    typingDiv.className = 'hub-typing-indicator'
    typingDiv.innerHTML = `
      <div class="hub-message-avatar hub-avatar-agent">
        <i data-lucide="bot"></i>
      </div>
      <span>${agentName} is thinking...</span>
      <div class="hub-typing-dots">
        <span></span><span></span><span></span>
      </div>
    `
    chatMessages.appendChild(typingDiv)
    chatMessages.scrollTop = chatMessages.scrollHeight
    
    if (window.lucide) window.lucide.createIcons()
  }
  
  // Legacy method - redirect to new implementation
  showAgentChat(agentId, agentName) {
    this.startAgentDm(agentId, agentName)
  }

  async startDmWithAgent_legacy(agentId, agentName) {
    try {
      const response = await fetch('/hub/dms', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ agent_id: agentId })
      })
      
      if (response.ok) {
        const data = await response.json()
        console.log("🌐 DM created/found:", data)
        
        // For now, show placeholder
        this.activeTypeValue = "dm"
        this.activeThreadValue = data.thread_id
        this.highlightActive()
        this.updateChatContext(agentName, "AI Agent", "bot")
        this.showDmPlaceholder(agentName, true)
      }
    } catch (error) {
      console.error("🌐 Error starting DM:", error)
      this.showNotification("Couldn't start DM. Try again.", "error")
    }
  }

  showNotification(message, type = "info") {
    // Use existing notification system if available
    if (window.showNotification) {
      window.showNotification(message, type)
      return
    }
    
    // Simple fallback
    const notification = document.createElement('div')
    notification.className = `hub-notification hub-notification-${type}`
    notification.innerHTML = `
      <i data-lucide="${type === 'error' ? 'alert-circle' : 'info'}"></i>
      <span>${message}</span>
    `
    notification.style.cssText = `
      position: fixed;
      bottom: 20px;
      left: 50%;
      transform: translateX(-50%);
      padding: 12px 20px;
      background: ${type === 'error' ? '#ef4444' : '#3b82f6'};
      color: white;
      border-radius: 8px;
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 14px;
      z-index: 9999;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3);
    `
    document.body.appendChild(notification)
    
    if (window.lucide) {
      window.lucide.createIcons()
    }
    
    setTimeout(() => notification.remove(), 3000)
  }

  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }
}
