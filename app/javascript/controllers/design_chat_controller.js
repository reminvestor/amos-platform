import { Controller } from "@hotwired/stimulus"

/**
 * Design Chat Controller
 * Manages the agent selector in the chat header for Design Mode
 * Loads agent-specific conversation history when switching
 */
export default class extends Controller {
  static targets = ["agentName"]
  static values = {
    currentAgent: { type: String, default: "amos" }
  }

  connect() {
    console.log("🎨 Design Chat controller connected")
    
    // Restore last selected agent
    const savedAgent = localStorage.getItem('designChat_currentAgent')
    if (savedAgent && savedAgent !== 'amos') {
      this.currentAgentValue = savedAgent
      // Update UI to show saved agent
      const agentItem = this.element.querySelector(`[data-agent-slug="${savedAgent}"]`)
      if (agentItem) {
        const agentName = agentItem.querySelector('span')?.textContent || savedAgent
        this.updateAgentDisplay(savedAgent, agentName)
      }
    }
  }

  selectAgent(event) {
    event?.preventDefault()
    event?.stopPropagation()
    
    const item = event.currentTarget
    const agentSlug = item.dataset.agentSlug
    const agentId = item.dataset.agentId
    const agentName = item.querySelector('span')?.textContent || 'Amos'
    
    // Don't reload if same agent
    if (agentSlug === this.currentAgentValue) {
      this.closeDropdown()
      return
    }
    
    // Update active state
    this.element.querySelectorAll('.dropdown-item').forEach(el => {
      el.classList.toggle('active', el === item)
    })
    
    // Update display
    this.updateAgentDisplay(agentSlug, agentName)
    
    // Close dropdown
    this.closeDropdown()
    
    // Save selection
    this.currentAgentValue = agentSlug
    localStorage.setItem('designChat_currentAgent', agentSlug)
    
    // Load conversation history for this agent
    this.loadAgentConversation(agentSlug, agentId, agentName)
    
    console.log("🎨 Selected agent:", agentSlug)
  }
  
  updateAgentDisplay(agentSlug, agentName) {
    // Update the button display
    if (this.hasAgentNameTarget) {
      this.agentNameTarget.textContent = agentName
    }
    
    // Update avatar icon
    const avatarIcon = this.element.querySelector('.agent-avatar-sm i')
    if (avatarIcon) {
      avatarIcon.setAttribute('data-lucide', agentSlug === 'amos' ? 'sparkles' : 'bot')
      if (typeof lucide !== 'undefined') {
        lucide.createIcons()
      }
    }
  }
  
  closeDropdown() {
    const dropdown = this.element.querySelector('.agent-dropdown-inline')
    if (dropdown) dropdown.style.display = 'none'
  }
  
  async loadAgentConversation(agentSlug, agentId, agentName) {
    console.log("📜 Loading conversation for agent:", agentSlug)
    
    const chatMessages = document.querySelector('.chat-messages')
    if (!chatMessages) return
    
    // Show loading state
    chatMessages.innerHTML = `
      <div class="loading-conversation" style="display: flex; align-items: center; justify-content: center; height: 100%; color: var(--text-muted);">
        <i data-lucide="loader-2" style="animation: spin 1s linear infinite; width: 24px; height: 24px;"></i>
        <span style="margin-left: 0.5rem;">Loading conversation...</span>
      </div>
    `
    if (typeof lucide !== 'undefined') lucide.createIcons()
    
    try {
      if (agentSlug === 'amos') {
        // Load Amos conversation (main thread)
        await this.loadAmosConversation()
      } else {
        // Load agent-specific conversation
        await this.loadAgentHistory(agentId, agentName)
      }
    } catch (error) {
      console.error("Failed to load conversation:", error)
      chatMessages.innerHTML = `
        <div class="empty-conversation" style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: var(--text-muted);">
          <i data-lucide="message-circle" style="width: 32px; height: 32px; opacity: 0.5;"></i>
          <p style="margin-top: 0.5rem;">Start a conversation with ${agentName}</p>
        </div>
      `
      if (typeof lucide !== 'undefined') lucide.createIcons()
    }
  }
  
  async loadAmosConversation() {
    // Reset to Amos - reload the page or clear to show Amos messages
    const chatMessages = document.querySelector('.chat-messages')
    
    // Fetch recent conversation
    const response = await fetch('/scout/conversation_history?limit=50', {
      headers: { 'Accept': 'application/json' }
    })
    
    if (response.ok) {
      const data = await response.json()
      if (data.messages && data.messages.length > 0) {
        this.renderMessages(chatMessages, data.messages)
      } else {
        chatMessages.innerHTML = `
          <div class="empty-conversation" style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: var(--text-muted);">
            <i data-lucide="sparkles" style="width: 32px; height: 32px; opacity: 0.5;"></i>
            <p style="margin-top: 0.5rem;">Start a conversation with Amos</p>
          </div>
        `
      }
    } else {
      throw new Error('Failed to load Amos conversation')
    }
    
    if (typeof lucide !== 'undefined') lucide.createIcons()
  }
  
  async loadAgentHistory(agentId, agentName) {
    const chatMessages = document.querySelector('.chat-messages')
    
    // Fetch agent-specific conversation
    const response = await fetch(`/scout/agent_conversation?agent_id=${agentId}`, {
      headers: { 'Accept': 'application/json' }
    })
    
    if (response.ok) {
      const data = await response.json()
      if (data.messages && data.messages.length > 0) {
        this.renderMessages(chatMessages, data.messages)
      } else {
        chatMessages.innerHTML = `
          <div class="empty-conversation" style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: var(--text-muted);">
            <i data-lucide="bot" style="width: 32px; height: 32px; opacity: 0.5;"></i>
            <p style="margin-top: 0.5rem;">Start a conversation with ${agentName}</p>
          </div>
        `
      }
    } else {
      throw new Error('Failed to load agent conversation')
    }
    
    if (typeof lucide !== 'undefined') lucide.createIcons()
  }
  
  renderMessages(container, messages) {
    container.innerHTML = messages.map(msg => {
      const isUser = msg.role === 'user'
      return `
        <div class="message ${isUser ? 'user-message' : 'assistant-message'}">
          <div class="message-content">
            ${msg.content}
          </div>
        </div>
      `
    }).join('')
    
    // Scroll to bottom
    container.scrollTop = container.scrollHeight
  }
}
