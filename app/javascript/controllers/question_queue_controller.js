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
    "emptyState"
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
    this.currentQuestionId = null
    
    // Listen for question queue updates from ActionCable
    this.boundHandleQueueUpdate = this.handleQueueUpdate.bind(this)
    window.addEventListener('question-queue-update', this.boundHandleQueueUpdate)
    
    // Initialize lucide icons in the component
    if (typeof lucide !== 'undefined') {
      lucide.createIcons()
    }
    
    // Load initial questions
    this.loadPendingQuestions()
  }

  disconnect() {
    if (this.boundHandleQueueUpdate) {
      window.removeEventListener('question-queue-update', this.boundHandleQueueUpdate)
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
    const { action, question, question_id, pending_count } = event.detail
    
    console.log('📬 Question queue update received:', {
      action,
      question_id: question_id || question?.id,
      pending_count,
      question: question
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
        
      default:
        console.warn('📬 Unknown queue update action:', action)
    }
    
    this.updateQuestionList()
  }

  // ============================================
  // UI UPDATES
  // ============================================

  updateBadge() {
    const count = this.questions.length
    
    console.log("🔄 Updating badge, question count:", count)
    
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
      this.overlayTarget.classList.toggle('hidden')
      
      if (!this.overlayTarget.classList.contains('hidden')) {
        // Refresh icons in overlay
        if (typeof lucide !== 'undefined') {
          lucide.createIcons()
        }
        
        // Focus answer input
        if (this.hasAnswerInputTarget) {
          this.answerInputTarget.focus()
        }
      }
    }
  }

  closeOverlay() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add('hidden')
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
}

