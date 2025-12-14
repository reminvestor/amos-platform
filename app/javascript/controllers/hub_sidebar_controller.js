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
    
    this.highlightActive()
    this.updateChatContext("Amos", "Your AI assistant", "sparkles")
    
    // Amos chat is already the Scout chat, so no navigation needed
    // Just ensure we're in conversation mode
    if (window.scoutController) {
      window.scoutController.goToConversation()
    }
    
    console.log("🌐 Selected Amos chat")
  }

  // Select a channel
  selectChannel(event) {
    event.preventDefault()
    const channelId = event.currentTarget.dataset.channelId
    const channelName = event.currentTarget.querySelector('.hub-item-name')?.textContent || 'Channel'
    
    this.activeTypeValue = "channel"
    this.activeThreadValue = channelId
    
    this.highlightActive()
    this.updateChatContext(`#${channelName}`, "Team channel", "hash")
    
    // TODO: Load channel messages
    console.log("🌐 Selected channel:", channelId)
    this.showChannelPlaceholder(channelName)
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
  selectAgent(event) {
    event.preventDefault()
    const agentId = event.currentTarget.dataset.agentId
    const agentName = event.currentTarget.querySelector('.hub-item-name')?.textContent || 'Agent'
    
    console.log("🌐 Starting DM with agent:", agentId, agentName)
    
    // Create or find DM with this agent
    this.startDmWithAgent(agentId, agentName)
  }

  // Create a new channel
  createChannel(event) {
    event.preventDefault()
    // TODO: Show channel creation modal
    console.log("🌐 Create channel clicked")
    this.showNotification("Channel creation coming soon!", "info")
  }

  // Start a new DM
  startDm(event) {
    event.preventDefault()
    // TODO: Show DM picker modal
    console.log("🌐 Start DM clicked")
    this.showNotification("Select an agent from the Agents section to start a DM", "info")
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

  showChannelPlaceholder(channelName) {
    const chatMessages = document.getElementById('chat-messages')
    if (chatMessages) {
      chatMessages.innerHTML = `
        <div class="hub-placeholder">
          <div class="hub-placeholder-icon">
            <i data-lucide="hash"></i>
          </div>
          <h3>#${channelName}</h3>
          <p>Channel messaging coming soon. For now, continue chatting with Amos!</p>
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

  async startDmWithAgent(agentId, agentName) {
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
