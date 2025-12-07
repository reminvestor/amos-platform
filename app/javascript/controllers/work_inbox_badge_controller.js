import { Controller } from "@hotwired/stimulus"

// Work Inbox Badge Controller
// Updates the red notification badge on the Work Inbox nav item
export default class extends Controller {
  static values = {
    userId: Number,
    initialCount: Number
  }

  connect() {
    console.log("📥 Work Inbox Badge controller connected", {
      userId: this.userIdValue,
      initialCount: this.initialCountValue
    })
    
    this.currentCount = this.initialCountValue || 0
    this.badge = document.getElementById('work-inbox-badge')
    
    this.updateDisplay()
    this.subscribeToChannel()
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      console.log("📥 Work Inbox Badge subscription disconnected")
    }
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
    }
  }

  subscribeToChannel() {
    // Subscribe to user's work items channel
    console.log("📥 Subscribing to WorkItemsChannel")
    
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
      console.warn("📥 ActionCable not available, using polling")
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
      this.animateBadge()
      this.updateDisplay()
      
      // Show toast notification
      this.showNotification(data.work_item)
    } else if (data.type === 'item_read') {
      // Decrement count
      this.currentCount = Math.max(0, this.currentCount - 1)
      this.updateDisplay()
    } else if (data.type === 'count_update') {
      // Direct count update
      const oldCount = this.currentCount
      this.currentCount = data.count || 0
      if (this.currentCount > oldCount) {
        this.animateBadge()
      }
      this.updateDisplay()
    }
  }

  updateDisplay() {
    if (!this.badge) {
      this.badge = document.getElementById('work-inbox-badge')
    }
    
    if (!this.badge) return
    
    if (this.currentCount > 0) {
      this.badge.textContent = this.currentCount > 99 ? '99+' : this.currentCount
      this.badge.style.display = 'flex'
    } else {
      this.badge.style.display = 'none'
    }
  }

  animateBadge() {
    if (!this.badge) return
    
    // Pulse animation
    this.badge.classList.remove('pulse')
    void this.badge.offsetWidth // Force reflow
    this.badge.classList.add('pulse')
    
    // Remove animation class after it completes
    setTimeout(() => {
      this.badge.classList.remove('pulse')
    }, 400)
  }

  showNotification(workItem) {
    // Create a toast notification for new work items
    if (!workItem) return
    
    const toast = document.createElement('div')
    toast.className = 'work-item-toast'
    toast.innerHTML = `
      <div class="toast-icon">${workItem.icon || '📥'}</div>
      <div class="toast-content">
        <div class="toast-title">${workItem.title || 'Task completed'}</div>
        <div class="toast-summary">${workItem.summary || 'New item in your Work Inbox'}</div>
      </div>
      <button class="toast-close" onclick="this.parentElement.remove()">×</button>
    `
    
    // Add toast styles if not already present
    if (!document.getElementById('work-toast-styles')) {
      const styles = document.createElement('style')
      styles.id = 'work-toast-styles'
      styles.textContent = `
        .work-item-toast {
          position: fixed;
          bottom: 100px;
          left: 80px;
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 12px 16px;
          background: rgba(26, 27, 46, 0.95);
          border: 1px solid rgba(16, 185, 129, 0.3);
          border-left: 3px solid #10b981;
          border-radius: 8px;
          box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
          z-index: 1001;
          animation: slideInToast 0.3s ease-out, fadeOutToast 0.3s ease-out 4s forwards;
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
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 250px;
        }
        .work-item-toast .toast-close {
          background: none;
          border: none;
          color: rgba(255, 255, 255, 0.5);
          font-size: 1.2rem;
          cursor: pointer;
          padding: 0 4px;
        }
        .work-item-toast .toast-close:hover {
          color: white;
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
    setTimeout(() => toast.remove(), 4500)
  }

  async fetchCount() {
    try {
      const response = await fetch('/scout/work_items/unread_count')
      if (response.ok) {
        const data = await response.json()
        const oldCount = this.currentCount
        this.currentCount = data.count || 0
        if (this.currentCount > oldCount) {
          this.animateBadge()
        }
        this.updateDisplay()
      }
    } catch (e) {
      console.warn("📥 Failed to fetch work item count:", e)
    }
  }
}
