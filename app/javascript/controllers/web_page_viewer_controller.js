import { Controller } from "@hotwired/stimulus"

/**
 * Web Page Viewer Controller
 * Handles iframe loading detection, screenshot capture triggers, and zoom functionality
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
    "iframeBlocked"
  ]

  static values = {
    url: String,
    requestId: String,
    displayMode: String
  }

  connect() {
    console.log("[WebPageViewer] Connected", this.urlValue)

    // Set up iframe load timeout
    if (this.displayModeValue === "iframe" && this.hasFrameTarget) {
      this.setupIframeLoadDetection()
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

    if (this.displayModeValue === "iframe" && this.hasFrameTarget) {
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
}
