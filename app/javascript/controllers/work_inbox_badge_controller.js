import { Controller } from "@hotwired/stimulus"

// Work Inbox Badge Controller
// Shows count of unread work items and animates when new items arrive
export default class extends Controller {
  static targets = ["count"]
  static values = {
    userId: Number,
    initialCount: Number
  }

  connect() {
    console.log("📥 Work Inbox Badge connected", {
      userId: this.userIdValue,
      initialCount: this.initialCountValue
    })
    
    this.currentCount = this.initialCountValue || 0
    this.updateDisplay()
    this.subscribeToChannel()
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      console.log("📥 Work Inbox Badge subscription disconnected")
    }
  }

  subscribeToChannel() {
    // Subscribe to user's work items channel
    const channelName = `user_${this.userIdValue}_work_items`
    console.log("📥 Subscribing to channel:", channelName)
    
    // Use ActionCable to subscribe
    if (typeof App !== 'undefined' && App.cable) {
      this.subscription = App.cable.subscriptions.create(
        { channel: "WorkItemsChannel" },
        {
          connected: () => {
            console.log("📥 Connected to WorkItemsChannel")
          },
          disconnected: () => {
            console.log("📥 Disconnected from WorkItemsChannel")
          },
          received: (data) => {
            console.log("📥 Work item update received:", data)
            this.handleUpdate(data)
          }
        }
      )
    } else {
      console.warn("📥 ActionCable not available, polling fallback")
      // Fallback: poll every 30 seconds
      this.pollInterval = setInterval(() => this.fetchCount(), 30000)
    }
    
    // Also listen for custom events (from ScoutChannel broadcasts)
    window.addEventListener('work-inbox-update', (e) => {
      console.log("📥 Work inbox update event:", e.detail)
      this.handleUpdate(e.detail)
    })
  }

  handleUpdate(data) {
    if (data.type === 'new_work_item') {
      // Increment count and animate
      this.currentCount++
      this.animateNewItem()
      this.updateDisplay()
      
      // Show toast notification
      this.showNotification(data.work_item)
    } else if (data.type === 'item_read') {
      // Decrement count
      this.currentCount = Math.max(0, this.currentCount - 1)
      this.updateDisplay()
    } else if (data.type === 'count_update') {
      // Direct count update
      this.currentCount = data.count || 0
      this.updateDisplay()
    }
  }

  updateDisplay() {
    // Update count display
    if (this.hasCountTarget) {
      this.countTarget.textContent = this.currentCount
    }
    
    // Show/hide badge based on count
    if (this.currentCount > 0) {
      this.element.classList.remove('hidden')
    } else {
      this.element.classList.add('hidden')
    }
    
    // Update tooltip
    const button = this.element.querySelector('.badge-button')
    if (button) {
      button.title = `Work Inbox - ${this.currentCount} unread items`
    }
  }

  animateNewItem() {
    // Pulse the badge
    this.element.classList.remove('has-new-items')
    void this.element.offsetWidth // Force reflow
    this.element.classList.add('has-new-items')
    
    // Bump the count
    if (this.hasCountTarget) {
      this.countTarget.classList.remove('bump')
      void this.countTarget.offsetWidth
      this.countTarget.classList.add('bump')
    }
    
    // Remove animation classes after animation completes
    setTimeout(() => {
      this.element.classList.remove('has-new-items')
      if (this.hasCountTarget) {
        this.countTarget.classList.remove('bump')
      }
    }, 500)
  }

  showNotification(workItem) {
    // Create a toast notification for new work items
    if (!workItem) return
    
    const toast = document.createElement('div')
    toast.className = 'work-item-toast'
    toast.innerHTML = `
      <div class="toast-icon">${workItem.icon || '📥'}</div>
      <div class="toast-content">
        <div class="toast-title">${workItem.title}</div>
        <div class="toast-summary">${workItem.summary || 'New item in your Work Inbox'}</div>
      </div>
    `
    
    // Add toast styles if not already present
    if (!document.getElementById('work-toast-styles')) {
      const styles = document.createElement('style')
      styles.id = 'work-toast-styles'
      styles.textContent = `
        .work-item-toast {
          position: fixed;
          bottom: 200px;
          left: 80px;
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 12px 16px;
          background: rgba(26, 27, 46, 0.95);
          border: 1px solid rgba(16, 185, 129, 0.3);
          border-radius: 12px;
          box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
          z-index: 1001;
          animation: slideInToast 0.3s ease-out, fadeOutToast 0.3s ease-out 3s forwards;
          max-width: 350px;
        }
        .work-item-toast .toast-icon {
          font-size: 1.5rem;
        }
        .work-item-toast .toast-content {
          flex: 1;
        }
        .work-item-toast .toast-title {
          color: white;
          font-weight: 600;
          font-size: 0.9rem;
        }
        .work-item-toast .toast-summary {
          color: rgba(255, 255, 255, 0.7);
          font-size: 0.8rem;
          margin-top: 2px;
        }
        @keyframes slideInToast {
          from {
            transform: translateX(-50px);
            opacity: 0;
          }
          to {
            transform: translateX(0);
            opacity: 1;
          }
        }
        @keyframes fadeOutToast {
          to {
            opacity: 0;
            transform: translateX(-20px);
          }
        }
      `
      document.head.appendChild(styles)
    }
    
    document.body.appendChild(toast)
    
    // Remove toast after animation
    setTimeout(() => toast.remove(), 3500)
  }

  openWorkInbox() {
    console.log("📥 Opening work inbox")
    // Load the work inbox canvas
    if (typeof window.scoutLoadCanvas === 'function') {
      window.scoutLoadCanvas('work_inbox', {})
    } else {
      // Fallback: dispatch event
      window.dispatchEvent(new CustomEvent('scout:load-canvas', {
        detail: { canvas: 'work_inbox', data: {} }
      }))
    }
  }

  async fetchCount() {
    try {
      const response = await fetch('/scout/work_items/unread_count')
      if (response.ok) {
        const data = await response.json()
        this.currentCount = data.count || 0
        this.updateDisplay()
      }
    } catch (e) {
      console.warn("📥 Failed to fetch work item count:", e)
    }
  }
}

