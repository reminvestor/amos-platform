// Billing notifications channel - handles token usage threshold alerts
import { createConsumer } from "@rails/actioncable"

let billingChannel = null

export function subscribeToBillingNotifications(userId) {
  if (!userId) {
    console.warn("Cannot subscribe to billing notifications: no user ID")
    return
  }

  // Unsubscribe from existing channel if any
  if (billingChannel) {
    billingChannel.unsubscribe()
  }

  const consumer = window.App?.cable || createConsumer()
  
  billingChannel = consumer.subscriptions.create(
    { channel: "UserNotificationsChannel", user_id: userId },
    {
      connected() {
        console.log("💳 Connected to billing notifications")
      },

      disconnected() {
        console.log("💳 Disconnected from billing notifications")
      },

      received(data) {
        console.log("💳 Billing notification received:", data)
        
        if (data.type === 'billing_reminder' || data.type === 'billing_required') {
          showBillingNotification(data)
        } else if (data.type === 'low_balance_reminder') {
          showLowBalanceNotification(data)
        } else if (data.type === 'billing_resolved') {
          hideBillingNotifications()
          showSuccessToast(data)
        }
      }
    }
  )

  return billingChannel
}

function showBillingNotification(data) {
  // Remove any existing billing notification
  const existing = document.getElementById('billing-notification-banner')
  if (existing) existing.remove()

  // Create notification banner
  const banner = document.createElement('div')
  banner.id = 'billing-notification-banner'
  banner.className = `billing-notification billing-notification-${data.level}`
  
  const btnClass = data.level === 'danger' ? 'btn-danger' : 'btn-warning'
  const dismissBtn = data.dismissable ? '<button class="billing-notification-dismiss" data-dismiss="billing">×</button>' : ''
  
  banner.innerHTML = `
    <div class="billing-notification-content">
      <div class="billing-notification-icon">
        ${getIconForLevel(data.level)}
      </div>
      <div class="billing-notification-text">
        <strong>${data.title}</strong>
        <p>${data.message}</p>
      </div>
      <div class="billing-notification-actions">
        <a href="${data.action_url}" class="btn ${btnClass} btn-sm">
          ${data.action_text}
        </a>
        ${dismissBtn}
      </div>
    </div>
  `

  // Add styles if not already present
  addBillingNotificationStyles()

  // Insert at top of main content area
  const mainContent = document.querySelector('.admin-content') || document.querySelector('main') || document.body
  mainContent.insertBefore(banner, mainContent.firstChild)

  // Add dismiss handler
  const dismissButton = banner.querySelector('[data-dismiss="billing"]')
  if (dismissButton) {
    dismissButton.addEventListener('click', () => banner.remove())
  }

  // If blocking, also show a modal
  if (data.blocking) {
    showBlockingModal(data)
  }
}

function showLowBalanceNotification(data) {
  // Remove any existing low balance notification
  const existing = document.getElementById('low-balance-notification-banner')
  if (existing) existing.remove()

  // Build action buttons
  const actionButtons = (data.actions || []).map(action => {
    const btnClass = action.style === 'primary' ? 'btn-warning' : 'btn-outline-secondary'
    return `<a href="${action.url}" class="btn ${btnClass} btn-sm">${action.text}</a>`
  }).join('')

  const dismissBtn = data.dismissable ? '<button class="billing-notification-dismiss" data-dismiss="low-balance">×</button>' : ''

  // Create notification banner
  const banner = document.createElement('div')
  banner.id = 'low-balance-notification-banner'
  banner.className = 'billing-notification billing-notification-warning'
  banner.innerHTML = `
    <div class="billing-notification-content">
      <div class="billing-notification-icon">
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#EAB308" stroke-width="2">
          <circle cx="12" cy="12" r="10"></circle>
          <path d="M12 6v6l4 2"></path>
        </svg>
      </div>
      <div class="billing-notification-text">
        <strong>${data.title}</strong>
        <p>${data.message}</p>
      </div>
      <div class="billing-notification-actions">
        ${actionButtons}
        ${dismissBtn}
      </div>
    </div>
  `

  // Add styles if not already present
  addBillingNotificationStyles()

  // Insert at top of main content area
  const mainContent = document.querySelector('.admin-content') || document.querySelector('main') || document.body
  mainContent.insertBefore(banner, mainContent.firstChild)

  // Add dismiss handler
  const dismissButton = banner.querySelector('[data-dismiss="low-balance"]')
  if (dismissButton) {
    dismissButton.addEventListener('click', () => banner.remove())
  }
}

function hideBillingNotifications() {
  const banner = document.getElementById('billing-notification-banner')
  if (banner) banner.remove()
  
  const lowBalanceBanner = document.getElementById('low-balance-notification-banner')
  if (lowBalanceBanner) lowBalanceBanner.remove()
  
  const modal = document.getElementById('billing-blocking-modal')
  if (modal) modal.remove()
}

function showSuccessToast(data) {
  const toast = document.createElement('div')
  toast.className = 'billing-toast billing-toast-success'
  toast.innerHTML = `
    <div class="billing-toast-content">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path>
        <polyline points="22 4 12 14.01 9 11.01"></polyline>
      </svg>
      <span>${data.title}</span>
    </div>
  `
  
  document.body.appendChild(toast)
  
  // Auto-remove after 5 seconds
  setTimeout(() => toast.remove(), 5000)
}

function showBlockingModal(data) {
  const modal = document.createElement('div')
  modal.id = 'billing-blocking-modal'
  modal.className = 'billing-modal-overlay'
  modal.innerHTML = `
    <div class="billing-modal">
      <div class="billing-modal-icon">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#EF4444" stroke-width="2">
          <circle cx="12" cy="12" r="10"></circle>
          <line x1="12" y1="8" x2="12" y2="12"></line>
          <line x1="12" y1="16" x2="12.01" y2="16"></line>
        </svg>
      </div>
      <h2>${data.title}</h2>
      <p>${data.message}</p>
      <a href="${data.action_url}" class="btn btn-danger btn-lg">
        ${data.action_text}
      </a>
    </div>
  `
  
  document.body.appendChild(modal)
}

function getIconForLevel(level) {
  switch (level) {
    case 'info':
      return `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#3B82F6" stroke-width="2">
        <circle cx="12" cy="12" r="10"></circle>
        <line x1="12" y1="16" x2="12" y2="12"></line>
        <line x1="12" y1="8" x2="12.01" y2="8"></line>
      </svg>`
    case 'warning':
      return `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#EAB308" stroke-width="2">
        <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"></path>
        <line x1="12" y1="9" x2="12" y2="13"></line>
        <line x1="12" y1="17" x2="12.01" y2="17"></line>
      </svg>`
    case 'danger':
      return `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#EF4444" stroke-width="2">
        <circle cx="12" cy="12" r="10"></circle>
        <line x1="12" y1="8" x2="12" y2="12"></line>
        <line x1="12" y1="16" x2="12.01" y2="16"></line>
      </svg>`
    default:
      return ''
  }
}

function addBillingNotificationStyles() {
  if (document.getElementById('billing-notification-styles')) return
  
  const styles = document.createElement('style')
  styles.id = 'billing-notification-styles'
  styles.textContent = `
    .billing-notification {
      position: relative;
      padding: 1rem;
      margin-bottom: 1rem;
      border-radius: 0.5rem;
      animation: slideDown 0.3s ease-out;
    }
    
    @keyframes slideDown {
      from { transform: translateY(-100%); opacity: 0; }
      to { transform: translateY(0); opacity: 1; }
    }
    
    .billing-notification-info {
      background: rgba(59, 130, 246, 0.1);
      border: 1px solid rgba(59, 130, 246, 0.3);
    }
    
    .billing-notification-warning {
      background: rgba(234, 179, 8, 0.1);
      border: 1px solid rgba(234, 179, 8, 0.3);
    }
    
    .billing-notification-danger {
      background: rgba(239, 68, 68, 0.1);
      border: 1px solid rgba(239, 68, 68, 0.3);
    }
    
    .billing-notification-content {
      display: flex;
      align-items: center;
      gap: 1rem;
    }
    
    .billing-notification-icon {
      flex-shrink: 0;
    }
    
    .billing-notification-text {
      flex: 1;
    }
    
    .billing-notification-text strong {
      color: white;
      display: block;
      margin-bottom: 0.25rem;
    }
    
    .billing-notification-text p {
      color: #94A3B8;
      margin: 0;
      font-size: 0.875rem;
    }
    
    .billing-notification-actions {
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }
    
    .billing-notification-dismiss {
      background: transparent;
      border: none;
      color: #94A3B8;
      font-size: 1.5rem;
      cursor: pointer;
      padding: 0.25rem;
      line-height: 1;
    }
    
    .billing-notification-dismiss:hover {
      color: white;
    }
    
    .billing-toast {
      position: fixed;
      bottom: 2rem;
      right: 2rem;
      padding: 1rem 1.5rem;
      border-radius: 0.5rem;
      z-index: 9999;
      animation: slideUp 0.3s ease-out;
    }
    
    @keyframes slideUp {
      from { transform: translateY(100%); opacity: 0; }
      to { transform: translateY(0); opacity: 1; }
    }
    
    .billing-toast-success {
      background: rgba(34, 197, 94, 0.9);
      color: white;
    }
    
    .billing-toast-content {
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }
    
    .billing-modal-overlay {
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background: rgba(0, 0, 0, 0.8);
      display: flex;
      align-items: center;
      justify-content: center;
      z-index: 10000;
    }
    
    .billing-modal {
      background: #1E293B;
      border-radius: 1rem;
      padding: 2rem;
      text-align: center;
      max-width: 400px;
    }
    
    .billing-modal-icon {
      margin-bottom: 1rem;
    }
    
    .billing-modal h2 {
      color: white;
      margin-bottom: 0.5rem;
    }
    
    .billing-modal p {
      color: #94A3B8;
      margin-bottom: 1.5rem;
    }
  `
  
  document.head.appendChild(styles)
}

// Auto-initialize if user ID is available in the page
document.addEventListener('DOMContentLoaded', () => {
  const userIdMeta = document.querySelector('meta[name="current-user-id"]')
  if (userIdMeta) {
    subscribeToBillingNotifications(userIdMeta.content)
  }
})

export default { subscribeToBillingNotifications }

