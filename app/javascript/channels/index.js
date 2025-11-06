// Import all the channels and set up ActionCable
import { createConsumer } from "@rails/actioncable"

// Create the ActionCable consumer
window.App = {}
App.cable = createConsumer()

// Also make createConsumer available globally for debugging
window.createConsumer = createConsumer

console.log("📡 ActionCable consumer created:", App.cable)
console.log("📡 ActionCable URL:", App.cable.url)

// Import specific channels
import "./documents_channel" 