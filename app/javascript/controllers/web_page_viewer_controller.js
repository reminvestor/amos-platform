import { Controller } from "@hotwired/stimulus"

/**
 * Web Page Viewer Controller
 * Handles iframe loading detection, screenshot capture triggers, interactive browsing, and zoom functionality
 */
export default class extends Controller {
  static targets = [
    "content",
    "loading",
    "error",
    "screenshot",
    "screenshotImg",
    "iframe",
    "frame",
    "iframeLoading",
    "iframeBlocked",
    // Interactive mode targets
    "interactive",
    "interactiveLoading",
    "interactiveFrame",
    "interactiveError",
    "proxyFrame"
  ]

  static values = {
    url: String,
    requestId: String,
    displayMode: String,
    proxyUrl: String
  }

  connect() {
    console.log("[WebPageViewer] Connected", this.urlValue, "mode:", this.displayModeValue)

    // Set up based on display mode
    if (this.displayModeValue === "iframe" && this.hasFrameTarget) {
      this.setupIframeLoadDetection()
    } else if (this.displayModeValue === "interactive") {
      this.setupInteractiveProxySession()
    }

    // Listen for canvas updates (for async screenshot results)
    this.setupCanvasUpdateListener()
  }

  disconnect() {
    if (this.loadTimeout) {
      clearTimeout(this.loadTimeout)
    }
    if (this.canvasUpdateHandler) {
      document.removeEventListener("scout:canvas-update", this.canvasUpdateHandler)
    }
  }

  /**
   * Set up interactive browser session via proxy
   * The iframe is already loaded in the template with the proxy URL
   * We just need to handle the load detection
   */
  setupInteractiveProxySession() {
    console.log("[WebPageViewer] Setting up interactive proxy session for:", this.urlValue)

    // The iframe is already in the template with src set to proxy_url
    // Set up a timeout to hide loading state
    this.interactiveTimeout = setTimeout(() => {
      this.showInteractiveReady()
    }, 5000)
  }

  /**
   * Called when proxy frame loads
   */
  onProxyFrameLoad(event) {
    console.log("[WebPageViewer] Proxy frame loaded")
    
    if (this.interactiveTimeout) {
      clearTimeout(this.interactiveTimeout)
    }
    
    this.showInteractiveReady()
  }

  /**
   * Show the interactive session as ready
   */
  showInteractiveReady() {
    console.log("[WebPageViewer] Showing interactive ready state")
    
    if (this.interactiveTimeout) {
      clearTimeout(this.interactiveTimeout)
    }

    // Hide the loading overlay
    if (this.hasInteractiveLoadingTarget) {
      this.interactiveLoadingTarget.classList.add("hidden")
      this.interactiveLoadingTarget.style.display = "none"
    }
    
    // Show the frame container
    if (this.hasInteractiveFrameTarget) {
      this.interactiveFrameTarget.classList.remove("hidden")
      this.interactiveFrameTarget.style.opacity = "1"
    }
    
    // Hide any error
    if (this.hasInteractiveErrorTarget) {
      this.interactiveErrorTarget.classList.add("hidden")
    }
  }

  /**
   * Show interactive session error
   */
  showInteractiveError(message = "Could not start browser session") {
    if (this.interactiveTimeout) {
      clearTimeout(this.interactiveTimeout)
    }

    if (this.hasInteractiveLoadingTarget) {
      this.interactiveLoadingTarget.classList.add("hidden")
    }
    if (this.hasInteractiveFrameTarget) {
      this.interactiveFrameTarget.classList.add("hidden")
    }
    if (this.hasInteractiveErrorTarget) {
      this.interactiveErrorTarget.classList.remove("hidden")
      const msgEl = this.interactiveErrorTarget.querySelector("p")
      if (msgEl) msgEl.textContent = message
    }
  }

  /**
   * Browser navigation - go back (works within proxied session)
   */
  goBack() {
    if (this.hasProxyFrameTarget) {
      try {
        this.proxyFrameTarget.contentWindow.history.back()
      } catch (e) {
        console.warn("[WebPageViewer] Cannot navigate back (cross-origin)")
      }
    }
  }

  /**
   * Browser navigation - go forward (works within proxied session)
   */
  goForward() {
    if (this.hasProxyFrameTarget) {
      try {
        this.proxyFrameTarget.contentWindow.history.forward()
      } catch (e) {
        console.warn("[WebPageViewer] Cannot navigate forward (cross-origin)")
      }
    }
  }

  /**
   * Refresh the interactive session
   */
  refreshInteractive() {
    if (this.hasProxyFrameTarget) {
      // Show loading state
      if (this.hasInteractiveLoadingTarget) {
        this.interactiveLoadingTarget.classList.remove("hidden")
      }
      if (this.hasInteractiveFrameTarget) {
        this.interactiveFrameTarget.style.opacity = "0.5"
      }
      
      // Reload the iframe
      const proxyUrl = this.proxyUrlValue || `/web_proxy?url=${encodeURIComponent(this.urlValue)}`
      this.proxyFrameTarget.src = ""
      setTimeout(() => {
        this.proxyFrameTarget.src = proxyUrl
        this.setupInteractiveProxySession()
      }, 100)
    }
  }

  /**
   * Switch from interactive to screenshot mode
   */
  switchToScreenshot() {
    console.log("[WebPageViewer] Switching to screenshot mode")
    this.displayModeValue = "screenshot"
    this.captureScreenshot()
  }

  /**
   * Set up iframe load detection with timeout fallback
   * Since we can't reliably detect X-Frame-Options blocks, we use a timeout
   */
  setupIframeLoadDetection() {
    // Give the iframe 10 seconds to load
    this.loadTimeout = setTimeout(() => {
      // If iframe is still showing loading overlay, assume it's blocked
      if (this.hasIframeLoadingTarget && !this.iframeLoadingTarget.classList.contains("hidden")) {
        console.log("[WebPageViewer] Iframe load timeout - showing blocked message")
        this.showIframeBlocked()
      }
    }, 10000)
  }

  /**
   * Listen for canvas update events (from background job completion)
   */
  setupCanvasUpdateListener() {
    this.canvasUpdateHandler = (event) => {
      const { canvas, canvas_data: data } = event.detail || {}

      if (canvas !== "web_page_viewer") return
      if (data?.request_id !== this.requestIdValue) return

      console.log("[WebPageViewer] Received canvas update", data)

      if (data.status === "complete" && data.screenshot_url) {
        this.showScreenshot(data)
      } else if (data.status === "error") {
        this.showError(data.error)
      }
    }

    document.addEventListener("scout:canvas-update", this.canvasUpdateHandler)
  }

  /**
   * Called when iframe successfully loads
   */
  onIframeLoad(event) {
    console.log("[WebPageViewer] Iframe loaded")

    if (this.loadTimeout) {
      clearTimeout(this.loadTimeout)
    }

    // Hide loading overlay
    if (this.hasIframeLoadingTarget) {
      this.iframeLoadingTarget.classList.add("hidden")
    }

    // Try to detect if iframe is actually showing content
    // Note: This is limited due to cross-origin restrictions
    try {
      const frame = this.frameTarget
      // If we can access contentDocument, the page loaded (same-origin)
      if (frame.contentDocument) {
        console.log("[WebPageViewer] Iframe content accessible")
      }
    } catch (e) {
      // Cross-origin - can't verify content, but load event fired so assume success
      console.log("[WebPageViewer] Cross-origin iframe, cannot verify content")
    }
  }

  /**
   * Called when iframe fails to load
   */
  onIframeError(event) {
    console.log("[WebPageViewer] Iframe error", event)

    if (this.loadTimeout) {
      clearTimeout(this.loadTimeout)
    }

    this.showIframeBlocked()
  }

  /**
   * Show the "iframe blocked" message
   */
  showIframeBlocked() {
    if (this.hasIframeLoadingTarget) {
      this.iframeLoadingTarget.classList.add("hidden")
    }
    if (this.hasIframeBlockedTarget) {
      this.iframeBlockedTarget.classList.remove("hidden")
    }
  }

  /**
   * Trigger screenshot capture via Scout
   */
  captureScreenshot() {
    console.log("[WebPageViewer] Requesting screenshot capture for", this.urlValue)

    // Show loading state
    this.showLoading("Capturing screenshot...")

    // Send message to Scout to capture the page
    if (typeof window.scoutSendMessage === "function") {
      window.scoutSendMessage(`Capture a screenshot of ${this.urlValue}`)
    } else {
      // Fallback: make direct API call
      this.captureViaApi()
    }
  }

  /**
   * Direct API call to trigger screenshot capture
   */
  async captureViaApi() {
    try {
      const response = await fetch("/scout/capture_web_page", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify({
          url: this.urlValue,
          request_id: this.requestIdValue
        })
      })

      const data = await response.json()

      if (data.success) {
        console.log("[WebPageViewer] Capture job started")
        // Result will come via canvas update listener
      } else {
        this.showError(data.error || "Failed to start capture")
      }
    } catch (error) {
      console.error("[WebPageViewer] API error:", error)
      this.showError("Failed to capture page")
    }
  }

  /**
   * Refresh the page view
   */
  refresh() {
    console.log("[WebPageViewer] Refreshing")

    if (this.displayModeValue === "interactive") {
      this.refreshInteractive()
    } else if (this.displayModeValue === "iframe" && this.hasFrameTarget) {
      // Reload iframe
      this.frameTarget.src = this.urlValue

      // Show loading again
      if (this.hasIframeLoadingTarget) {
        this.iframeLoadingTarget.classList.remove("hidden")
      }
      if (this.hasIframeBlockedTarget) {
        this.iframeBlockedTarget.classList.add("hidden")
      }

      // Reset timeout
      this.setupIframeLoadDetection()
    } else {
      // Re-trigger screenshot capture
      this.captureScreenshot()
    }
  }

  /**
   * Toggle zoom on screenshot image
   */
  toggleZoom(event) {
    if (this.hasScreenshotImgTarget) {
      this.screenshotImgTarget.classList.toggle("zoomed")

      // Close on escape key when zoomed
      if (this.screenshotImgTarget.classList.contains("zoomed")) {
        this.escapeHandler = (e) => {
          if (e.key === "Escape") {
            this.screenshotImgTarget.classList.remove("zoomed")
            document.removeEventListener("keydown", this.escapeHandler)
          }
        }
        document.addEventListener("keydown", this.escapeHandler)
      }
    }
  }

  /**
   * Show loading state
   */
  showLoading(message = "Loading...") {
    // Hide other states
    if (this.hasErrorTarget) this.errorTarget.classList.add("hidden")
    if (this.hasScreenshotTarget) this.screenshotTarget.classList.add("hidden")
    if (this.hasIframeTarget) this.iframeTarget.classList.add("hidden")
    if (this.hasInteractiveTarget) this.interactiveTarget.classList.add("hidden")

    // Show loading
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove("hidden")
      const textEl = this.loadingTarget.querySelector(".wpv-loading-text")
      if (textEl) textEl.textContent = message
    } else {
      // Create loading element if not present
      this.contentTarget.innerHTML = `
        <div class="wpv-loading">
          <div class="wpv-spinner"></div>
          <p class="wpv-loading-text">${message}</p>
        </div>
      `
    }
  }

  /**
   * Show error state
   */
  showError(message = "Failed to load page") {
    // Hide other states
    if (this.hasLoadingTarget) this.loadingTarget.classList.add("hidden")
    if (this.hasScreenshotTarget) this.screenshotTarget.classList.add("hidden")
    if (this.hasIframeTarget) this.iframeTarget.classList.add("hidden")
    if (this.hasInteractiveTarget) this.interactiveTarget.classList.add("hidden")

    // Show or create error
    if (this.hasErrorTarget) {
      this.errorTarget.classList.remove("hidden")
      const msgEl = this.errorTarget.querySelector("p")
      if (msgEl) msgEl.textContent = message
    } else {
      this.contentTarget.innerHTML = `
        <div class="wpv-error">
          <i data-lucide="alert-circle" class="wpv-error-icon" aria-hidden="true"></i>
          <h4>Unable to load page</h4>
          <p>${message}</p>
          <div class="wpv-error-actions">
            <button type="button" class="wpv-btn wpv-btn-primary"
                    data-action="click->web-page-viewer#captureScreenshot">
              <i data-lucide="camera" class="wpv-icon-sm" aria-hidden="true"></i>
              Try Screenshot Capture
            </button>
            <a href="${this.urlValue}" target="_blank" rel="noopener noreferrer" class="wpv-btn wpv-btn-secondary">
              <i data-lucide="external-link" class="wpv-icon-sm" aria-hidden="true"></i>
              Open in New Tab
            </a>
          </div>
        </div>
      `
      if (typeof lucide !== "undefined") {
        lucide.createIcons()
      }
    }
  }

  /**
   * Show screenshot result
   */
  showScreenshot(data) {
    // Hide other states
    if (this.hasLoadingTarget) this.loadingTarget.classList.add("hidden")
    if (this.hasErrorTarget) this.errorTarget.classList.add("hidden")
    if (this.hasIframeTarget) this.iframeTarget.classList.add("hidden")
    if (this.hasInteractiveTarget) this.interactiveTarget.classList.add("hidden")

    // Build screenshot HTML
    const html = `
      <div class="wpv-screenshot-container">
        ${data.title ? `
          <div class="wpv-page-info">
            <h4 class="wpv-page-title">${this.escapeHtml(data.title)}</h4>
          </div>
        ` : ''}

        <div class="wpv-screenshot-wrapper">
          <img src="${data.screenshot_url}"
               alt="Screenshot"
               class="wpv-screenshot-img"
               data-action="click->web-page-viewer#toggleZoom"
               data-web-page-viewer-target="screenshotImg" />
        </div>

        ${data.text_content ? `
          <details class="wpv-text-content">
            <summary>
              <i data-lucide="file-text" class="wpv-icon-sm" aria-hidden="true"></i>
              Page Content (extracted text)
            </summary>
            <div class="wpv-text-body">
              ${this.escapeHtml(data.text_content.substring(0, 5000))}
            </div>
          </details>
        ` : ''}
      </div>
    `

    this.contentTarget.innerHTML = html

    // Re-init icons
    if (typeof lucide !== "undefined") {
      lucide.createIcons()
    }

    this.displayModeValue = "screenshot"
  }

  /**
   * Get CSRF token for API calls
   */
  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.getAttribute("content") : ""
  }

  /**
   * Escape HTML to prevent XSS
   */
  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  /**
   * Share the current page with Amos so it can see what the user is viewing
   * This sends a message asking Amos to read the current page
   */
  shareWithAmos() {
    console.log("[WebPageViewer] Sharing page with Amos:", this.urlValue)
    
    // Find the share button and show loading state
    const shareBtn = this.element.querySelector('.wpv-share-btn')
    if (shareBtn) {
      const originalContent = shareBtn.innerHTML
      shareBtn.innerHTML = `<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Reading...`
      shareBtn.disabled = true
      
      // Reset after a few seconds (Amos will respond in chat)
      setTimeout(() => {
        shareBtn.innerHTML = originalContent
        shareBtn.disabled = false
        if (typeof lucide !== "undefined") {
          lucide.createIcons()
        }
      }, 3000)
    }
    
    // Send message to Amos asking it to read the current page
    if (typeof window.scoutSendMessage === "function") {
      window.scoutSendMessage(
        `I'm looking at ${this.urlValue} in the interactive browser. Can you read this page and tell me what you see?`
      )
    } else if (typeof window.scoutController?.sendMessage === "function") {
      window.scoutController.sendMessage(
        `I'm looking at ${this.urlValue} in the interactive browser. Can you read this page and tell me what you see?`
      )
    } else {
      // Fallback: Try to find the scout controller and send message
      const chatInput = document.querySelector('.scout-chat-input, [data-chat-input], textarea[name="message"]')
      if (chatInput) {
        chatInput.value = `I'm looking at ${this.urlValue} in the interactive browser. Can you read this page and tell me what you see?`
        // Try to trigger submit
        const form = chatInput.closest('form')
        if (form) {
          form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
        }
      } else {
        // Last resort: show an alert
        showInfo("Please ask Amos: 'What's on the page I'm viewing?' in the chat")
      }
    }
  }
}
