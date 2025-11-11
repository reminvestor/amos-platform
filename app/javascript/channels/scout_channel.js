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

  // Don't create subscription if we're in a parallel tasks canvas (it will create its own)
  if (document.getElementById('parallel-tasks-panel')) {
    console.log("ScoutChannel: Parallel tasks panel detected, skipping main channel subscription")
    return
  }

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
      
      // Handle different message types
      switch(data.type) {
        case 'task_progress':
        case 'task_completed':
        case 'task_failed':
          // Route to parallel task handler if available
          if (window.handleParallelTaskUpdate) {
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
          
        default:
          console.log("ScoutChannel: Unknown message type:", data.type)
      }
    }
  })
})
