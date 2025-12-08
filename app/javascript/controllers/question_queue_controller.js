import { Controller } from "@hotwired/stimulus"

console.log("🎯 QuestionQueueController JS FILE LOADED")

// Question Queue Controller
// Manages the floating badge and overlay for agent questions
// Non-blocking - users can continue chatting while agents ask questions
export default class extends Controller {
  static targets = [
    "badge",
    "count", 
    "overlay", 
    "list", 
    "activeQuestion",
    "agentIcon",
    "agentName", 
    "questionTime",
    "questionContent",
    "questionContext",
    "answerInput",
    "emptyState",
    "attachmentPreview",
    "attachmentImage",
    "fileInput"
  ]

  static values = {
    sessionId: String
  }

  connect() {
    console.log("🔔 Question Queue controller connected", {
      sessionId: this.sessionIdValue,
      hasBadgeTarget: this.hasBadgeTarget,
      hasOverlayTarget: this.hasOverlayTarget,
      hasCountTarget: this.hasCountTarget
    })
    this.questions = []
    this.completions = []  // Track agent completions for badge count
    this.currentQuestionId = null
    this.pendingAttachment = null  // Store file to upload with answer
    
    // Listen for question queue updates from ActionCable
    this.boundHandleQueueUpdate = this.handleQueueUpdate.bind(this)
    window.addEventListener('question-queue-update', this.boundHandleQueueUpdate)
    
    // Listen for session changes (e.g., from Fresh Start)
    this.boundHandleSessionChange = this.handleSessionChange.bind(this)
    window.addEventListener('session-changed', this.boundHandleSessionChange)
    
    // Initialize lucide icons in the component
    if (typeof lucide !== 'undefined') {
      lucide.createIcons()
    }
    
    // Load initial questions
    this.loadPendingQuestions()
  }
  
  handleSessionChange(event) {
    const { sessionId } = event.detail
    console.log("🔔 Session changed, updating to:", sessionId)
    
    // Update our session ID value
    this.sessionIdValue = sessionId
    
    // Clear current questions and completions (they belong to old session)
    this.questions = []
    this.completions = []
    this.currentQuestionId = null
    this.updateBadge()
    this.hideBadge()
    this.closeOverlay()
    
    // Load questions for new session
    this.loadPendingQuestions()
  }

  disconnect() {
    if (this.boundHandleQueueUpdate) {
      window.removeEventListener('question-queue-update', this.boundHandleQueueUpdate)
    }
    if (this.boundHandleSessionChange) {
      window.removeEventListener('session-changed', this.boundHandleSessionChange)
    }
  }

  // ============================================
  // QUESTION LOADING
  // ============================================

  async loadPendingQuestions() {
    try {
      // Include session_id in the request if available
      let url = '/scout/questions/pending'
      if (this.sessionIdValue) {
        url += `?session_id=${encodeURIComponent(this.sessionIdValue)}`
      }
      
      console.log("📥 Loading pending questions from:", url)
      
      const response = await fetch(url, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        console.log("📥 Loaded pending questions:", data)
        this.questions = data.questions || []
        this.updateBadge()
        
        if (this.questions.length > 0) {
          this.showActiveQuestion(this.questions[0])
        }
      } else {
        console.error('Failed to load pending questions, status:', response.status)
      }
    } catch (error) {
      console.error('Failed to load pending questions:', error)
    }
  }

  handleQueueUpdate(event) {
    const { action, question, question_id, pending_count, completion } = event.detail
    
    console.log('📬 Question queue update received:', {
      action,
      question_id: question_id || question?.id,
      pending_count,
      question: question,
      completion: completion
    })
    
    switch (action) {
      case 'added':
        // Add the new question
        if (question) {
          this.questions.push(question)
          console.log('📬 Added question to queue, total:', this.questions.length)
        }
        this.updateBadge()
        this.showBadge()
        
        // If no question is currently shown, show this one
        if (!this.currentQuestionId && question) {
          this.showActiveQuestion(question)
        }
        break
        
      case 'answered':
      case 'skipped':
      case 'cancelled':
        this.questions = this.questions.filter(q => q.id !== question_id)
        console.log('📬 Removed question from queue, remaining:', this.questions.length)
        this.updateBadge()
        
        // If this was the active question, show next one
        if (this.currentQuestionId === question_id) {
          this.currentQuestionId = null
          if (this.questions.length > 0) {
            this.showActiveQuestion(this.questions[0])
          } else {
            this.showEmptyState()
          }
        }
        break
      
      case 'completed':
        // Agent completed a task - add to queue and update badge (but don't auto-open overlay)
        if (completion) {
          console.log('📬 Agent completion received:', completion)
          // Add completion as a special "message" in the queue
          this.completions = this.completions || []
          this.completions.push(completion)
          // Update badge count and show with pulse animation
          this.updateBadge()
          this.showBadge()
          this.pulseBadge()  // Draw attention without popup
        }
        break
        
      default:
        console.warn('📬 Unknown queue update action:', action)
    }
    
    this.updateQuestionList()
  }
  
  // When user opens overlay and there are completions, show them
  showCompletionInOverlay(completion) {
    console.log('📬 showCompletionInOverlay called with:', completion)
    
    // Update the overlay content to show the completion
    if (this.hasAgentIconTarget) {
      this.agentIconTarget.textContent = completion.agent_icon || '✅'
      console.log('✅ Updated agent icon')
    }
    if (this.hasAgentNameTarget) {
      this.agentNameTarget.textContent = completion.agent_name || 'Agent'
      console.log('✅ Updated agent name:', completion.agent_name)
    }
    if (this.hasQuestionTimeTarget) {
      this.questionTimeTarget.textContent = 'just now'
    }
    
    // Show completion content
    if (this.hasQuestionContentTarget) {
      const agentName = completion.agent_name || 'Agent'
      const message = completion.message || 'Task completed successfully!'
      
      this.questionContentTarget.innerHTML = `
        <div class="completion-content">
          <div class="completion-icon">✅</div>
          <div class="completion-title">Task Completed!</div>
          <div class="completion-message">${message}</div>
        </div>
      `
      console.log('✅ Updated question content with message:', message)
    } else {
      console.warn('⚠️ No questionContentTarget found')
    }
    
    if (this.hasQuestionContextTarget) {
      this.questionContextTarget.innerHTML = `
        <div class="completion-context">
          View full results in <strong>Work Items</strong>
        </div>
      `
    }
    
    // Hide answer form, show action buttons
    if (this.hasActiveQuestionTarget) {
      const answerForm = this.activeQuestionTarget.querySelector('.answer-form')
      if (answerForm) {
        answerForm.innerHTML = `
          <div class="completion-actions">
            <button class="btn btn-outline-secondary btn-sm dismiss-btn" data-action="question-queue#dismissCompletion">
              Dismiss
            </button>
            <button class="btn btn-primary btn-sm" data-action="question-queue#viewWorkItems">
              📥 View Work Items
            </button>
          </div>
        `
        console.log('✅ Updated answer form with action buttons')
      }
    }
    
    // Trigger work inbox refresh
    window.dispatchEvent(new CustomEvent('work-inbox-update', {
      detail: { type: 'completion', agent_name: completion.agent_name }
    }))
  }
  
  dismissCompletion() {
    // Remove the current completion and show next item
    if (this.completions && this.completions.length > 0) {
      this.completions.shift()
      this.updateBadge()
    }
    
    // Show next completion or question
    if (this.completions && this.completions.length > 0) {
      this.showCompletionInOverlay(this.completions[0])
    } else if (this.questions.length > 0) {
      this.showActiveQuestion(this.questions[0])
    } else {
      this.showEmptyState()
    }
  }
  
  // Navigate to work items
  viewWorkItems() {
    if (this.completionTimeout) {
      clearTimeout(this.completionTimeout)
    }
    this.closeOverlay()
    this.restoreAnswerForm()
    
    // Load work inbox canvas
    if (window.scoutLoadCanvas) {
      window.scoutLoadCanvas('work_inbox', {})
    }
  }
  
  // Restore the answer form after showing completion
  restoreAnswerForm() {
    if (this.hasActiveQuestionTarget) {
      const answerForm = this.activeQuestionTarget.querySelector('.answer-form')
      if (answerForm) {
        answerForm.innerHTML = `
          <div class="attachment-preview hidden" data-question-queue-target="attachmentPreview">
            <div class="attachment-item">
              <img src="" alt="Attachment preview" data-question-queue-target="attachmentImage">
              <button type="button" class="btn-remove-attachment" data-action="question-queue#removeAttachment">
                <i data-lucide="x" style="width: 14px; height: 14px;"></i>
              </button>
            </div>
          </div>
          
          <div class="answer-input-wrapper">
            <textarea 
              class="form-control answer-input" 
              data-question-queue-target="answerInput"
              placeholder="Type your answer... (paste images with Ctrl/Cmd+V)"
              rows="3"
              data-action="keydown->question-queue#handleKeydown paste->question-queue#handlePaste"
            ></textarea>
          </div>
          
          <div class="answer-actions">
            <div class="action-group-left">
              <button class="btn btn-outline-secondary btn-sm skip-btn" 
                      data-action="question-queue#skipQuestion"
                      title="Skip this question">
                <i data-lucide="skip-forward" style="width: 14px; height: 14px;"></i>
                Skip
              </button>
              <button class="btn btn-outline-secondary btn-sm upload-btn"
                      data-action="question-queue#triggerFileUpload"
                      title="Attach a file or screenshot">
                <i data-lucide="paperclip" style="width: 14px; height: 14px;"></i>
                Attach
              </button>
            </div>
            <button class="btn btn-primary btn-sm answer-btn" 
                    data-action="question-queue#submitAnswer">
              <i data-lucide="send" style="width: 14px; height: 14px;"></i>
              Send Answer
            </button>
          </div>
        `
        if (typeof lucide !== 'undefined') {
          lucide.createIcons()
        }
      }
    }
  }

  // ============================================
  // UI UPDATES
  // ============================================

  updateBadge() {
    // Count includes both pending questions AND unread completions
    const questionCount = this.questions.length
    const completionCount = (this.completions || []).length
    const count = questionCount + completionCount
    
    console.log("🔄 Updating badge, questions:", questionCount, "completions:", completionCount, "total:", count)
    
    if (this.hasCountTarget) {
      this.countTarget.textContent = count
    }
    
    if (count > 0) {
      this.showBadge()
      if (this.hasBadgeTarget) {
        this.badgeTarget.classList.add('has-questions')
      }
    } else {
      this.hideBadge()
      if (this.hasBadgeTarget) {
        this.badgeTarget.classList.remove('has-questions')
      }
    }
  }

  showBadge() {
    console.log("📍 Showing badge")
    if (this.hasBadgeTarget) {
      this.badgeTarget.classList.remove('hidden')
      // Ensure icons are rendered
      if (typeof lucide !== 'undefined') {
        lucide.createIcons()
      }
    }
  }

  hideBadge() {
    console.log("📍 Hiding badge")
    if (this.hasBadgeTarget) {
      this.badgeTarget.classList.add('hidden')
    }
  }
  
  pulseBadge() {
    // Add a pulse animation to draw attention
    if (this.hasBadgeTarget) {
      this.badgeTarget.classList.add('pulse-attention')
      setTimeout(() => {
        this.badgeTarget.classList.remove('pulse-attention')
      }, 1000)
    }
  }

  updateQuestionList() {
    if (!this.hasListTarget) return
    
    if (this.questions.length <= 1) {
      this.listTarget.innerHTML = ''
      return
    }
    
    // Show list of questions when multiple
    this.listTarget.innerHTML = this.questions.map((q, index) => `
      <div class="question-list-item ${q.id === this.currentQuestionId ? 'active' : ''}" 
           data-question-id="${q.id}"
           data-action="click->question-queue#selectQuestion">
        <span class="item-icon">${q.agent_icon || '🤖'}</span>
        <div class="item-info">
          <div class="item-agent">${q.agent_name || 'Agent'}</div>
          <div class="item-preview">${q.question?.substring(0, 50)}...</div>
        </div>
      </div>
    `).join('')
  }

  showActiveQuestion(question) {
    if (!question) {
      this.showEmptyState()
      return
    }
    
    this.currentQuestionId = question.id
    
    if (this.hasActiveQuestionTarget) {
      this.activeQuestionTarget.classList.remove('hidden')
    }
    
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.add('hidden')
    }
    
    // Update UI
    if (this.hasAgentIconTarget) {
      this.agentIconTarget.textContent = question.agent_icon || '🤖'
    }
    
    if (this.hasAgentNameTarget) {
      this.agentNameTarget.textContent = question.agent_name || 'Agent'
    }
    
    if (this.hasQuestionTimeTarget) {
      this.questionTimeTarget.textContent = this.formatTime(question.created_at)
    }
    
    if (this.hasQuestionContentTarget) {
      this.questionContentTarget.textContent = question.question
    }
    
    if (this.hasQuestionContextTarget) {
      const context = question.context
      if (context && Object.keys(context).length > 0) {
        this.questionContextTarget.textContent = `Context: ${JSON.stringify(context)}`
      } else {
        this.questionContextTarget.textContent = ''
      }
    }
    
    if (this.hasAnswerInputTarget) {
      this.answerInputTarget.value = ''
      this.answerInputTarget.focus()
    }
    
    this.updateQuestionList()
  }

  showEmptyState() {
    if (this.hasActiveQuestionTarget) {
      this.activeQuestionTarget.classList.add('hidden')
    }
    
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.remove('hidden')
    }
    
    // Auto-close overlay after a moment
    setTimeout(() => {
      if (this.questions.length === 0) {
        this.closeOverlay()
      }
    }, 1500)
  }

  formatTime(isoString) {
    if (!isoString) return ''
    const date = new Date(isoString)
    const now = new Date()
    const diff = (now - date) / 1000 // seconds
    
    if (diff < 60) return 'just now'
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
    return date.toLocaleDateString()
  }

  // ============================================
  // USER ACTIONS
  // ============================================

  toggleOverlay() {
    if (this.hasOverlayTarget) {
      const wasHidden = this.overlayTarget.classList.contains('hidden')
      this.overlayTarget.classList.toggle('hidden')
      
      // When opening the overlay, show the appropriate content
      if (wasHidden) {
        console.log('📬 Opening overlay, completions:', this.completions?.length, 'questions:', this.questions?.length)
        
        // Show completions first if any, otherwise show questions
        if (this.completions && this.completions.length > 0) {
          console.log('📬 Showing completion in overlay')
          this.showCompletionInOverlay(this.completions[0])
        } else if (this.questions && this.questions.length > 0) {
          this.showActiveQuestion(this.questions[0])
        } else {
          this.showEmptyState()
        }
        
        // Refresh icons in overlay
        if (typeof lucide !== 'undefined') {
          lucide.createIcons()
        }
      }
    }
  }

  closeOverlay() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add('hidden')
    }
  }
  
  openOverlay() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.remove('hidden')
      
      // Show completions first if any, otherwise show questions
      if (this.completions && this.completions.length > 0) {
        console.log('📬 Showing', this.completions.length, 'completions')
        this.showCompletionInOverlay(this.completions[0])
      } else if (this.questions.length > 0) {
        this.showActiveQuestion(this.questions[0])
      }
      
      // Refresh icons in overlay
      if (typeof lucide !== 'undefined') {
        lucide.createIcons()
      }
    }
  }

  selectQuestion(event) {
    const questionId = parseInt(event.currentTarget.dataset.questionId)
    const question = this.questions.find(q => q.id === questionId)
    if (question) {
      this.showActiveQuestion(question)
    }
  }

  handleKeydown(event) {
    // Cmd/Ctrl + Enter to submit
    if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
      event.preventDefault()
      this.submitAnswer()
    }
    // Escape to close
    if (event.key === 'Escape') {
      this.closeOverlay()
    }
  }

  async submitAnswer() {
    if (!this.currentQuestionId || !this.hasAnswerInputTarget) return
    
    const answer = this.answerInputTarget.value.trim()
    if (!answer) {
      this.answerInputTarget.focus()
      return
    }
    
    const button = this.element.querySelector('.answer-btn')
    if (button) {
      button.disabled = true
      button.innerHTML = '<i data-lucide="loader-2" class="icon-spin" style="width: 14px; height: 14px;"></i> Sending...'
    }
    
    try {
      const response = await fetch(`/scout/questions/${this.currentQuestionId}/answer`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ answer: answer })
      })
      
      if (response.ok) {
        console.log('✅ Answer submitted for question:', this.currentQuestionId)
        
        // Remove from local list (broadcast will also trigger update)
        this.questions = this.questions.filter(q => q.id !== this.currentQuestionId)
        this.currentQuestionId = null
        
        // Show next question or empty state
        if (this.questions.length > 0) {
          this.showActiveQuestion(this.questions[0])
        } else {
          this.showEmptyState()
        }
        
        this.updateBadge()
      } else {
        const error = await response.json()
        console.error('Failed to submit answer:', error)
        alert('Failed to submit answer. Please try again.')
      }
    } catch (error) {
      console.error('Error submitting answer:', error)
      alert('Network error. Please try again.')
    } finally {
      if (button) {
        button.disabled = false
        button.innerHTML = '<i data-lucide="send" style="width: 14px; height: 14px;"></i> Send Answer'
        if (typeof lucide !== 'undefined') lucide.createIcons()
      }
    }
  }

  async skipQuestion() {
    if (!this.currentQuestionId) return
    
    const reason = prompt('Why are you skipping this question? (optional)')
    
    try {
      const response = await fetch(`/scout/questions/${this.currentQuestionId}/skip`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ reason: reason })
      })
      
      if (response.ok) {
        console.log('⏭️ Skipped question:', this.currentQuestionId)
        
        // Remove from local list
        this.questions = this.questions.filter(q => q.id !== this.currentQuestionId)
        this.currentQuestionId = null
        
        // Show next or empty
        if (this.questions.length > 0) {
          this.showActiveQuestion(this.questions[0])
        } else {
          this.showEmptyState()
        }
        
        this.updateBadge()
      }
    } catch (error) {
      console.error('Error skipping question:', error)
    }
  }

  // ============================================
  // FILE UPLOAD & PASTE HANDLING
  // ============================================

  triggerFileUpload() {
    if (this.hasFileInputTarget) {
      this.fileInputTarget.click()
    }
  }

  handleFileSelect(event) {
    const file = event.target.files[0]
    if (file) {
      this.processFile(file)
    }
  }

  handlePaste(event) {
    const items = event.clipboardData?.items
    if (!items) return

    for (const item of items) {
      if (item.type.startsWith('image/')) {
        event.preventDefault()
        const file = item.getAsFile()
        if (file) {
          console.log('📋 Pasted image:', file.type, file.size)
          this.processFile(file)
        }
        return
      }
    }
  }

  processFile(file) {
    // Validate file size (max 10MB)
    if (file.size > 10 * 1024 * 1024) {
      alert('File is too large. Maximum size is 10MB.')
      return
    }

    // Store the file for upload
    this.pendingAttachment = file
    console.log('📎 Attachment ready:', file.name, file.type)

    // Show preview for images
    if (file.type.startsWith('image/')) {
      const reader = new FileReader()
      reader.onload = (e) => {
        if (this.hasAttachmentImageTarget) {
          this.attachmentImageTarget.src = e.target.result
        }
        if (this.hasAttachmentPreviewTarget) {
          this.attachmentPreviewTarget.classList.remove('hidden')
        }
        if (typeof lucide !== 'undefined') {
          lucide.createIcons()
        }
      }
      reader.readAsDataURL(file)
    } else {
      // For non-images, show a generic preview
      if (this.hasAttachmentPreviewTarget) {
        this.attachmentPreviewTarget.innerHTML = `
          <div class="attachment-item file-attachment">
            <span class="file-name">${file.name}</span>
            <button type="button" class="btn-remove-attachment" data-action="question-queue#removeAttachment">
              <i data-lucide="x" style="width: 14px; height: 14px;"></i>
            </button>
          </div>
        `
        this.attachmentPreviewTarget.classList.remove('hidden')
        if (typeof lucide !== 'undefined') {
          lucide.createIcons()
        }
      }
    }
  }

  removeAttachment() {
    this.pendingAttachment = null
    if (this.hasAttachmentPreviewTarget) {
      this.attachmentPreviewTarget.classList.add('hidden')
    }
    if (this.hasFileInputTarget) {
      this.fileInputTarget.value = ''
    }
    console.log('🗑️ Attachment removed')
  }

  // Override submitAnswer to include attachment
  async submitAnswer() {
    if (!this.currentQuestionId || !this.hasAnswerInputTarget) return
    
    const answer = this.answerInputTarget.value.trim()
    if (!answer && !this.pendingAttachment) {
      this.answerInputTarget.focus()
      return
    }
    
    const button = this.element.querySelector('.answer-btn')
    if (button) {
      button.disabled = true
      button.innerHTML = '<i data-lucide="loader-2" class="icon-spin" style="width: 14px; height: 14px;"></i> Sending...'
    }
    
    try {
      // Use FormData to support file uploads
      const formData = new FormData()
      formData.append('answer', answer)
      
      if (this.pendingAttachment) {
        formData.append('attachment', this.pendingAttachment)
        console.log('📤 Uploading attachment with answer:', this.pendingAttachment.name)
      }
      
      const response = await fetch(`/scout/questions/${this.currentQuestionId}/answer`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: formData
      })
      
      if (response.ok) {
        console.log('✅ Answer submitted for question:', this.currentQuestionId)
        
        // Clear attachment
        this.removeAttachment()
        
        // Remove from local list (broadcast will also trigger update)
        this.questions = this.questions.filter(q => q.id !== this.currentQuestionId)
        this.currentQuestionId = null
        
        // Show next question or empty state
        if (this.questions.length > 0) {
          this.showActiveQuestion(this.questions[0])
        } else {
          this.showEmptyState()
        }
        
        this.updateBadge()
      } else {
        const error = await response.json()
        console.error('Failed to submit answer:', error)
        alert('Failed to submit answer. Please try again.')
      }
    } catch (error) {
      console.error('Error submitting answer:', error)
      alert('Network error. Please try again.')
    } finally {
      if (button) {
        button.disabled = false
        button.innerHTML = '<i data-lucide="send" style="width: 14px; height: 14px;"></i> Send Answer'
        if (typeof lucide !== 'undefined') lucide.createIcons()
      }
    }
  }
}

