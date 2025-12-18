import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

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
    this.threadSubscription = null
  }
  
  disconnect() {
    this.unsubscribeFromThread()
  }
  
  // Subscribe to a thread for real-time updates
  subscribeToThread(threadId) {
    // Unsubscribe from any existing thread
    this.unsubscribeFromThread()
    
    console.log("🌐 Subscribing to Hub thread:", threadId)
    
    this.threadSubscription = consumer.subscriptions.create(
      { channel: "HubChannel", thread_id: threadId },
      {
        connected: () => {
          console.log("🌐 Connected to Hub thread:", threadId)
        },
        disconnected: () => {
          console.log("🌐 Disconnected from Hub thread:", threadId)
        },
        received: (data) => {
          console.log("🌐 Received from Hub thread:", data)
          this.handleThreadMessage(data)
        }
      }
    )
  }
  
  unsubscribeFromThread() {
    if (this.threadSubscription) {
      this.threadSubscription.unsubscribe()
      this.threadSubscription = null
      console.log("🌐 Unsubscribed from Hub thread")
    }
  }
  
  handleThreadMessage(data) {
    switch (data.type) {
      case 'new_message':
        this.addReceivedMessage(data.message)
        break
      case 'typing':
        this.showRemoteTyping(data)
        break
      case 'stop_typing':
        this.hideRemoteTyping(data)
        break
      default:
        console.log("🌐 Unknown message type:", data.type)
    }
  }
  
  addReceivedMessage(message) {
    const chatMessages = document.getElementById('chat-messages')
    if (!chatMessages) return

    // Check if we already have this message displayed (by ID)
    const messageId = message.id
    if (messageId && chatMessages.querySelector(`[data-message-id="${messageId}"]`)) {
      console.log("🌐 Skipping duplicate message ID:", messageId)
      return
    }

    // Don't add our own messages (we already added them optimistically)
    // Handle both nested sender object (from broadcast) and flat fields (from API)
    const senderId = message.sender?.id || message.sender_id
    const senderType = message.sender?.type || message.sender_type
    const currentUserId = this.getCurrentUserId()

    console.log("🌐 Message check - senderId:", senderId, "senderType:", senderType, "currentUserId:", currentUserId)

    // Compare as numbers to avoid string/number mismatch
    if (senderType === 'User' && senderId && currentUserId && parseInt(senderId) === parseInt(currentUserId)) {
      console.log("🌐 Skipping own message (sender matches current user)")
      // Update the temp message with real ID if it exists
      const tempMessage = chatMessages.querySelector('.hub-message.sending')
      if (tempMessage && messageId) {
        tempMessage.dataset.messageId = messageId
        tempMessage.classList.remove('sending')
        tempMessage.querySelector('.hub-sending-indicator')?.remove()
      }
      return
    }
    
    // Remove typing indicator if present
    chatMessages.querySelector('.hub-typing-indicator')?.remove()
    
    let messagesList = chatMessages.querySelector('.hub-messages-list')
    
    // Create list if it doesn't exist
    if (!messagesList) {
      // Replace welcome message with messages list
      chatMessages.innerHTML = '<div class="hub-messages-list"></div>'
      messagesList = chatMessages.querySelector('.hub-messages-list')
    }
    
    // Add the new message
    const html = this.renderMessage({
      id: message.id,
      content: message.content,
      sender_type: message.sender_type || message.sender?.type,
      sender_name: message.sender_name || message.sender?.name,
      created_at: message.created_at || new Date().toISOString()
    })
    
    messagesList.insertAdjacentHTML('beforeend', html)
    
    // Scroll to bottom
    chatMessages.scrollTop = chatMessages.scrollHeight
    
    if (window.lucide) window.lucide.createIcons()
    
    console.log("🌐 Added received message from:", message.sender_name || message.sender?.name)
  }
  
  getCurrentUserId() {
    // Try to get current user ID from meta tag or data attribute
    const meta = document.querySelector('meta[name="current-user-id"]')
    if (meta) return parseInt(meta.content)
    
    const body = document.body
    if (body.dataset.userId) return parseInt(body.dataset.userId)
    
    return null
  }
  
  showRemoteTyping(data) {
    // Don't show typing indicator for our own typing
    if (data.user_id === this.getCurrentUserId()) return
    
    const chatMessages = document.getElementById('chat-messages')
    if (!chatMessages) return
    
    // Check if already showing
    if (chatMessages.querySelector('.hub-typing-indicator')) return
    
    const typingDiv = document.createElement('div')
    typingDiv.className = 'hub-typing-indicator'
    typingDiv.dataset.userId = data.user_id
    typingDiv.innerHTML = `
      <div class="hub-message-avatar hub-avatar-agent">
        <i data-lucide="bot"></i>
      </div>
      <span>${data.user_name || 'Agent'} is typing...</span>
      <div class="hub-typing-dots">
        <span></span><span></span><span></span>
      </div>
    `
    chatMessages.appendChild(typingDiv)
    chatMessages.scrollTop = chatMessages.scrollHeight
    
    if (window.lucide) window.lucide.createIcons()
  }
  
  hideRemoteTyping(data) {
    const chatMessages = document.getElementById('chat-messages')
    chatMessages?.querySelector(`.hub-typing-indicator[data-user-id="${data.user_id}"]`)?.remove()
  }

  // Select Amos (main AI chat) - this is the default Scout chat
  // Amos conversations persist across all spaces - he's your chief of staff
  selectAmos(event) {
    event.preventDefault()
    this.activeTypeValue = "amos"
    this.activeThreadValue = ""
    this.currentMode = 'amos' // Reset mode so Scout handles messages
    this.currentChannelId = null
    this.currentThreadId = null

    this.highlightActive()
    this.updateChatContext("Amos", "Your AI assistant", "sparkles")

    // Remove channel/DM handlers and unsubscribe from thread
    this.removeChannelHandlers()
    this.unsubscribeFromThread()
    
    // Clear hub mode from chat messages so Scout can take over
    const chatMessages = document.getElementById('chat-messages')
    if (chatMessages) {
      delete chatMessages.dataset.hubMode
      delete chatMessages.dataset.channelId
      delete chatMessages.dataset.agentId
      
      // Load Scout/Amos history
      this.loadAmosHistory(chatMessages)
    }

    console.log("🌐 Selected Amos chat - loading persistent conversation")
  }
  
  async loadAmosHistory(chatMessages) {
    // Show loading state
    chatMessages.innerHTML = `
      <div class="hub-loading">
        <i data-lucide="loader" class="spin"></i>
        <span>Loading conversation...</span>
      </div>
    `
    if (window.lucide) window.lucide.createIcons()
    
    try {
      // Fetch Scout history
      const response = await fetch('/scout/history?limit=50', {
        headers: { 'Accept': 'application/json' }
      })
      
      if (!response.ok) throw new Error('Failed to load history')
      
      const data = await response.json()
      const messages = data.messages || []
      
      if (messages.length === 0) {
        // Show welcome message
        chatMessages.innerHTML = `
          <div class="hub-welcome-message">
            <div class="hub-welcome-icon">
              <i data-lucide="sparkles"></i>
            </div>
            <h3>Chat with Amos</h3>
            <p class="text-muted">Amos is your AI chief of staff. Ask him anything!</p>
          </div>
        `
      } else {
        // Render messages in Hub format
        this.renderAmosMessages(messages, chatMessages)
      }
      
      if (window.lucide) window.lucide.createIcons()
      
    } catch (error) {
      console.error("🌐 Error loading Amos history:", error)
      chatMessages.innerHTML = `
        <div class="hub-welcome-message">
          <div class="hub-welcome-icon">
            <i data-lucide="sparkles"></i>
          </div>
          <h3>Chat with Amos</h3>
          <p class="text-muted">Start a conversation with your AI assistant!</p>
        </div>
      `
      if (window.lucide) window.lucide.createIcons()
    }
  }
  
  renderAmosMessages(messages, chatMessages) {
    let html = '<div class="hub-messages-list">'
    let lastDate = null
    
    messages.forEach(msg => {
      const msgDate = new Date(msg.created_at).toLocaleDateString()
      if (msgDate !== lastDate) {
        html += `<div class="hub-date-divider"><span>${msgDate}</span></div>`
        lastDate = msgDate
      }
      
      const isAmos = msg.role === 'assistant'
      const time = new Date(msg.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
      const senderName = isAmos ? 'Amos' : 'You'
      const initial = isAmos ? '✨' : (senderName.charAt(0).toUpperCase() || 'U')
      
      html += `
        <div class="hub-message ${isAmos ? 'agent' : 'user'}" data-message-id="${msg.id}">
          <div class="hub-message-avatar ${isAmos ? 'agent' : 'user'}">
            ${isAmos ? '<i data-lucide="sparkles"></i>' : initial}
          </div>
          <div class="hub-message-content">
            <div class="hub-message-header">
              <span class="hub-message-sender">${senderName}</span>
              <span class="hub-message-time">${time}</span>
            </div>
            <div class="hub-message-text">${this.formatMessageContent(msg.content)}</div>
          </div>
        </div>
      `
    })
    
    html += '</div>'
    chatMessages.innerHTML = html
    chatMessages.scrollTop = chatMessages.scrollHeight
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
        
        // Get the thread ID from the channel data and subscribe
        if (data.thread_id) {
          this.currentThreadId = data.thread_id
          this.subscribeToThread(data.thread_id)
        }
        
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
    // Handle both flat format (sender_type) and nested format (sender.type)
    const senderType = msg.sender_type || msg.sender?.type
    const isAgent = senderType === 'AgentPlugin'
    const time = new Date(msg.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    
    // Get sender name from various possible sources (nested or flat)
    const senderName = msg.sender_name || msg.sender?.name || (isAgent ? 'Agent' : 'You')
    const initial = senderName.charAt(0)?.toUpperCase() || 'U'
    
    return `
      <div class="hub-message ${isAgent ? 'agent' : 'user'}" data-message-id="${msg.id}">
        <div class="hub-message-avatar ${isAgent ? 'agent' : 'user'}">
          ${isAgent ? '<i data-lucide="bot"></i>' : initial}
        </div>
        <div class="hub-message-content">
          <div class="hub-message-header">
            <span class="hub-message-sender">${senderName}</span>
            <span class="hub-message-time">${time}</span>
          </div>
          <div class="hub-message-text">${this.formatMessageContent(msg.content)}</div>
        </div>
      </div>
    `
  }
  
  formatMessageContent(content) {
    if (!content) return ''
    
    // Check for markdown images (GIFs) FIRST before escaping
    if (content.includes('![') && content.includes('](')) {
      // Extract and convert markdown images
      let html = content
      
      // Convert markdown images ![alt](url) to <img> tags
      html = html.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (match, alt, url) => {
        const isGif = url.toLowerCase().includes('.gif')
        if (isGif) {
          return `<div class="message-gif" style="max-width: 300px; border-radius: 0.5rem; overflow: hidden; margin: 0.5rem 0;">
                    <img src="${url}" alt="${alt}" style="width: 100%; display: block; border-radius: 0.5rem;">
                  </div>`
        } else {
          return `<img src="${url}" alt="${alt}" style="max-width: 100%; border-radius: 0.5rem; margin: 0.5rem 0;">`
        }
      })
      
      return html
    }
    
    // Regular text formatting
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
    
    // Get message content (text from input)
    let textContent = textarea.value.trim()
    
    // Check for pending Hub images (from paste)
    let finalContent = textContent;
    
    if (window.hubPendingImages && window.hubPendingImages.length > 0) {
      console.log('📸 Found pending images:', window.hubPendingImages.length);
      const imageMarkdown = window.hubPendingImages.map(img => img.markdown).join('\n');
      finalContent = textContent ? `${textContent}\n${imageMarkdown}` : imageMarkdown;
      
      // Clear pending images and preview
      window.hubPendingImages = [];
      const preview = document.querySelector('.hub-image-preview');
      if (preview) preview.remove();
    }
    
    if (!finalContent) {
      console.log('📸 No content to send');
      return;
    }
    
    console.log('📤 Sending message with content length:', finalContent.length);
    
    textarea.value = ''
    this.addOptimisticMessage(finalContent)
    
    try {
      const response = await fetch(`/hub/channels/${this.currentChannelId}/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ content: finalContent })
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
    if (!chatMessages) return
    
    // Track recently sent messages to prevent duplicates from websocket
    if (!this.recentlySentMessages) {
      this.recentlySentMessages = new Set()
    }
    this.recentlySentMessages.add(content)
    // Remove from set after 10 seconds
    setTimeout(() => {
      this.recentlySentMessages?.delete(content)
    }, 10000)
    
    let messagesList = chatMessages.querySelector('.hub-messages-list')

    // Create list if it doesn't exist (first message) - this clears any welcome banner
    if (!messagesList) {
      // Clear everything (including welcome banners) and create messages list
      chatMessages.innerHTML = '<div class="hub-messages-list"></div>'
      messagesList = chatMessages.querySelector('.hub-messages-list')
    }
    
    // Also remove any welcome messages that might be siblings
    chatMessages.querySelectorAll('.hub-welcome-message, .hub-channel-welcome, .hub-agent-chat-welcome').forEach(el => el.remove())
    
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

  // Select a DM (existing thread)
  async selectDm(event) {
    event.preventDefault()
    const threadId = event.currentTarget.dataset.threadId
    const participantName = event.currentTarget.querySelector('.hub-item-name')?.textContent || 'Unknown'
    const isAgent = event.currentTarget.querySelector('.hub-avatar-agent') !== null
    
    this.activeTypeValue = "dm"
    this.activeThreadValue = threadId
    this.currentThreadId = threadId
    this.currentMode = isAgent ? 'agent_dm' : 'user_dm'
    
    this.highlightActive()
    this.updateChatContext(participantName, isAgent ? "AI Agent" : "Team member", isAgent ? "bot" : "user")
    
    console.log("🌐 Selected DM:", threadId, participantName, isAgent)
    
    // Subscribe to the thread for real-time updates
    this.subscribeToThread(threadId)
    
    // Load the thread messages
    await this.loadThreadMessages(threadId, participantName)

    // Setup input handlers for this DM
    if (isAgent) {
      this.currentAgentName = participantName
      this.setupAgentDmInput()
    } else {
      // User-to-user DM
      this.currentUserName = participantName
      this.setupUserDmInput()
    }
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

  // Select a team member (start DM with human)
  async selectTeamMember(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const target = event.currentTarget
    const userId = target.dataset.userId
    const userName = target.dataset.userName || target.querySelector('.hub-item-name')?.textContent || 'Team Member'
    
    console.log("🌐 Starting DM with team member:", userId, userName)
    
    // Highlight the selected team member
    this.element.querySelectorAll('.hub-item.active').forEach(el => el.classList.remove('active'))
    target.classList.add('active')
    
    // Update chat context
    this.updateChatContext(userName, "Team Member", "user")
    
    // Set mode for routing messages
    this.currentMode = 'user_dm'
    this.currentUserId = userId
    this.currentUserName = userName
    
    // Create or find DM thread with this user
    await this.startUserDm(userId, userName)
  }

  // Start a DM with a user
  async startUserDm(userId, userName) {
    const chatMessages = document.getElementById('chat-messages')
    if (!chatMessages) return

    // Show loading state
    chatMessages.innerHTML = ''
    chatMessages.dataset.hubMode = 'user_dm'
    chatMessages.dataset.userId = userId

    chatMessages.innerHTML = `
      <div class="hub-loading">
        <i data-lucide="loader" class="spin"></i>
        <span>Loading conversation with ${userName}...</span>
      </div>
    `
    if (window.lucide) window.lucide.createIcons()

    try {
      // Create or find DM thread with this user
      const response = await fetch('/hub/dms', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({
          participant_type: 'User',
          participant_id: userId
        })
      })

      if (response.ok) {
        const data = await response.json()
        // API returns { success: true, thread: { id: ..., ... } }
        const threadId = data.thread?.id || data.thread_id
        
        if (!threadId) {
          console.error("🌐 No thread ID in response:", data)
          throw new Error('No thread ID returned')
        }
        
        // Store thread info
        this.currentThreadId = threadId
        this.currentThreadType = 'dm'
        
        // Load thread messages
        await this.loadThreadMessages(threadId, userName)
        
        // Setup input handlers
        this.setupUserDmInput()
      } else {
        throw new Error('Failed to create DM')
      }
    } catch (error) {
      console.error("🌐 Error starting user DM:", error)
      chatMessages.innerHTML = `
        <div class="hub-error">
          <i data-lucide="alert-circle"></i>
          <span>Couldn't start conversation. Please try again.</span>
        </div>
      `
      if (window.lucide) window.lucide.createIcons()
    }
  }

  // Setup input for user DMs
  setupUserDmInput() {
    this.currentMode = 'user_dm'
    
    const chatForm = document.getElementById('message-form')
    const textarea = document.getElementById('message-input')
    const sendButton = document.getElementById('send-button')

    if (!chatForm) return

    // Remove ALL old handlers (user and agent DM)
    this.removeUserDmHandlers()
    this.removeAgentDmHandlers()

    // Create bound handlers
    this.boundUserDmSubmit = (e) => this.handleUserDmSubmit(e)
    this.boundUserDmKeyHandler = (e) => this.handleUserDmKeydown(e)
    this.boundUserDmClickHandler = (e) => this.handleUserDmClick(e)

    // Add handlers with capture to intercept before Scout
    chatForm.addEventListener('submit', this.boundUserDmSubmit, true)
    textarea?.addEventListener('keydown', this.boundUserDmKeyHandler)
    sendButton?.addEventListener('click', this.boundUserDmClickHandler, true)

    // Update placeholder
    if (textarea) {
      textarea.placeholder = `Message ${this.currentUserName || 'team member'}...`
      textarea.disabled = false
      textarea.focus()
    }
    
    console.log("🌐 User DM input handlers set up for thread:", this.currentThreadId)
  }

  removeUserDmHandlers() {
    const chatForm = document.getElementById('message-form')
    const textarea = document.getElementById('message-input')
    const sendButton = document.getElementById('send-button')

    if (this.boundUserDmSubmit) {
      chatForm?.removeEventListener('submit', this.boundUserDmSubmit, true)
    }
    if (this.boundUserDmKeyHandler) {
      textarea?.removeEventListener('keydown', this.boundUserDmKeyHandler)
    }
    if (this.boundUserDmClickHandler) {
      sendButton?.removeEventListener('click', this.boundUserDmClickHandler, true)
    }
  }

  removeAgentDmHandlers() {
    const chatForm = document.getElementById('message-form')
    const textarea = document.getElementById('message-input')
    const sendButton = document.getElementById('send-button')

    if (this.boundAgentSubmit) {
      chatForm?.removeEventListener('submit', this.boundAgentSubmit, true)
      this.boundAgentSubmit = null
    }
    if (this.boundAgentKeydown) {
      textarea?.removeEventListener('keydown', this.boundAgentKeydown, true)
      this.boundAgentKeydown = null
    }
    if (this.boundAgentClick) {
      sendButton?.removeEventListener('click', this.boundAgentClick, true)
      this.boundAgentClick = null
    }
  }

  handleUserDmKeydown(event) {
    if (this.currentMode !== 'user_dm') return

    // Enter without shift sends message
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault()
      event.stopPropagation()
      this.sendUserDmMessage()
    }
  }

  handleUserDmClick(event) {
    if (this.currentMode !== 'user_dm') return

    event.preventDefault()
    event.stopPropagation()
    this.sendUserDmMessage()
  }

  handleUserDmSubmit(event) {
    if (this.currentMode !== 'user_dm' || !this.currentThreadId) return

    event.preventDefault()
    event.stopPropagation()
    this.sendUserDmMessage()
  }

  async sendUserDmMessage() {
    const textarea = document.getElementById('message-input')
    if (!textarea) return

    // Get message content (text from input)
    let textContent = textarea.value.trim()
    
    // Check for pending Hub images (from paste)
    let finalContent = textContent;
    
    if (window.hubPendingImages && window.hubPendingImages.length > 0) {
      console.log('📸 Found pending images for DM:', window.hubPendingImages.length);
      const imageMarkdown = window.hubPendingImages.map(img => img.markdown).join('\n');
      finalContent = textContent ? `${textContent}\n${imageMarkdown}` : imageMarkdown;
      
      // Clear pending images and preview
      window.hubPendingImages = [];
      const preview = document.querySelector('.hub-image-preview');
      if (preview) preview.remove();
    }
    
    if (!finalContent) {
      console.log('📸 No content to send in DM');
      return;
    }

    console.log("🌐 Sending user DM message to thread:", this.currentThreadId, "length:", finalContent.length)

    textarea.value = ''
    this.addOptimisticMessage(finalContent)

    try {
      const response = await fetch(`/hub/thread/${this.currentThreadId}/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ content: finalContent })
      })

      if (!response.ok) throw new Error('Failed to send')

      const data = await response.json()
      console.log("🌐 User DM message sent:", data)
      this.updateOptimisticMessage(data.message)
    } catch (error) {
      console.error("🌐 Error sending user DM:", error)
      this.showNotification("Couldn't send message", "error")
    }
  }

  // Invite a new team member
  inviteTeamMember(event) {
    event.preventDefault()
    event.stopPropagation()
    console.log("🌐 Invite team member clicked")
    
    // Open the business profile canvas with members tab
    if (window.scoutLoadCanvas) {
      window.scoutLoadCanvas('business_profile', { tab: 'members' })
    } else {
      // Fallback - navigate to business profile page
      window.location.href = '/business_profiles?tab=members'
    }
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

  // Start a new DM - scroll to team members or agents section
  startDm(event) {
    event.preventDefault()
    console.log("🌐 Start DM clicked - showing team members and agents")

    // First check for team members
    const teamMembersSection = this.element.querySelector('#hub-team-members')
    const agentsSection = this.element.querySelector('#hub-agents')
    
    // Prefer scrolling to team members if they exist, otherwise agents
    const targetSection = teamMembersSection?.children.length > 0 ? teamMembersSection : agentsSection
    
    if (targetSection) {
      targetSection.scrollIntoView({ behavior: 'smooth', block: 'center' })

      // Highlight the section briefly
      targetSection.style.background = 'rgba(124, 58, 237, 0.2)'
      setTimeout(() => {
        targetSection.style.background = ''
      }, 2000)

      this.showNotification("Click on a team member or agent to start a conversation", "info")
    } else {
      this.showNotification("No team members or agents available yet.", "info")
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
    // Find elements globally since they're outside this controller's element
    const chatContext = document.querySelector('[data-hub-sidebar-target="chatContext"]') || 
                        document.querySelector('.hub-chat-context')
    const chatTitle = document.querySelector('[data-hub-sidebar-target="chatTitle"]') ||
                      document.querySelector('.chat-header-title')
    const chatSubtitle = document.querySelector('[data-hub-sidebar-target="chatSubtitle"]') ||
                         document.querySelector('.hub-chat-subtitle')
    
    if (chatTitle) {
      chatTitle.textContent = title
    }
    if (chatSubtitle) {
      chatSubtitle.textContent = subtitle
    }
    if (chatContext) {
      const avatarIcon = chatContext.querySelector('.hub-chat-avatar i')
      if (avatarIcon) {
        avatarIcon.setAttribute('data-lucide', icon)
        // Re-render lucide icons
        if (window.lucide) {
          window.lucide.createIcons()
        }
      }
    }
    
    console.log("🌐 Updated chat context:", title, subtitle, icon)
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
    // Legacy - redirect to proper welcome message
    const chatMessages = document.getElementById('chat-messages')
    if (chatMessages) {
      chatMessages.innerHTML = `
        <div class="hub-agent-chat-welcome">
          <div class="hub-welcome-icon">
            <i data-lucide="${isAgent ? 'bot' : 'user'}"></i>
          </div>
          <h3>Chat with ${participantName}</h3>
          <p class="text-muted">Start your conversation with ${participantName}.</p>
          <p class="text-muted small">Send a message to get started!</p>
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
      
      // Subscribe to the thread for real-time updates (agent responses)
      this.subscribeToThread(data.thread.id)
      
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
    
    // Ensure hub mode is set to prevent Scout from loading history
    // Preserve current mode if already set (user_dm, agent_dm), otherwise use 'thread'
    if (!chatMessages.dataset.hubMode || chatMessages.dataset.hubMode === 'scout' || chatMessages.dataset.hubMode === 'amos') {
      chatMessages.dataset.hubMode = this.currentMode || 'thread'
    }
    chatMessages.dataset.threadId = threadId
    
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
    
    // Remove ALL existing handlers (channel, user DM, old agent DM)
    this.removeChannelHandlers()
    this.removeUserDmHandlers()
    this.removeAgentDmHandlers()
    
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
    
    // Check for attached files (from Scout's file handling)
    const attachedFilesContainer = document.getElementById('attached-files')
    
    // Get attachedFiles from global scope (set by Scout's file handling)
    const attachedFiles = window.attachedFiles || []
    
    if (!content && attachedFiles.length === 0) {
      console.warn("🌐 No content or files for agent DM")
      return
    }
    
    if (!this.currentThreadId) {
      console.warn("🌐 No thread ID for agent DM")
      return
    }
    
    const finalMessage = content || 'Please process these files'
    
    // If there are files, show the storage choice modal
    if (attachedFiles.length > 0) {
      console.log("🌐 Files attached, showing storage choice modal")
      this.showStorageModalForAgent(finalMessage, attachedFiles, attachedFilesContainer)
      return
    }
    
    // No files - send directly
    await this.sendAgentMessage(finalMessage, [], attachedFilesContainer)
  }
  
  showStorageModalForAgent(message, files, container) {
    const modalElement = document.getElementById('document-storage-modal')
    
    if (!modalElement) {
      console.warn("🌐 Storage modal not found, defaulting to long-term")
      this.sendAgentMessageWithFiles(message, files, container, 'long-term')
      return
    }
    
    // Store context for callback
    const self = this
    const filesCopy = [...files] // Clone the array
    
    // Use the same pendingFileUpload mechanism as Scout
    // This will be called by the existing Scout confirm handler
    window.pendingFileUpload = async function() {
      // Get the storage choice that Scout's handler set
      const storageChoice = window.documentStorageChoice || 'long-term'
      console.log("🌐 Hub upload proceeding with storage:", storageChoice)
      
      // Process the upload
      await self.sendAgentMessageWithFiles(message, filesCopy, container, storageChoice)
      
      // Cleanup
      window.pendingFileUpload = null
    }
    
    // Show the modal - Scout's existing handlers will manage it
    try {
      const storageModal = new bootstrap.Modal(modalElement)
      storageModal.show()
      console.log("🌐 Storage modal shown for Hub upload")
      
    } catch (error) {
      console.error("🌐 Failed to show storage modal:", error)
      // Fallback to long-term
      window.pendingFileUpload = null
      this.sendAgentMessageWithFiles(message, files, container, 'long-term')
    }
  }
  
  async sendAgentMessageWithFiles(message, files, container, storageType) {
    const textarea = document.getElementById('message-input')
    
    console.log("🌐 Sending to agent with", files.length, "files, storage:", storageType)
    
    // Clear input
    if (textarea) {
      textarea.value = ''
      textarea.style.height = 'auto'
    }
    
    // Add optimistic message
    const displayContent = `${message} [${files.length} file(s) attached]`
    this.addOptimisticMessage(displayContent, 'You')
    
    try {
      // Upload files
      console.log("🌐 Uploading", files.length, "files...")
      const fileUrls = await this.uploadFilesForAgent(files, storageType)
      console.log("🌐 File upload complete:", fileUrls)
      
      // Send the message
      await this.sendAgentMessage(message, fileUrls, container)
      
      // Clear attached files after sending
      if (window.attachedFiles) {
        window.attachedFiles.length = 0
      }
      if (container) {
        container.innerHTML = ''
        container.classList.add('d-none')
      }
      
    } catch (error) {
      console.error("🌐 Error sending with files:", error)
      this.showMessageError(message)
    }
  }
  
  async sendAgentMessage(message, fileUrls = [], container = null) {
    const textarea = document.getElementById('message-input')
    
    // Clear input if not already cleared
    if (textarea && textarea.value) {
      textarea.value = ''
      textarea.style.height = 'auto'
    }
    
    // Add optimistic message if no files (files case already added)
    if (fileUrls.length === 0) {
      this.addOptimisticMessage(message, 'You')
    }
    
    console.log("🌐 Sending to agent thread:", this.currentThreadId, message)
    
    try {
      // Build message payload
      const payload = { 
        content: message,
        attachments: fileUrls.map(url => ({ type: 'file', url: url }))
      }
      
      const response = await fetch(`/hub/thread/${this.currentThreadId}/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify(payload)
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
      this.showMessageError(message)
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

  async uploadFilesForAgent(files, storageType = 'long-term') {
    console.log("🌐 Uploading", files.length, "files for agent, storage:", storageType)
    
    const formData = new FormData()
    files.forEach((file, index) => {
      formData.append(`files[${index}]`, file)
    })
    
    // Use specified storage type
    formData.append('storage_type', storageType)
    
    try {
      const response = await fetch('/scout/upload_files', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: formData
      })
      
      if (!response.ok) {
        throw new Error('File upload failed')
      }
      
      const data = await response.json()
      console.log("🌐 Upload response:", data)
      
      // Extract just the URL strings from the response
      // Response format: [{url: "http://...", filename: "...", ...}]
      const urls = data.urls || data.file_urls || []
      return urls.map(item => {
        if (typeof item === 'string') return item
        return item.url || item
      })
      
    } catch (error) {
      console.error("🌐 File upload error:", error)
      return []
    }
  }

  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }
}
