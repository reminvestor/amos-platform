import { createConsumer } from "@rails/actioncable"

const consumer = createConsumer()

// Subscribe to document updates for the entity
const documentsSubscription = consumer.subscriptions.create("DocumentsChannel", {
  connected() {
    console.log("Connected to documents channel")
  },

  disconnected() {
    console.log("Disconnected from documents channel")
  },

  received(data) {
    // Handle different types of updates
    switch(data.action) {
      case 'update_status':
        this.updateDocumentStatus(data)
        break
      case 'update_progress':
        this.updateDocumentProgress(data)
        break
      case 'processing_complete':
        this.handleProcessingComplete(data)
        break
    }
  },

  updateDocumentStatus(data) {
    // Update document status in list view
    const listRow = document.querySelector(`tr[data-document-id="${data.document_id}"]`)
    if (listRow) {
      const statusCell = listRow.querySelector('.document-status')
      if (statusCell) {
        statusCell.innerHTML = data.status_html
      }
    }

    // Update document status in grid view
    const gridCard = document.querySelector(`.document-card[data-document-id="${data.document_id}"]`)
    if (gridCard) {
      const preview = gridCard.querySelector('.document-preview')
      if (preview) {
        preview.innerHTML = data.preview_html
      }
      
      const badges = gridCard.querySelector('.document-badges')
      if (badges) {
        // Update processing badge
        const processingBadge = badges.querySelector('.badge-warning, .badge-danger, .badge-success')
        if (processingBadge) {
          processingBadge.className = data.badge_class
          processingBadge.textContent = data.badge_text
        }
      }
    }
  },

  updateDocumentProgress(data) {
    // Update progress bars
    const progressBars = document.querySelectorAll(`[data-document-id="${data.document_id}"] .progress-bar`)
    progressBars.forEach(bar => {
      bar.style.width = `${data.progress}%`
      bar.setAttribute('aria-valuenow', data.progress)
    })

    // Update progress text
    const progressTexts = document.querySelectorAll(`[data-document-id="${data.document_id}"] .processing-text`)
    progressTexts.forEach(text => {
      text.textContent = data.stage_description
    })

    // Update embedding stats if present
    const embeddingStats = document.querySelector(`[data-document-id="${data.document_id}"] .embedding-stats`)
    if (embeddingStats && data.embedding_stats) {
      embeddingStats.innerHTML = data.embedding_stats
    }
  },

  handleProcessingComplete(data) {
    // Update to completed state
    this.updateDocumentStatus(data)
    
    // If we're on the document detail page, reload to show content
    const documentViewer = document.querySelector(`.document-viewer[data-document-id="${data.document_id}"]`)
    if (documentViewer && data.redirect_url) {
      // Show success message before redirecting
      const message = document.createElement('div')
      message.className = 'alert alert-success admin-alert'
      message.innerHTML = '<i data-lucide="check-circle" class="me-2"></i>Processing complete! Reloading...'
      documentViewer.prepend(message)
      
      // Reload after a short delay
      setTimeout(() => {
        window.location.href = data.redirect_url
      }, 1500)
    }
  }
})

// Function to subscribe to a specific document
window.subscribeToDocument = function(documentId) {
  consumer.subscriptions.create(
    { channel: "DocumentsChannel", document_id: documentId },
    {
      received(data) {
        documentsSubscription.received(data)
      }
    }
  )
}

export default documentsSubscription
