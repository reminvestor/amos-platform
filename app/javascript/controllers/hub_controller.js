import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = [
    "search",
    "agentActivity", 
    "threadHeader",
    "messagesContainer",
    "inputContainer",
    "messageInput",
    "messageTextarea",
    "attachmentPreviews",
    "typingIndicator",
    "threadDetails",
    "dmRecipient",
    "dmMessage"
  ]

  static values = {
    entityId: Number,
    currentThreadId: Number
  }

  connect() {
    console.log("Hub controller connected")
    this.subscribeToEntity()
    this.scrollToBottom()
    this.setupPresenceHeartbeat()
  }

  disconnect() {
    if (this.entitySubscription) {
      this.entitySubscription.unsubscribe()
    }
    if (this.threadSubscription) {
      this.threadSubscription.unsubscribe()
    }
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval)
    }
  }

  // ============================================
  // SUBSCRIPTIONS
  // ============================================

  subscribeToEntity() {
    this.entitySubscription = consumer.subscriptions.create(
      { channel: "HubChannel", entity_id: this.entityIdValue },
      {
        received: (data) => this.handleEntityMessage(data),
        connected: () => console.log("Connected to Hub entity channel"),
        disconnected: () => console.log("Disconnected from Hub entity channel")
      }
    )
  }

  subscribeToThread(threadId) {
    if (this.threadSubscription) {
      this.threadSubscription.unsubscribe()
    }

    this.currentThreadIdValue = threadId

    this.threadSubscription = consumer.subscriptions.create(
      { channel: "HubChannel", thread_id: threadId },
      {
        received: (data) => this.handleThreadMessage(data),
        connected: () => console.log(`Connected to Hub thread ${threadId}`),
        disconnected: () => console.log(`Disconnected from Hub thread ${threadId}`)
      }
    )
  }

  // ============================================
  // MESSAGE HANDLERS
  // ============================================

  handleEntityMessage(data) {
    switch (data.type) {
      case "presence_update":
        this.updatePresence(data)
        break
      case "agent_activity":
        this.updateAgentActivity(data)
        break
      case "new_thread":
        this.handleNewThread(data)
        break
      case "handoff_request":
        this.handleHandoffRequest(data)
        break
    }
  }

  handleThreadMessage(data) {
    switch (data.type) {
      case "new_message":
        this.appendMessage(data.message)
        break
      case "typing":
        this.showTypingIndicator(data)
        break
      case "stop_typing":
        this.hideTypingIndicator(data)
        break
      case "reaction_update":
        this.updateReactions(data)
        break
    }
  }

  // ============================================
  // NAVIGATION
  // ============================================

  loadChannel(event) {
    event.preventDefault()
    const channelId = event.currentTarget.dataset.channelId
    this.fetchAndLoadChannel(channelId)
  }

  loadThread(event) {
    event.preventDefault()
    const threadId = event.currentTarget.dataset.threadId
    this.fetchAndLoadThread(threadId)
  }

  async fetchAndLoadChannel(channelId) {
    try {
      const response = await fetch(`/hub/channel/${channelId}`, {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()
      this.renderThread(data)
    } catch (error) {
      console.error("Failed to load channel:", error)
    }
  }

  async fetchAndLoadThread(threadId) {
    try {
      const response = await fetch(`/hub/thread/${threadId}`, {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()
      this.renderThread(data)
      this.subscribeToThread(threadId)
    } catch (error) {
      console.error("Failed to load thread:", error)
    }
  }

  renderThread(data) {
    // Update header
    this.updateThreadHeader(data)
    
    // Render messages
    this.renderMessages(data.messages)
    
    // Update input
    this.updateMessageInput(data)
    
    // Update sidebar active state
    this.updateSidebarActiveState(data.id)
    
    // Subscribe to thread updates
    this.subscribeToThread(data.id)
    
    // Scroll to bottom
    this.scrollToBottom()
  }

  // ============================================
  // MESSAGING
  // ============================================

  async sendMessage(event) {
    event.preventDefault()
    
    const threadId = event.currentTarget.dataset.threadId || this.currentThreadIdValue
    const content = this.messageTextareaTarget.value.trim()
    
    if (!content) return

    try {
      const response = await fetch(`/hub/thread/${threadId}/messages`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ content, message_type: "text" })
      })

      if (response.ok) {
        this.messageTextareaTarget.value = ""
        this.autoResize()
      } else {
        console.error("Failed to send message")
      }
    } catch (error) {
      console.error("Error sending message:", error)
    }
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.sendMessage(event)
    }
  }

  autoResize() {
    const textarea = this.messageTextareaTarget
    textarea.style.height = "auto"
    textarea.style.height = Math.min(textarea.scrollHeight, 200) + "px"
  }

  appendMessage(message) {
    const container = this.messagesContainerTarget
    const messageHtml = this.buildMessageHtml(message)
    container.insertAdjacentHTML("beforeend", messageHtml)
    this.scrollToBottom()
  }

  buildMessageHtml(message) {
    const isFromCurrentUser = message.sender.type === "User" && message.sender.id === this.currentUserId
    const isFromAgent = message.sender.type === "AgentPlugin"
    const bubbleClass = isFromCurrentUser ? "from-user" : (isFromAgent ? "from-agent" : "from-other")
    
    return `
      <div class="message-wrapper mb-3 d-flex ${isFromCurrentUser ? 'flex-row-reverse' : ''}" id="message-${message.id}">
        <div class="message-avatar me-2 ${isFromCurrentUser ? 'ms-2 me-0' : ''}">
          ${isFromAgent ? 
            '<span class="d-inline-flex align-items-center justify-content-center rounded-circle bg-primary text-white" style="width: 36px; height: 36px; font-size: 18px;">🤖</span>' :
            `<span class="d-inline-flex align-items-center justify-content-center rounded-circle bg-secondary text-white" style="width: 36px; height: 36px;">${message.sender.name[0].toUpperCase()}</span>`
          }
        </div>
        <div class="message-content">
          ${!isFromCurrentUser ? `
            <div class="message-meta mb-1">
              <span class="fw-semibold small">${message.sender.name}</span>
              ${isFromAgent ? '<span class="badge bg-primary-subtle text-primary ms-1" style="font-size: 0.65rem;">Agent</span>' : ''}
              <span class="text-muted small ms-2">${this.formatTime(message.created_at)}</span>
            </div>
          ` : ''}
          <div class="message-bubble p-3 ${bubbleClass}" style="position: relative;">
            <div class="message-text" style="user-select: text;">${this.escapeHtml(message.content)}</div>
            ${message.needs_response && !isFromCurrentUser ? `
              <div class="needs-response mt-2 d-flex align-items-center gap-2 text-warning">
                <i class="bi bi-hourglass-split"></i>
                <span class="small">Waiting for your response</span>
              </div>
            ` : ''}
            <button class="btn btn-sm copy-message-btn" title="Copy message"
              data-action="click->hub#copyMessage"
              data-content="${this.escapeAttr(message.content)}"
              style="position: absolute; top: 4px; right: 4px; opacity: 0; transition: opacity 0.15s; padding: 2px 6px; font-size: 0.75rem; background: var(--bg-secondary, #f0f0f0); border: 1px solid var(--border-primary, #ddd); border-radius: 4px; cursor: pointer;">
              <i class="bi bi-clipboard"></i>
            </button>
          </div>
          ${isFromCurrentUser ? `
            <div class="text-end">
              <span class="text-muted small">${this.formatTime(message.created_at)}</span>
            </div>
          ` : ''}
        </div>
      </div>
    `
  }

  // ============================================
  // DM CREATION
  // ============================================

  showNewDmModal() {
    const modal = new bootstrap.Modal(document.getElementById("newDmModal"))
    modal.show()
  }

  async createDm() {
    const recipientValue = this.dmRecipientTarget.value
    const [participantType, participantId] = recipientValue.split(":")
    const message = this.dmMessageTarget?.value || ""

    try {
      const response = await fetch("/hub/dms", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          participant_type: participantType,
          participant_id: parseInt(participantId),
          message: message
        })
      })

      if (response.ok) {
        const data = await response.json()
        bootstrap.Modal.getInstance(document.getElementById("newDmModal")).hide()
        this.fetchAndLoadThread(data.thread.id)
      }
    } catch (error) {
      console.error("Failed to create DM:", error)
    }
  }

  // ============================================
  // HANDOFF ACTIONS
  // ============================================

  async acceptHandoff(event) {
    const messageId = event.currentTarget.dataset.messageId
    
    try {
      const response = await fetch(`/hub/messages/${messageId}/handoff_action`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ action_id: "approve" })
      })

      if (response.ok) {
        // Refresh the thread to show updated state
        this.fetchAndLoadThread(this.currentThreadIdValue)
      }
    } catch (error) {
      console.error("Failed to accept handoff:", error)
    }
  }

  discussHandoff(event) {
    // Focus the message input to start a discussion
    this.messageTextareaTarget.focus()
    this.messageTextareaTarget.placeholder = "Discuss the handoff..."
  }

  // ============================================
  // REACTIONS
  // ============================================

  async toggleReaction(event) {
    const messageId = event.currentTarget.dataset.messageId
    const emoji = event.currentTarget.dataset.emoji

    try {
      await fetch(`/hub/messages/${messageId}/react`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ emoji })
      })
    } catch (error) {
      console.error("Failed to toggle reaction:", error)
    }
  }

  // ============================================
  // PRESENCE & ACTIVITY
  // ============================================

  setupPresenceHeartbeat() {
    // Send heartbeat every 30 seconds
    this.heartbeatInterval = setInterval(() => {
      fetch("/hub/heartbeat", {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.csrfToken
        }
      }).catch(console.error)
    }, 30000)
  }

  updatePresence(data) {
    // Update presence indicators in sidebar
    const indicator = document.querySelector(`[data-participant-id="${data.participant_id}"] .presence-indicator`)
    if (indicator) {
      indicator.className = `presence-indicator ${this.presenceClass(data.status)}`
    }
  }

  updateAgentActivity(data) {
    if (this.hasAgentActivityTarget) {
      // Could refresh the agent activity section
      // For now, just log
      console.log("Agent activity update:", data)
    }
  }

  presenceClass(status) {
    switch (status) {
      case "online": return "online"
      case "away": return "away"
      case "busy":
      case "working":
      case "thinking": return "busy"
      default: return "offline"
    }
  }

  // ============================================
  // TYPING INDICATORS
  // ============================================

  showTypingIndicator(data) {
    if (this.hasTypingIndicatorTarget) {
      this.typingIndicatorTarget.classList.remove("d-none")
      this.typingIndicatorTarget.querySelector(".typing-text").textContent = 
        `${data.user_name} is typing...`
    }
  }

  hideTypingIndicator(data) {
    if (this.hasTypingIndicatorTarget) {
      this.typingIndicatorTarget.classList.add("d-none")
    }
  }

  // ============================================
  // UTILITIES
  // ============================================

  scrollToBottom() {
    if (this.hasMessagesContainerTarget) {
      const container = this.messagesContainerTarget
      container.scrollTop = container.scrollHeight
    }
  }

  updateSidebarActiveState(threadId) {
    document.querySelectorAll(".sidebar-item").forEach(item => {
      item.classList.remove("active")
    })
    const activeItem = document.querySelector(`[data-thread-id="${threadId}"]`)
    if (activeItem) {
      activeItem.classList.add("active")
    }
  }

  formatTime(isoString) {
    const date = new Date(isoString)
    return date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML.replace(/\n/g, "<br>")
  }

  escapeAttr(text) {
    return text.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/'/g, "&#39;").replace(/`/g, "&#96;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  async copyMessage(event) {
    const btn = event.currentTarget
    const content = btn.dataset.content
    try {
      await navigator.clipboard.writeText(content)
      const icon = btn.querySelector("i")
      icon.className = "bi bi-check"
      setTimeout(() => { icon.className = "bi bi-clipboard" }, 1500)
    } catch {
      // Fallback for older browsers
      const textarea = document.createElement("textarea")
      textarea.value = content
      textarea.style.position = "fixed"
      textarea.style.opacity = "0"
      document.body.appendChild(textarea)
      textarea.select()
      document.execCommand("copy")
      document.body.removeChild(textarea)
      const icon = btn.querySelector("i")
      icon.className = "bi bi-check"
      setTimeout(() => { icon.className = "bi bi-clipboard" }, 1500)
    }
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ''
  }

  get currentUserId() {
    return parseInt(document.querySelector("meta[name='current-user-id']")?.content || "0")
  }

  updateThreadHeader(data) {
    // This would update the header based on the loaded thread
    // For now, rely on the partial render
  }

  renderMessages(messages) {
    if (!this.hasMessagesContainerTarget) return
    
    const container = this.messagesContainerTarget
    container.innerHTML = ""
    
    messages.forEach(message => {
      container.insertAdjacentHTML("beforeend", this.buildMessageHtml(message))
    })
  }

  updateMessageInput(data) {
    // Update the message input placeholder, etc.
  }

  handleNewThread(data) {
    // A new thread was created - could update sidebar
    console.log("New thread:", data)
  }

  handleHandoffRequest(data) {
    // A handoff request came in - show notification
    this.showNotification("Handoff Request", `${data.message.sender.name} needs your input`)
    
    // If we're in the thread, scroll to show it
    if (data.thread_id === this.currentThreadIdValue) {
      this.appendMessage(data.message)
    }
  }

  showNotification(title, body) {
    if ("Notification" in window && Notification.permission === "granted") {
      new Notification(title, { body })
    }
  }

  // Search functionality
  search(event) {
    const query = event.target.value.toLowerCase()
    // Filter sidebar items
    document.querySelectorAll(".sidebar-item").forEach(item => {
      const text = item.textContent.toLowerCase()
      item.style.display = text.includes(query) ? "" : "none"
    })
  }

  showAgentsList() {
    this.showNewDmModal()
  }

  showAttachmentPicker() {
    // Show file picker - placeholder
    console.log("Attachment picker")
  }

  focusResponse() {
    this.messageTextareaTarget.focus()
  }
}
