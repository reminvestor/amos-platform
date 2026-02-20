import { Controller } from "@hotwired/stimulus"

/**
 * Feedback Controller
 * 
 * Handles user feedback submission (thumbs up/down) for agent executions,
 * tool calls, and other feedbackable items.
 * 
 * Usage:
 *   <div data-controller="feedback"
 *        data-feedback-feedbackable-type-value="AgentPluginExecution"
 *        data-feedback-feedbackable-id-value="123"
 *        data-feedback-session-id-value="session-abc">
 *     <button data-action="click->feedback#submit" 
 *             data-feedback-rating-param="1">👍</button>
 *     <button data-action="click->feedback#submit" 
 *             data-feedback-rating-param="-1">👎</button>
 *   </div>
 */
export default class extends Controller {
  static values = {
    feedbackableType: String,
    feedbackableId: Number,
    sessionId: String,
    taskType: String,              // For experience learning integration
    decisionTraceId: Number,       // Link to specific decision trace
    submitted: { type: Boolean, default: false }
  }

  connect() {
    // Check if feedback was already submitted (stored in localStorage)
    const key = this.storageKey
    if (localStorage.getItem(key)) {
      this.submittedValue = true
      this.showSuccess(parseInt(localStorage.getItem(key)))
    }
  }

  get storageKey() {
    return `feedback-${this.feedbackableTypeValue}-${this.feedbackableIdValue}`
  }

  async submit(event) {
    // Prevent double submission
    if (this.submittedValue) {
      return
    }

    const rating = parseInt(event.params.rating)
    const button = event.currentTarget

    // For negative feedback, show comment prompt first
    if (rating === -1) {
      this.showCommentPrompt(button)
      return
    }

    // For positive/neutral feedback, submit immediately
    await this.submitFeedback(rating, null, button)
  }

  showCommentPrompt(button) {
    // Show the comment form that's in the partial
    const commentForm = this.element.querySelector('.feedback-comment-form')
    if (commentForm) {
      commentForm.classList.remove('d-none')
      // Hide the buttons temporarily
      const btnGroup = this.element.querySelector('.btn-group')
      if (btnGroup) btnGroup.classList.add('d-none')
      // Hide the label
      const label = this.element.querySelector('.feedback-label')
      if (label) label.classList.add('d-none')
      // Focus the textarea
      const textarea = this.element.querySelector('.feedback-comment-input')
      if (textarea) textarea.focus()
    }
  }

  async submitWithComment(event) {
    event.preventDefault()
    const comment = this.element.querySelector('.feedback-comment-input')?.value?.trim() || ''
    await this.submitFeedback(-1, comment.length > 0 ? comment : null)
  }

  async skipComment() {
    await this.submitFeedback(-1, null)
  }

  async submitFeedback(rating, comment, button) {
    this.submittedValue = true

    // Disable submit/skip buttons to prevent double clicks
    const commentForm = this.element.querySelector('.feedback-comment-form')
    if (commentForm) {
      commentForm.querySelectorAll('button').forEach(btn => btn.disabled = true)
    }

    try {
      // Build metadata including experience learning context
      const metadata = {
        submitted_from: window.location.pathname,
        user_agent: navigator.userAgent
      }

      // Include task_type for experience learning integration
      if (this.hasTaskTypeValue && this.taskTypeValue) {
        metadata.task_type = this.taskTypeValue
      }

      // Include decision_trace_id for direct trace linking
      if (this.hasDecisionTraceIdValue && this.decisionTraceIdValue) {
        metadata.decision_trace_id = this.decisionTraceIdValue
      }

      // Build the feedback payload
      const feedbackPayload = {
        feedbackable_type: this.feedbackableTypeValue,
        feedbackable_id: this.feedbackableIdValue,
        rating: rating,
        session_id: this.sessionIdValue || null,
        metadata: metadata
      }

      // Include comment if provided
      if (comment) {
        feedbackPayload.comment = comment
      }

      // Use session-based Scout endpoint for in-app feedback
      const response = await fetch('/scout/feedback', {
        method: 'POST',
        headers: this.getHeaders(),
        body: JSON.stringify({
          feedback: feedbackPayload
        })
      })

      const data = await response.json()

      if (data.success) {
        // Store in localStorage to prevent re-submission
        localStorage.setItem(this.storageKey, rating.toString())

        // Show success message
        this.showSuccess(rating)

        // Dispatch custom event for other components to react
        this.dispatch('submitted', {
          detail: {
            rating,
            feedbackableType: this.feedbackableTypeValue,
            feedbackableId: this.feedbackableIdValue
          }
        })
      } else {
        // Revert on error
        this.submittedValue = false
        if (button) button.classList.remove('selected')
        // Re-enable buttons
        if (commentForm) {
          commentForm.querySelectorAll('button').forEach(btn => btn.disabled = false)
        }
        this.showError(data.errors?.join(', ') || 'Failed to submit feedback')
      }
    } catch (error) {
      console.error('Feedback submission error:', error)
      this.submittedValue = false
      if (button) button.classList.remove('selected')
      // Re-enable buttons
      if (commentForm) {
        commentForm.querySelectorAll('button').forEach(btn => btn.disabled = false)
      }
      this.showError('Network error. Please try again.')
    }
  }

  showSuccess(rating) {
    const successEl = this.element.querySelector('.feedback-success')
    const messageEl = this.element.querySelector('.feedback-message')

    if (successEl) {
      successEl.classList.remove('d-none')

      if (messageEl) {
        messageEl.textContent = rating === 1
          ? 'Thanks for the positive feedback!'
          : 'Thanks for your feedback. We\'ll do better!'
      }
    }

    // Hide the buttons
    const btnGroup = this.element.querySelector('.btn-group')
    if (btnGroup) {
      btnGroup.classList.add('d-none')
    }

    // Hide the comment form (if it was shown for negative feedback)
    const commentForm = this.element.querySelector('.feedback-comment-form')
    if (commentForm) {
      commentForm.classList.add('d-none')
    }

    // Hide the label
    const label = this.element.querySelector('.feedback-label')
    if (label) {
      label.classList.add('d-none')
    }
  }

  showError(message) {
    // Create temporary error toast using DOM APIs to prevent XSS
    const toast = document.createElement('div')
    toast.className = 'position-fixed bottom-0 end-0 p-3'
    toast.style.zIndex = '1100'

    const toastInner = document.createElement('div')
    toastInner.className = 'toast show'
    toastInner.setAttribute('role', 'alert')

    const header = document.createElement('div')
    header.className = 'toast-header bg-danger text-white'
    const title = document.createElement('strong')
    title.className = 'me-auto'
    title.textContent = 'Error'
    const closeBtn = document.createElement('button')
    closeBtn.type = 'button'
    closeBtn.className = 'btn-close btn-close-white'
    closeBtn.setAttribute('data-bs-dismiss', 'toast')
    header.appendChild(title)
    header.appendChild(closeBtn)

    const body = document.createElement('div')
    body.className = 'toast-body'
    body.textContent = message

    toastInner.appendChild(header)
    toastInner.appendChild(body)
    toast.appendChild(toastInner)
    document.body.appendChild(toast)

    // Auto-remove after 5 seconds
    setTimeout(() => toast.remove(), 5000)
  }

  getApiToken() {
    // Try to get API token from various sources
    // 1. Meta tag
    const metaToken = document.querySelector('meta[name="api-token"]')?.content
    if (metaToken) return metaToken
    
    // 2. Data attribute on body
    const bodyToken = document.body.dataset.apiToken
    if (bodyToken) return bodyToken
    
    // 3. LocalStorage (for SPA-like usage)
    const storedToken = localStorage.getItem('api_token')
    if (storedToken) return storedToken
    
    // 4. Return empty string - the server will use session auth
    return ''
  }

  getCsrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }

  getHeaders() {
    const headers = {
      'Content-Type': 'application/json',
      'X-CSRF-Token': this.getCsrfToken()
    }
    
    const apiToken = this.getApiToken()
    if (apiToken) {
      headers['Authorization'] = `Bearer ${apiToken}`
    }
    
    return headers
  }
}

