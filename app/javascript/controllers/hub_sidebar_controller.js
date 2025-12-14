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
    
    // For now, show placeholder - will integrate with actual agent chat later
    this.showAgentChat(agentId, agentName)
  }

  // Create a new channel
  createChannel(event) {
    event.preventDefault()
    event.stopPropagation()
    console.log("🌐 Create channel clicked")
    
    // Show a simple prompt for now
    const channelName = prompt("Enter channel name:")
    if (channelName && channelName.trim()) {
      this.createChannelRequest(channelName.trim())
    }
  }
  
  async createChannelRequest(name) {
    try {
      const response = await fetch('/hub/channels', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ name: name })
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

  showAgentChat(agentId, agentName) {
    const chatMessages = document.getElementById('chat-messages')
    if (chatMessages) {
      chatMessages.innerHTML = `
        <div class="hub-agent-chat-welcome">
          <div class="hub-welcome-icon">
            <i data-lucide="bot"></i>
          </div>
          <h3>Chat with ${agentName}</h3>
          <p class="text-muted">This is the beginning of your conversation with ${agentName}.</p>
          <p class="text-muted small">Agent-specific conversations coming soon! For now, you can chat with Amos who can delegate tasks to this agent.</p>
          <button class="btn btn-primary btn-sm mt-3" onclick="document.querySelector('[data-thread-type=amos]').click()">
            <i data-lucide="sparkles" class="me-2"></i>
            Chat with Amos instead
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
