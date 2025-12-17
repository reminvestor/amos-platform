import { Controller } from "@hotwired/stimulus"

// Hub Unread Badge Controller
// Updates the red notification badge on the Hub nav item for unread messages
export default class extends Controller {
  static values = {
    userId: Number,
    entityId: Number,
    initialCount: Number
  }

  connect() {
    console.log("📬 Hub Unread Badge controller connected", {
      userId: this.userIdValue,
      entityId: this.entityIdValue,
      initialCount: this.initialCountValue
    })
    
    this.currentCount = this.initialCountValue || 0
    // Support both badge locations (chat header and hub sidebar)
    this.badge = document.getElementById('hub-unread-badge')
    this.badgeCompact = document.getElementById('hub-unread-badge-compact')
    
    this.updateDisplay()
    this.subscribeToHubUpdates()
  }

  disconnect() {
    // Cleanup if needed
  }

  subscribeToHubUpdates() {
    // Subscribe to user-specific Hub updates via ActionCable
    if (typeof App !== 'undefined' && App.cable) {
      this.subscription = App.cable.subscriptions.create(
        { channel: "HubChannel", entity_id: this.entityIdValue },
        {
          received: (data) => {
            console.log('📬 Hub channel data received:', data)
            
            if (data.type === 'unread_count_update') {
              this.handleCountUpdate(data)
            } else if (data.type === 'new_message') {
              this.handleNewMessage(data)
            } else if (data.type === 'mention') {
              // Increment on mention
              this.currentCount++
              this.animateBadge()
              this.updateDisplay()
            }
          }
        }
      )
      console.log('📬 Subscribed to HubChannel for unread updates')
    }
  }

  handleNewMessage(data) {
    // Check if this is in a thread where user is a participant
    // and the message is not from the current user
    if (data.sender_id !== this.userIdValue) {
      // Check if user is currently viewing this thread
      const currentThread = document.querySelector('.hub-item.active')?.dataset?.threadId
      const messageThreadId = data.thread_id
      
      // Only increment if not currently viewing this thread
      if (currentThread !== messageThreadId?.toString()) {
        this.currentCount++
        this.animateBadge()
        this.updateDisplay()
      }
    }
  }

  handleMessageRead(data) {
    // Decrement count when messages are read
    const readCount = data.count || 1
    this.currentCount = Math.max(0, this.currentCount - readCount)
    this.updateDisplay()
  }

  handleCountUpdate(data) {
    // Direct count update from server
    const oldCount = this.currentCount
    this.currentCount = data.count || 0
    
    if (this.currentCount > oldCount) {
      this.animateBadge()
    }
    
    this.updateDisplay()
  }

  updateDisplay() {
    const count = this.currentCount > 99 ? '99+' : this.currentCount.toString()
    
    // Update both badges (chat header and hub sidebar)
    if (this.badge) {
      if (this.currentCount > 0) {
        this.badge.textContent = count
        this.badge.style.display = 'flex'
      } else {
        this.badge.style.display = 'none'
      }
    }
    
    if (this.badgeCompact) {
      if (this.currentCount > 0) {
        this.badgeCompact.textContent = count
        this.badgeCompact.style.display = 'flex'
      } else {
        this.badgeCompact.style.display = 'none'
      }
    }
    
    console.log('📬 Badge updated:', this.currentCount)
  }

  animateBadge() {
    // Animate both badges
    [this.badge, this.badgeCompact].forEach(badge => {
      if (!badge) return
      
      badge.classList.remove('pulse')
      // Trigger reflow
      void badge.offsetWidth
      badge.classList.add('pulse')
      
      // Remove pulse class after animation
      setTimeout(() => {
        badge.classList.remove('pulse')
      }, 400)
    })
  }

  // Public method to manually update count
  setCount(count) {
    const oldCount = this.currentCount
    this.currentCount = count
    
    if (count > oldCount) {
      this.animateBadge()
    }
    
    this.updateDisplay()
  }
}

