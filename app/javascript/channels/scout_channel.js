// Initialize Scout channel subscription when DOM is loaded
console.log("📡 ScoutChannel JS file loaded")

function initializeScoutChannel() {
  console.log("📡 ScoutChannel: Attempting to initialize...")
  
  const sessionId = document.querySelector('[data-scout-session-id]')?.dataset?.scoutSessionId
  
  if (!sessionId) {
    console.log("ScoutChannel: No Scout session ID found, skipping channel subscription")
    return false
  }
  
  console.log("📡 ScoutChannel: Found session ID:", sessionId)

  // Use the global App.cable consumer that's already created
  if (typeof App === 'undefined' || !App.cable) {
    console.error("ScoutChannel: ActionCable not available, App:", typeof App, "App.cable:", typeof App?.cable)
    return false
  }
  
  console.log("📡 ScoutChannel: App.cable is available")

  // Allow both Scout and parallel tasks canvas to have subscriptions
  // They handle different message types and won't interfere with each other

  // Clean up any existing subscription
  if (window.scoutChannelSubscription) {
    console.log("ScoutChannel: Cleaning up existing subscription")
    window.scoutChannelSubscription.unsubscribe()
  }

  console.log("ScoutChannel: Creating subscription for session:", sessionId)
  
  // Expose message handler globally so Fresh Start can reuse it
  window.handleScoutChannelMessage = function(data) {
    console.log("📨 ScoutChannel: Received:", data)
    console.log("📨 ScoutChannel: Message type is:", data.type)
    
    // Special logging for load_canvas to debug production issue
    if (data.type === 'load_canvas') {
      console.log("🎨 LOAD_CANVAS MESSAGE RECEIVED:", JSON.stringify(data))
    }
    
    // Special logging for question_queue_update
    if (data.type === 'question_queue_update') {
      console.log("🔔 QUESTION_QUEUE_UPDATE RECEIVED:", JSON.stringify(data))
    }
    
    // Handle different message types
    switch(data.type) {
      // ==== AMOS MESSAGE TYPES ====
      case 'amos_response':
      case 'assistant_message':
        // Stream assistant messages from Amos
        console.log("ScoutChannel: Amos response received:", data.content)
        if (window.streamAmosResponse) {
          window.streamAmosResponse(data)
        } else if (window.streamTaskContent) {
          // Fallback to task content streaming
          window.streamTaskContent({
            content: data.content,
            type: 'assistant',
            metadata: data.metadata
          })
        }
        break
        
      case 'job_status':
        // Handle job status updates from Amos
        console.log("ScoutChannel: Job status update:", data)
        console.log("🤖 Agent Status:", data.message || data.status)
        if (window.handleJobStatus) {
          window.handleJobStatus(data)
        } else if (window.handleParallelTaskUpdate) {
          // Map to parallel task update format
          window.handleParallelTaskUpdate({
            type: 'task_progress',
            task_id: data.job_id,
            status: data.status,
            progress: data.progress,
            message: data.message
          })
        }
        break
        
      case 'input_request':
      case 'agent_question':
        // Handle input requests from Amos agents
        console.log("ScoutChannel: Input request from agent:", data)
        
        // Note: Questions are now handled by the question queue system
        // The QuestionQueueController receives question_queue_update messages
        // and manages the badge/overlay UI. We no longer display questions
        // directly in chat to avoid duplicates.
        
        // Legacy handlers (kept for backwards compatibility if needed)
        if (window.handleAmosInputRequest) {
          window.handleAmosInputRequest(data)
        } else if (window.handleTaskNeedsInput) {
          // Map to existing input handler
          window.handleTaskNeedsInput({
            task_id: data.job_id || data.execution_id,
            prompt: data.prompt || data.question,
            options: data.options
          })
        }
        break
        
      case 'load_canvas':
        // Handle canvas updates from Amos
        console.log("ScoutChannel: Canvas update:", data)
        const canvasName = data.canvas_name || data.canvas
        const forceRefresh = data.force_refresh || false
        
        // Skip if canvasName is empty/null
        if (!canvasName) {
          console.log("ScoutChannel: Canvas name is empty/null, skipping canvas update")
          break
        }
        
        if (window.scoutLoadCanvas) {
          window.scoutLoadCanvas(canvasName, data.canvas_data, forceRefresh)
        } else if (window.loadCanvas) {
          window.loadCanvas(canvasName, data.canvas_data)
        } else {
          // Try to find Scout controller and call its method directly
          const scoutController = document.querySelector('[data-controller="scout"]')
          if (scoutController && scoutController._controller) {
            scoutController._controller.loadScoutCanvas(canvasName, data.canvas_data)
          }
        }
        break
      
      // ==== LEGACY TASK MESSAGE TYPES ====  
      case 'task_progress':
      case 'task_completed':
      case 'task_failed':
      case 'agent_plugin_completed':
      case 'agent_plugin_failed':
        // Route to parallel task handler if available
        if (window.handleParallelTaskUpdate) {
          // Normalize agent plugin events to task events
          if (data.type.startsWith('agent_plugin_')) {
            data.type = data.type.replace('agent_plugin_', 'task_');
            data.task_id = data.execution_id;
            data.status = data.type === 'task_completed' ? 'completed' : 'failed';
          }
          window.handleParallelTaskUpdate(data)
        }
        break
        
      case 'task_result':
        // Stream task results to main chat
        console.log("ScoutChannel: Task result received:", data)
        if (window.streamTaskResult) {
          window.streamTaskResult(data)
        }
        break
        
      case 'task_needs_input':
        // Handle workflow tasks that need user input
        console.log("ScoutChannel: Task needs input:", data)
        if (window.handleTaskNeedsInput) {
          window.handleTaskNeedsInput(data)
        }
        break
        
      case 'task_content':
        // Stream content from tasks to chat
        console.log("ScoutChannel: Task content received:", data)
        if (window.streamTaskContent) {
          window.streamTaskContent(data)
        }
        break

      // ==== QUESTION QUEUE MESSAGE TYPES ====
      case 'question_queue_update':
        // Handle question queue updates for the async question badge/overlay
        console.log("ScoutChannel: Question queue update:", data)
        window.dispatchEvent(new CustomEvent('question-queue-update', {
          detail: {
            action: data.action,
            question: data.question,
            question_id: data.question_id,
            pending_count: data.pending_count,
            completion: data.completion  // For agent completion notifications
          }
        }))
        break
      
      // ==== WORK ITEM / AGENT COMPLETION MESSAGE TYPES ====
      case 'work_item_notification':
      case 'agent_execution_completed':
        // Agent completed - update work inbox badge
        console.log("ScoutChannel: Work item notification:", data)
        
        // Update work inbox badge
        window.dispatchEvent(new CustomEvent('work-inbox-update', {
          detail: {
            type: 'new_item',
            agent_name: data.agent_name,
            execution_id: data.execution_id
          }
        }))
        break
        
      default:
        console.log("ScoutChannel: Unknown message type:", data.type)
    }
  }

  window.scoutChannelSubscription = App.cable.subscriptions.create({
    channel: "ScoutChannel",
    session_id: sessionId
  }, {
    connected() {
      console.log("✅ ScoutChannel: Connected for session:", sessionId)
    },

    disconnected() {
      console.log("❌ ScoutChannel: Disconnected")
    },

    received(data) {
      window.handleScoutChannelMessage(data)
    }
  })
  
  return true
}

// Try to initialize on multiple events to ensure it works
// turbo:load - for Turbo navigation
document.addEventListener('turbo:load', function() {
  console.log("📡 ScoutChannel: turbo:load event fired")
  initializeScoutChannel()
})

// DOMContentLoaded - for regular page loads
document.addEventListener('DOMContentLoaded', function() {
  console.log("📡 ScoutChannel: DOMContentLoaded event fired")
  initializeScoutChannel()
})

// Also try immediately in case DOM is already loaded
if (document.readyState === 'complete' || document.readyState === 'interactive') {
  console.log("📡 ScoutChannel: DOM already loaded, initializing immediately")
  // Small delay to ensure App.cable is ready
  setTimeout(initializeScoutChannel, 100)
}
