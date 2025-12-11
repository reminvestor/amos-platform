import { Controller } from "@hotwired/stimulus"

// Browser Session Controller
// Manages the browser session canvas for computer use agent
// Handles screenshot zoom, ActionCable updates, and state management
export default class extends Controller {
  static targets = ["content", "screenshot", "screenshotContainer", "urlDisplay"]
  static values = {
    sessionId: String,
    url: String
  }

  connect() {
    console.log("[BrowserSession] Controller connected", {
      sessionId: this.sessionIdValue,
      url: this.urlValue
    })
    
    // Subscribe to browser state updates via custom events
    this.handleBrowserState = this.handleBrowserState.bind(this)
    document.addEventListener('scout:browser-state', this.handleBrowserState)
  }

  disconnect() {
    document.removeEventListener('scout:browser-state', this.handleBrowserState)
  }

  // Toggle zoom on screenshot
  toggleZoom(event) {
    const img = event.currentTarget
    img.classList.toggle('zoomed')
    
    // Add escape key listener when zoomed
    if (img.classList.contains('zoomed')) {
      this.escapeHandler = (e) => {
        if (e.key === 'Escape') {
          img.classList.remove('zoomed')
          document.removeEventListener('keydown', this.escapeHandler)
        }
      }
      document.addEventListener('keydown', this.escapeHandler)
    }
  }

  // Handle browser state updates from ActionCable
  handleBrowserState(event) {
    const data = event.detail || {}
    console.log("[BrowserSession] Received state update:", data)

    // Update URL display
    if (this.hasUrlDisplayTarget && data.url) {
      try {
        this.urlDisplayTarget.textContent = new URL(data.url).host
      } catch {
        this.urlDisplayTarget.textContent = data.url
      }
      this.urlValue = data.url
    }

    // Update screenshot
    if (data.screenshot && this.hasContentTarget) {
      this.updateScreenshot(data)
    }
  }

  updateScreenshot(data) {
    const screenshotSrc = data.screenshot.startsWith('data:') 
      ? data.screenshot 
      : `data:image/png;base64,${data.screenshot}`

    if (this.hasScreenshotContainerTarget) {
      // Update existing screenshot
      const img = this.screenshotContainerTarget.querySelector('.bs-screenshot-img')
      if (img) {
        img.src = screenshotSrc
      }
      
      // Update message if present
      const msgSpan = this.screenshotContainerTarget.querySelector('.bs-action-message span')
      if (msgSpan && data.message) {
        msgSpan.textContent = data.message
      }
    } else {
      // Create new screenshot container
      this.contentTarget.innerHTML = this.buildScreenshotHTML(screenshotSrc, data)
      
      // Re-initialize Lucide icons
      if (typeof lucide !== 'undefined') {
        lucide.createIcons()
      }
    }
  }

  buildScreenshotHTML(screenshotSrc, data) {
    return `
      <div class="bs-screenshot-container" data-browser-session-target="screenshotContainer">
        ${data.message ? `
          <div class="bs-action-message">
            <i data-lucide="check-circle" class="bs-icon-sm bs-success-icon" aria-hidden="true"></i>
            <span>${this.escapeHtml(data.message)}</span>
          </div>
        ` : ''}
        <div class="bs-screenshot-wrapper">
          <img src="${screenshotSrc}"
               alt="Browser screenshot"
               class="bs-screenshot-img"
               data-browser-session-target="screenshot"
               data-action="click->browser-session#toggleZoom" />
        </div>
        ${data.title ? `
          <div class="bs-page-title">
            <i data-lucide="file-text" class="bs-icon-sm" aria-hidden="true"></i>
            <span>${this.escapeHtml(data.title)}</span>
          </div>
        ` : ''}
      </div>
    `
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text || ''
    return div.innerHTML
  }
}
