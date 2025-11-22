// Initialize Scout channel subscription when DOM is loaded
document.addEventListener('turbo:load', function() {
  const sessionId = document.querySelector('[data-scout-session-id]')?.dataset?.scoutSessionId
  
  if (!sessionId) {
    console.log("ScoutChannel: No Scout session ID found, skipping channel subscription")
    return
  }

  // Use the global App.cable consumer that's already created
  if (typeof App === 'undefined' || !App.cable) {
    console.error("ScoutChannel: ActionCable not available")
    return
  }

  // Allow both Scout and parallel tasks canvas to have subscriptions
  // They handle different message types and won't interfere with each other

  // Clean up any existing subscription
  if (window.scoutChannelSubscription) {
    console.log("ScoutChannel: Cleaning up existing subscription")
    window.scoutChannelSubscription.unsubscribe()
  }

  console.log("ScoutChannel: Creating subscription for session:", sessionId)
  
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
      console.log("📨 ScoutChannel: Received:", data)
      
      // Special logging for load_canvas to debug production issue
      if (data.type === 'load_canvas') {
        console.log("🎨 LOAD_CANVAS MESSAGE RECEIVED:", JSON.stringify(data))
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
          
          // If it's an agent question, display it in the chat
          if (data.type === 'agent_question' && window.streamTaskContent) {
            window.streamTaskContent({
              content: data.question,
              type: 'assistant',
              metadata: {
                from_agent: true,
                agent_name: data.agent_name,
                execution_id: data.execution_id,
                awaiting_response: true
              }
            })
          }

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
          
        default:
          console.log("ScoutChannel: Unknown message type:", data.type)
      }
    }
  })
})
