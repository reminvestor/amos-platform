import consumer from "./consumer"

// Minimal ActionCable subscription to satisfy client code
const JobNotificationChannel = consumer.subscriptions.create("JobNotificationChannel", {
  connected() {
    console.log("✅ JobNotificationChannel connected")
  },

  disconnected() {
    console.log("❌ JobNotificationChannel disconnected")
  },

  received(data) {
    console.log("📨 JobNotificationChannel received:", data)
  }
})

export default JobNotificationChannel




