import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

// Cache bust: v3 models + comprehensive error handling - 2025-11-17b

/**
 * VoiceAssistantController - Handles voice input for Scout chat
 *
 * Features:
 * - WebRTC audio capture with VAD
 * - Direct Deepgram WebSocket connection for STT (Speech-to-Text)
 * - Integration with Scout chat interface
 * - Scout responds via text in chat UI (no voice output)
 *
 * Usage:
 *   <div data-controller="voice-assistant">
 *     <button data-action="click->voice-assistant#toggleVoice">🎤</button>
 *   </div>
 */
export default class extends Controller {
  static targets = ["button", "status", "waveform"]

  connect() {
    console.log("VoiceAssistant controller connected")

    this.isActive = false
    this.isListening = false
    this.continuousMode = false  // Continuous listening for multiple wake words
    this.waitingForWakeWord = false  // Waiting for next "Hey Amos"

    this.voiceSessionId = null
    this.elevenLabsSocket = null  // Eleven Labs Scribe v3 WebSocket (primary STT)
    this.deepgramSocket = null     // Deepgram WebSocket (fallback STT)
    this.currentSTTProvider = null // Track which STT provider is active
    this.mediaStream = null
    this.audioContext = null
    this.voiceChannel = null
    this.listeningTimeout = null
    this.continuousTimeout = null  // Timeout for continuous mode

    // Transcript buffering (handle Deepgram splitting speech)
    this.transcriptBuffer = ""
    this.transcriptBufferTimeout = null

    // Pre-initialization cache (Eleven Labs only - Deepgram loaded on-demand if needed)
    this.cachedSession = null
    this.cachedElevenLabsCreds = null  // Cache Eleven Labs credentials (primary STT)
    this.isPreInitialized = false

    // Performance tracking
    this.performanceMetrics = {
      speechStartTime: null,
      transcriptReceivedTime: null,
      scoutSentTime: null,
      scoutResponseTime: null,
      totalLatency: null
    }

    // Pre-initialize on page load for instant mic activation
    this.preInitialize()
  }

  /**
   * Pre-initialize session and credentials on page load
   * This makes mic button activation nearly instant
   * Fetches Eleven Labs credentials (primary STT provider)
   */
  async preInitialize() {
    try {
      console.log("🚀 Pre-initializing voice assistant (background)...")

      // Create session in background
      this.cachedSession = await this.createVoiceSession()
      console.log("✅ Pre-initialized session:", this.cachedSession.session_id)

      // Pre-fetch Eleven Labs Scribe v3 credentials (primary STT)
      this.cachedElevenLabsCreds = await fetch(`/api/voice/sessions/${this.cachedSession.session_id}/eleven_labs_credentials`, {
        headers: {
          "X-CSRF-Token": this.csrfToken()
        }
      }).then(r => r.json())

      console.log("✅ Pre-fetched Eleven Labs Scribe v3 credentials")
      this.isPreInitialized = true
      console.log("🎉 Voice assistant pre-initialized! Mic button will be instant.")

    } catch (error) {
      console.warn("⚠️ Pre-initialization failed (will initialize on first click):", error)
      this.isPreInitialized = false
    }
  }

  disconnect() {
    this.stopVoice()
  }

  /**
   * Toggle voice assistant on/off
   */
  async toggleVoice() {
    if (this.isActive) {
      // Use fullStop() to exit continuous mode completely
      this.fullStop()
    } else {
      await this.startVoice()
    }
  }

  /**
   * Start voice assistant session
   * OPTIMIZED: Pre-initialized session + credentials = INSTANT activation!
   */
  async startVoice() {
    // Prevent starting if already active
    if (this.isActive || this.isListening) {
      console.warn("⚠️ Voice assistant already active, ignoring start request")
      return
    }

    try {
      const startTime = performance.now()
      console.log("🎤 Starting voice assistant...")
      
      // Unlock iOS audio during this user gesture (required for TTS playback later)
      this.unlockIOSAudio()
      
      this.updateStatus("Requesting microphone access...")

      // STEP 1: Request microphone FIRST (immediate user feedback)
      console.log("Step 1: Requesting microphone permission...")
      await this.startAudioCapture()
      console.log("✅ Microphone ready")

      // STEP 2: Use cached session or create new one
      if (this.isPreInitialized && this.cachedSession) {
        console.log("⚡ Using pre-initialized session (INSTANT):", this.cachedSession.session_id)
        this.voiceSessionId = this.cachedSession.session_id

        // Use cached Eleven Labs credentials (primary STT provider)
        const elevenLabsCreds = this.cachedElevenLabsCreds

        // Clear cache after using it (session will be ended after use)
        this.cachedSession = null
        this.cachedElevenLabsCreds = null
        this.isPreInitialized = false
        console.log("🔄 Cache cleared (will re-initialize after this session)")

        // Connect Action Cable in parallel with WebSocket setup
        this.connectVoiceChannel() // Fire and forget

        // Attempt Eleven Labs first (primary), with Deepgram fallback
        await this.connectWithFallback(elevenLabsCreds)

      } else {
        // Fallback: initialize normally if pre-init failed
        console.log("Step 2: Creating voice session (fallback)...")
        const session = await this.createVoiceSession()
        this.voiceSessionId = session.session_id
        console.log("✅ Voice session created:", this.voiceSessionId)

        // Parallelize operations
        console.log("Step 3: Connecting services in parallel...")
        const [elevenLabsCreds, _] = await Promise.all([
          this.getElevenLabsCredentials(),
          this.connectVoiceChannel()
        ])

        console.log("✅ All services connected")
        // Attempt Eleven Labs first (primary), with Deepgram fallback
        await this.connectWithFallback(elevenLabsCreds)
      }

      const initTime = performance.now() - startTime
      console.log(`⚡ TOTAL INITIALIZATION: ${initTime.toFixed(0)}ms`)
      console.log(`✅ STT Provider Connected (${this.currentSTTProvider})`)

      this.isActive = true
      this.updateStatus("🎤 Listening... Say 'Hey Amos' + your command")
      this.updateButton("active")
      console.log("🎉 Voice assistant fully active and ready!")

      // Enable continuous mode by default
      this.continuousMode = true
      this.waitingForWakeWord = false  // First command doesn't require wake word

      // Set continuous mode timeout (5 minutes)
      this.resetContinuousTimeout()

      // Auto-stop after 20 seconds if no speech detected
      this.listeningTimeout = setTimeout(() => {
        console.log("⏱️ 20-second listening timeout reached - stopping voice assistant")
        this.updateStatus("Listening timeout - click mic to speak again")
        this.fullStop()
      }, 20000) // 20 seconds

    } catch (error) {
      console.error("❌ Failed to start voice assistant:", error)
      console.error("Error stack:", error.stack)
      this.updateStatus(`Error: ${error.message}`)
      this.stopVoice()
    }
  }

  /**
   * Stop voice assistant session
   */
  async stopVoice() {
    // Prevent multiple calls to stopVoice
    if (!this.isActive && !this.isListening) {
      console.log("⚠️ Voice assistant already stopped, skipping cleanup")
      return
    }

    // In continuous mode, don't fully stop - just wait for next command
    if (this.continuousMode) {
      console.log("🔄 Continuous mode: Ready for next command...")
      this.waitingForWakeWord = true
      this.updateStatus("Ready for next command (wake word optional)...")
      this.updateButton("listening")  // Keep button showing active/listening

      // Reset continuous timeout (5 min auto-stop)
      this.resetContinuousTimeout()
      return  // Don't run cleanup below
    }

    console.log("🛑 Stopping voice assistant - cleaning up resources...")

    // Set flags first to prevent race conditions
    this.isActive = false
    this.isListening = false

    // Add small delay to ensure cleanup completes before allowing restart
    await new Promise(resolve => setTimeout(resolve, 100))

    // Clear listening timeout
    if (this.listeningTimeout) {
      clearTimeout(this.listeningTimeout)
      this.listeningTimeout = null
    }

    // Clear continuous mode timeout
    if (this.continuousTimeout) {
      clearTimeout(this.continuousTimeout)
      this.continuousTimeout = null
    }

    // Clear transcript buffer
    if (this.transcriptBufferTimeout) {
      clearTimeout(this.transcriptBufferTimeout)
      this.transcriptBufferTimeout = null
    }
    this.transcriptBuffer = ""

    // Exit continuous mode
    this.continuousMode = false
    this.waitingForWakeWord = false

    // Log which provider was active during session
    if (this.currentSTTProvider) {
      console.log(`📊 Session used STT provider: ${this.currentSTTProvider}`)
      this.currentSTTProvider = null
    }

    // Stop audio capture
    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach(track => track.stop())
      this.mediaStream = null
      console.log("✅ Microphone stopped")
    }

    // Close Eleven Labs connection gracefully (primary STT provider)
    if (this.elevenLabsSocket) {
      if (this.elevenLabsSocket.readyState === WebSocket.OPEN) {
        this.elevenLabsSocket.close(1000, "User ended session") // Normal closure
        console.log("✅ Eleven Labs WebSocket closed gracefully")
      }
      this.elevenLabsSocket = null
    }

    // Close Deepgram connection gracefully (fallback - if still open)
    if (this.deepgramSocket) {
      if (this.deepgramSocket.readyState === WebSocket.OPEN) {
        this.deepgramSocket.close(1000, "User ended session") // Normal closure
        console.log("✅ Deepgram WebSocket closed gracefully")
      }
      this.deepgramSocket = null
    }

    // Disconnect Action Cable
    if (this.voiceChannel) {
      this.voiceChannel.unsubscribe()
      this.voiceChannel = null
      console.log("✅ Action Cable disconnected")
    }


    // End voice session
    if (this.voiceSessionId) {
      await this.endVoiceSession()
      this.voiceSessionId = null
      console.log("✅ Voice session ended")
    }

    this.updateStatus("Ready to listen")
    this.updateButton("inactive")
    console.log("✅ Voice assistant stopped cleanly")

    // Re-initialize cache for next use (background operation)
    setTimeout(() => {
      if (!this.isPreInitialized) {
        console.log("🔄 Re-initializing cache for next voice command...")
        this.preInitialize()
      }
    }, 500) // Small delay to ensure cleanup is complete
  }

  /**
   * Create voice session via API
   */
  async createVoiceSession() {
    const response = await fetch("/api/voice/sessions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      }
    })

    if (!response.ok) throw new Error("Failed to create voice session")
    return await response.json()
  }

  /**
   * Get Deepgram credentials
   */
  async getDeepgramCredentials() {
    const response = await fetch(`/api/voice/sessions/${this.voiceSessionId}/deepgram_key`, {
      headers: {
        "X-CSRF-Token": this.csrfToken()
      }
    })

    if (!response.ok) throw new Error("Failed to get Deepgram credentials")
    return await response.json()
  }

  /**
   * Get Eleven Labs Scribe v3 credentials
   */
  async getElevenLabsCredentials() {
    const response = await fetch(`/api/voice/sessions/${this.voiceSessionId}/eleven_labs_credentials`, {
      headers: {
        "X-CSRF-Token": this.csrfToken()
      }
    })

    if (!response.ok) throw new Error("Failed to get Eleven Labs credentials")
    return await response.json()
  }

  /**
   * End voice session
   */
  async endVoiceSession() {
    await fetch(`/api/voice/sessions/${this.voiceSessionId}/end`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this.csrfToken()
      }
    })
  }

  /**
   * Connect to Action Cable VoiceChannel
   */
  connectVoiceChannel() {
    return new Promise((resolve, reject) => {
      this.voiceChannel = consumer.subscriptions.create(
        {
          channel: "VoiceChannel",
          session_id: this.voiceSessionId
        },
        {
          connected: () => {
            console.log("VoiceChannel connected")
            resolve()
          },

          disconnected: () => {
            console.log("VoiceChannel disconnected")
          },

          received: (data) => {
            this.handleVoiceChannelMessage(data)
          }
        }
      )

      // Timeout if connection takes too long
      setTimeout(() => reject(new Error("VoiceChannel connection timeout")), 5000)
    })
  }

  /**
   * Handle messages from VoiceChannel
   */
  handleVoiceChannelMessage(data) {
    // Debug: Uncomment to see Action Cable messages
    // console.log("VoiceChannel message:", data)

    switch (data.type) {
      case "response":
        // Performance tracking
        this.performanceMetrics.scoutResponseTime = performance.now()
        const totalLatency = this.performanceMetrics.scoutResponseTime - this.performanceMetrics.speechStartTime
        const scoutProcessingTime = this.performanceMetrics.scoutResponseTime - this.performanceMetrics.scoutSentTime

        console.log(`⏱️ Scout processing time: ${scoutProcessingTime.toFixed(0)}ms`)
        console.log(`⏱️ TOTAL END-TO-END LATENCY: ${totalLatency.toFixed(0)}ms`)
        console.log(`📊 Latency Breakdown:
  - Speech → Transcript: ${(this.performanceMetrics.transcriptReceivedTime - this.performanceMetrics.speechStartTime).toFixed(0)}ms (includes 3s silence wait)
  - Transcript → Send: ${(this.performanceMetrics.scoutSentTime - this.performanceMetrics.transcriptReceivedTime).toFixed(0)}ms
  - Scout Processing: ${scoutProcessingTime.toFixed(0)}ms
  - TOTAL: ${totalLatency.toFixed(0)}ms`)

        // Add response to Scout chat UI
        this.addMessageToScoutChat("assistant", data.content)

        // Read response aloud using TTS when voice mode is active
        if (this.isActive) {
          this.synthesizeSpeech(data.content)
        }
        break

      case "partial_response":
        // Streaming response - don't synthesize yet
        // Could show interim text in UI
        break

      case "status":
        this.updateStatus(data.status)
        break

      case "error":
        this.updateStatus(`Error: ${data.message}`)
        break

      case "canvas":
        // Canvas update from Scout
        // Trigger canvas load in Scout UI
        if (window.loadCanvas) {
          window.loadCanvas(data.data)
        }
        break
    }
  }

  /**
   * Start WebRTC audio capture
   */
  async startAudioCapture() {
    const constraints = {
      audio: {
        sampleRate: 16000, // Telephony quality - perfect for voice, 66% less data than 48kHz
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true
      }
    }

    try {
      this.mediaStream = await navigator.mediaDevices.getUserMedia(constraints)
    } catch (error) {
      console.error("❌ Failed to get microphone access:", error)
      throw new Error(`Microphone access denied: ${error.message}`)
    }
    
    try {
      // Try to create AudioContext with preferred sample rate
      this.audioContext = new AudioContext({ sampleRate: 16000 })
      console.log("✅ Audio capture started at 16kHz sample rate (telephony quality)")
    } catch (error) {
      console.warn("⚠️ Could not create 16kHz AudioContext, falling back to default:", error)
      // Fallback to default sample rate
      this.audioContext = new AudioContext()
      console.log(`✅ Audio capture started at ${this.audioContext.sampleRate}Hz sample rate`)
    }
  }

  /**
   * Connect to Deepgram WebSocket (browser-compatible method)
   */
  connectDeepgram(creds) {
    return new Promise((resolve, reject) => {
      console.log("🔗 Deepgram config:", creds.config)

      // Build WebSocket URL with query parameters (NO token in URL for security)
      const params = new URLSearchParams(creds.config)
      const wsUrl = `${creds.websocket_url}?${params.toString()}`

      console.log("🔗 Connecting to Deepgram WebSocket...")
      console.log("🔗 WebSocket URL:", wsUrl)

      // CORRECT browser authentication: Use Sec-WebSocket-Protocol header
      // This is the documented way for browser-based Deepgram connections
      // Format: ['token', 'YOUR_API_KEY']
      this.deepgramSocket = new WebSocket(wsUrl, ['token', creds.api_key])

      this.deepgramSocket.onopen = () => {
        console.log("✅ Deepgram WebSocket connected")
        this.isListening = true
        
        // Clear transcription display when starting to listen
        document.dispatchEvent(new CustomEvent('voice:interim', {
          detail: { text: "" }
        }))

        // Start performance tracking
        this.performanceMetrics.speechStartTime = performance.now()
        console.log("⏱️ Performance tracking started")

        this.streamAudioToDeepgram()
        resolve()
      }

      this.deepgramSocket.onmessage = (event) => {
        const data = JSON.parse(event.data)
        // High-frequency event - comment out to reduce console noise
        // console.log("📥 Deepgram message received:", data)
        this.handleDeepgramMessage(data)
      }

      this.deepgramSocket.onerror = (error) => {
        console.error("❌ Deepgram WebSocket error:", error)
        console.error("   WebSocket URL was:", wsUrl)
        console.error("   API Key (first 10 chars):", creds.api_key?.substring(0, 10))
        this.updateStatus("Deepgram connection failed - check console")
        reject(error)
      }

      this.deepgramSocket.onclose = (event) => {
        // Only log if Deepgram was actively being used (not just pre-initialized)
        const wasActiveProvider = this.currentSTTProvider && this.currentSTTProvider.includes("Deepgram")

        if (wasActiveProvider) {
          console.log("🔌 Deepgram WebSocket closed", {
            code: event.code,
            reason: event.reason,
            wasClean: event.wasClean
          })
        }

        this.isListening = false

        // Common close codes explained
        const closeReasons = {
          1000: "Normal closure",
          1001: "Going away",
          1002: "Protocol error",
          1003: "Unsupported data",
          1006: "Abnormal closure (no close frame) - Usually authentication or network issue",
          1008: "Policy violation",
          1009: "Message too big",
          1011: "Server error",
          4001: "Deepgram authentication failed",
          4008: "Deepgram request timeout",
          4010: "Deepgram invalid request"
        }

        const reason = closeReasons[event.code] || 'Unknown reason'

        // Only show messages if Deepgram was the active provider
        if (wasActiveProvider) {
          if (event.code !== 1000 && this.isActive) {
            console.error(`❌ Deepgram closed abnormally`)
            console.error(`   Code: ${event.code}`)
            console.error(`   Reason: ${event.reason || reason}`)
            console.error(`   This usually means authentication failed or bad configuration`)
            this.updateStatus(`Connection error: ${reason}`)
          } else if (event.code === 1000) {
            console.log("✅ Deepgram WebSocket closed normally")
          }
        }
      }
    })
  }

  /**
   * Connect to Eleven Labs Scribe v3 WebSocket (real-time speech-to-text)
   * Features:
   * - Ultra-low latency (~150ms)
   * - 90+ language support
   * - High accuracy across accents
   * - Supports PCM and μ-law encoding
   */
  connectElevenLabs(creds) {
    return new Promise((resolve, reject) => {
      console.log("🔗 Eleven Labs config:", creds.config)

      // Build WebSocket URL with API key in query parameter
      const wsUrl = `${creds.websocket_url}?api_key=${creds.api_key}`

      console.log("🔗 Connecting to Eleven Labs Scribe v3 WebSocket...")
      this.elevenLabsSocket = new WebSocket(wsUrl)

      this.elevenLabsSocket.onopen = () => {
        console.log("✅ Eleven Labs WebSocket connected")
        this.isListening = true

        // Clear transcription display when starting to listen
        document.dispatchEvent(new CustomEvent('voice:interim', {
          detail: { text: "" }
        }))

        // Start performance tracking
        this.performanceMetrics.speechStartTime = performance.now()
        console.log("⏱️ Performance tracking started")

        // Send initial config
        this.elevenLabsSocket.send(JSON.stringify({
          type: "request_init",
          config: {
            ...creds.config,
            enable_speaker_diarization: false
          }
        }))

        this.streamAudioToElevenLabs()
        resolve()
      }

      this.elevenLabsSocket.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data)
          this.handleElevenLabsMessage(data)
        } catch (e) {
          console.error("Failed to parse Eleven Labs message:", e)
        }
      }

      this.elevenLabsSocket.onerror = (error) => {
        console.error("❌ Eleven Labs WebSocket error:", error)
        this.updateStatus("Eleven Labs connection failed - check console")
        reject(error)
      }

      this.elevenLabsSocket.onclose = (event) => {
        console.log("🔌 Eleven Labs WebSocket closed", {
          code: event.code,
          reason: event.reason,
          wasClean: event.wasClean
        })
        this.isListening = false

        if (event.code !== 1000 && this.isActive) {
          console.error(`❌ Eleven Labs closed abnormally`)
          console.error(`   Code: ${event.code}`)
          console.error(`   Reason: ${event.reason || "Unknown"}`)
          this.updateStatus(`Connection error: ${event.reason || "Unknown"}`)
        } else if (event.code === 1000) {
          console.log("✅ Eleven Labs WebSocket closed normally")
        }
      }

      // Timeout if connection takes too long
      setTimeout(() => reject(new Error("Eleven Labs connection timeout")), 10000)
    })
  }

  /**
   * Connect to STT provider with fallback
   * Attempts Eleven Labs Scribe v3 first, falls back to Deepgram if unavailable
   * Logs which provider is being used for monitoring/debugging
   */
  async connectWithFallback(elevenLabsCreds) {
    console.log("🚀 Attempting STT provider connection (priority: Eleven Labs → Deepgram)...")

    try {
      console.log("1️⃣ Attempting Eleven Labs Scribe v3 (primary provider)...")
      const startTime = performance.now()

      await this.connectElevenLabs(elevenLabsCreds)

      const connectionTime = performance.now() - startTime
      this.currentSTTProvider = "Eleven Labs Scribe v3"
      console.log(`✅ Eleven Labs connected successfully in ${connectionTime.toFixed(0)}ms`)
      console.log(`📊 STT Provider: ${this.currentSTTProvider}`)

    } catch (elevenLabsError) {
      console.warn("⚠️ Eleven Labs Scribe v3 unavailable, attempting fallback...")
      console.error("   Error:", elevenLabsError.message)
      console.log("   Reason: Eleven Labs API unreachable or credentials invalid")

      try {
        console.log("2️⃣ Attempting Deepgram (fallback provider)...")
        const startTime = performance.now()

        // Fetch Deepgram credentials from server
        const deepgramCreds = await this.getDeepgramCredentials()
        await this.connectDeepgram(deepgramCreds)

        const connectionTime = performance.now() - startTime
        this.currentSTTProvider = "Deepgram (fallback)"
        console.log(`✅ Deepgram connected successfully in ${connectionTime.toFixed(0)}ms`)
        console.log(`📊 STT Provider: ${this.currentSTTProvider}`)
        console.log(`ℹ️ Note: Using fallback provider. Eleven Labs will be retried on next session.`)

        // Notify user that fallback is active
        this.updateStatus("🎤 Listening (using Deepgram)... Say 'Hey Amos' + your command")

      } catch (deepgramError) {
        console.error("❌ Both STT providers failed!")
        console.error("   Eleven Labs error:", elevenLabsError.message)
        console.error("   Deepgram error:", deepgramError.message)

        const errorMsg = "Voice input unavailable - both STT providers failed. Please try again."
        this.updateStatus(errorMsg)
        throw new Error(errorMsg)
      }
    }
  }

  /**
   * Stream audio to Eleven Labs
   */
  async streamAudioToElevenLabs() {
    const source = this.audioContext.createMediaStreamSource(this.mediaStream)
    const processor = this.audioContext.createScriptProcessor(4096, 1, 1)

    let audioChunkCount = 0
    const needsResampling = this.audioContext.sampleRate !== 16000

    if (needsResampling) {
      console.log(`🔄 Resampling from ${this.audioContext.sampleRate}Hz to 16000Hz for Eleven Labs`)
    }

    processor.onaudioprocess = (e) => {
      if (!this.isListening || !this.elevenLabsSocket || this.elevenLabsSocket.readyState !== WebSocket.OPEN) {
        return
      }

      const inputData = e.inputBuffer.getChannelData(0)

      let resampledData = inputData

      // Simple resampling if needed
      if (needsResampling) {
        const resampleRatio = 16000 / this.audioContext.sampleRate
        const newLength = Math.floor(inputData.length * resampleRatio)
        resampledData = new Float32Array(newLength)

        for (let i = 0; i < newLength; i++) {
          const srcIndex = i / resampleRatio
          const srcIndexFloor = Math.floor(srcIndex)
          const srcIndexCeil = Math.ceil(srcIndex)
          const fraction = srcIndex - srcIndexFloor

          if (srcIndexCeil < inputData.length) {
            resampledData[i] = inputData[srcIndexFloor] * (1 - fraction) + inputData[srcIndexCeil] * fraction
          } else {
            resampledData[i] = inputData[srcIndexFloor]
          }
        }
      }

      // Convert to 16-bit PCM
      const pcmData = new Int16Array(resampledData.length)
      for (let i = 0; i < resampledData.length; i++) {
        pcmData[i] = Math.max(-32768, Math.min(32767, resampledData[i] * 32768))
      }

      if (pcmData.byteLength === 0) {
        console.warn("⚠️ Empty audio buffer, skipping")
        return
      }

      // Send to Eleven Labs as binary data
      try {
        this.elevenLabsSocket.send(pcmData.buffer)

        audioChunkCount++
        if (audioChunkCount <= 3) {
          console.log(`📤 Sent audio chunk #${audioChunkCount}, size: ${pcmData.buffer.byteLength} bytes`)
        }
      } catch (error) {
        console.error("❌ Failed to send audio to Eleven Labs:", error)
      }

      // Voice Activity Detection
      const volume = this.calculateVolume(inputData)
      this.handleVAD(volume)
    }

    try {
      source.connect(processor)
      processor.connect(this.audioContext.destination)
      console.log("🎙️ Audio processor connected and streaming to Eleven Labs")
    } catch (error) {
      console.error("❌ Failed to connect audio processor:", error)
      this.updateStatus("Audio error - please refresh and try again")
      this.stopListening()
      throw error
    }
  }

  /**
   * Handle Eleven Labs messages
   * Eleven Labs Scribe v3 Realtime message format
   */
  handleElevenLabsMessage(data) {
    console.log("📥 Eleven Labs message:", data)

    switch (data.type) {
      case "transcript":
        // Partial or final transcript
        const transcript = data.transcript
        const isFinal = data.is_final

        if (transcript) {
          if (isFinal) {
            // Track transcript latency
            this.performanceMetrics.transcriptReceivedTime = performance.now()
            const transcriptLatency = this.performanceMetrics.transcriptReceivedTime - this.performanceMetrics.speechStartTime
            console.log("✅ Final transcript from Eleven Labs:", transcript)
            console.log(`⏱️ Transcript latency: ${transcriptLatency.toFixed(0)}ms`)

            // Buffer transcript
            this.addToTranscriptBuffer(transcript)
          } else {
            // Interim transcript
            console.log("💬 Interim transcript:", transcript)
            this.showInterimTranscript(transcript)
          }
        }
        break

      case "auth_error":
        console.error("❌ Eleven Labs authentication error:", data.message || data.error_message)
        this.updateStatus("Connection issue - please try again")
        this.handleElevenLabsError("auth_error", data.message || data.error_message)
        break

      case "quota_exceeded":
        console.error("❌ Eleven Labs quota exceeded:", data.message || data.error_message)
        this.updateStatus("Switching to backup service...")
        this.handleElevenLabsError("quota_exceeded", data.message || data.error_message)
        break

      case "transcriber_error":
        console.error("❌ Eleven Labs transcriber error:", data.message || data.error_message)
        this.updateStatus("Connection issue - retrying...")
        this.handleElevenLabsError("transcriber_error", data.message || data.error_message)
        break

      case "input_error":
        console.error("❌ Eleven Labs input error:", data.message || data.error_message)
        this.updateStatus("Audio issue - retrying...")
        this.handleElevenLabsError("input_error", data.message || data.error_message)
        break

      case "error":
        console.error("❌ Eleven Labs error:", data.message || data.error_message)
        this.updateStatus("Connection issue - retrying...")
        this.handleElevenLabsError("error", data.message || data.error_message)
        break

      case "ping":
        // Respond to keepalive ping
        if (this.elevenLabsSocket?.readyState === WebSocket.OPEN) {
          this.elevenLabsSocket.send(JSON.stringify({ type: "pong" }))
        }
        break

      default:
        console.log("📨 Eleven Labs message type:", data.type)
    }
  }

  /**
   * Handle Eleven Labs errors with appropriate recovery strategy
   * Implements fallback to Deepgram for recoverable errors
   * Logs errors to backend silently for monitoring
   */
  async handleElevenLabsError(errorType, errorMessage) {
    console.log(`🔧 Handling Eleven Labs error: ${errorType}`)

    // Log error to backend silently (don't expose third-party details to user)
    this.logErrorToBackend(errorType, errorMessage, "eleven_labs")

    // Close Eleven Labs socket if still open
    if (this.elevenLabsSocket) {
      try {
        this.elevenLabsSocket.close()
      } catch (e) {
        console.warn("⚠️ Error closing Eleven Labs socket:", e)
      }
      this.elevenLabsSocket = null
    }

    // Determine if we should attempt fallback to Deepgram
    const shouldFallback = this.shouldFallbackToDeepgram(errorType)

    if (shouldFallback && this.isActive) {
      console.log("🔄 Attempting fallback to Deepgram after Eleven Labs error")
      this.updateStatus("Switching to backup transcription service...")

      try {
        // Fetch Deepgram credentials on-demand
        const response = await fetch('/api/voice/sessions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
          }
        })

        if (response.ok) {
          const data = await response.json()
          const deepgramCreds = {
            websocket_url: data.deepgram_websocket_url,
            api_key: data.deepgram_api_key
          }

          await this.connectDeepgram(deepgramCreds)
          this.currentSTTProvider = "Deepgram (fallback)"
          console.log(`✅ Fallback successful - now using ${this.currentSTTProvider}`)
          this.updateStatus("Connected to backup service")
        } else {
          throw new Error(`Failed to fetch Deepgram credentials: ${response.status}`)
        }
      } catch (fallbackError) {
        console.error("❌ Fallback to Deepgram failed:", fallbackError)
        this.updateStatus("Voice assistant unavailable - please try again later")
        this.fullStop()
      }
    } else {
      // Non-recoverable error or user stopped - just stop
      console.log("⛔ Error not recoverable or user stopped - stopping voice assistant")
      this.fullStop()
    }
  }

  /**
   * Determine if we should attempt fallback to Deepgram based on error type
   */
  shouldFallbackToDeepgram(errorType) {
    switch (errorType) {
      case "quota_exceeded":
      case "transcriber_error":
        // These errors can be recovered by switching providers
        return true

      case "auth_error":
        // Auth errors won't be fixed by switching providers (same backend)
        return false

      case "input_error":
        // Input format errors might persist with Deepgram too
        // But worth trying in case it's Eleven Labs specific
        return true

      case "error":
        // Generic errors - try fallback
        return true

      default:
        return false
    }
  }

  /**
   * Log voice errors to backend for monitoring
   * Sends error details to server without disrupting user experience
   */
  async logErrorToBackend(errorType, errorMessage, provider) {
    if (!this.voiceSessionId) {
      console.warn("⚠️ Cannot log error - no voice session ID")
      return
    }

    try {
      await fetch(`/api/voice/sessions/${this.voiceSessionId}/log_error`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({
          error_type: errorType,
          error_message: errorMessage,
          provider: provider
        })
      })
      console.log(`📊 Error logged to backend: ${errorType}`)
    } catch (error) {
      // Fail silently - don't disrupt user experience
      console.warn("⚠️ Failed to log error to backend:", error)
    }
  }

  /**
   * Stream audio to Deepgram
   */
  async streamAudioToDeepgram() {
    const source = this.audioContext.createMediaStreamSource(this.mediaStream)
    // Reverted to 4096 buffer size (last working config)
    const processor = this.audioContext.createScriptProcessor(4096, 1, 1)

    let audioChunkCount = 0
    const needsResampling = this.audioContext.sampleRate !== 16000
    
    if (needsResampling) {
      console.log(`🔄 Resampling from ${this.audioContext.sampleRate}Hz to 16000Hz for Deepgram`)
    }

    processor.onaudioprocess = (e) => {
      if (!this.isListening || !this.deepgramSocket || this.deepgramSocket.readyState !== WebSocket.OPEN) {
        return
      }

      const inputData = e.inputBuffer.getChannelData(0)

      let resampledData = inputData
      
      // Simple resampling if needed (not perfect but works for voice)
      if (needsResampling) {
        const resampleRatio = 16000 / this.audioContext.sampleRate
        const newLength = Math.floor(inputData.length * resampleRatio)
        resampledData = new Float32Array(newLength)
        
        for (let i = 0; i < newLength; i++) {
          const srcIndex = i / resampleRatio
          const srcIndexFloor = Math.floor(srcIndex)
          const srcIndexCeil = Math.ceil(srcIndex)
          const fraction = srcIndex - srcIndexFloor
          
          if (srcIndexCeil < inputData.length) {
            resampledData[i] = inputData[srcIndexFloor] * (1 - fraction) + inputData[srcIndexCeil] * fraction
          } else {
            resampledData[i] = inputData[srcIndexFloor]
          }
        }
      }
      
      // Convert to 16-bit PCM
      const pcmData = new Int16Array(resampledData.length)
      for (let i = 0; i < resampledData.length; i++) {
        pcmData[i] = Math.max(-32768, Math.min(32767, resampledData[i] * 32768))
      }

      // Check if we have valid audio data
      if (pcmData.byteLength === 0) {
        console.warn("⚠️ Empty audio buffer, skipping")
        return
      }
      
      // Send to Deepgram
      try {
        this.deepgramSocket.send(pcmData.buffer)
        
        // Log first few chunks to verify audio is flowing
        audioChunkCount++
        if (audioChunkCount <= 3) {
          console.log(`📤 Sent audio chunk #${audioChunkCount}, size: ${pcmData.buffer.byteLength} bytes`)
          // Also log if audio seems silent
          const maxValue = Math.max(...Array.from(pcmData).slice(0, 100).map(Math.abs))
          if (maxValue < 100) {
            console.warn(`⚠️ Audio chunk ${audioChunkCount} appears to be silent (max value: ${maxValue})`)
          }
        }
      } catch (error) {
        console.error("❌ Failed to send audio to Deepgram:", error)
      }

      // Simple VAD - detect if user is speaking
      const volume = this.calculateVolume(inputData)
      this.handleVAD(volume)
    }

    try {
      source.connect(processor)
      processor.connect(this.audioContext.destination)
      console.log("🎙️ Audio processor connected and streaming to Deepgram")
    } catch (error) {
      console.error("❌ Failed to connect audio processor:", error)
      this.updateStatus("Audio error - please refresh and try again")
      this.stopListening()
      throw error
    }
  }

  /**
   * Calculate audio volume for VAD
   */
  calculateVolume(buffer) {
    let sum = 0
    for (let i = 0; i < buffer.length; i++) {
      sum += buffer[i] * buffer[i]
    }
    return Math.sqrt(sum / buffer.length)
  }

  /**
   * Handle Voice Activity Detection
   * (Simplified - no barge-in needed since no TTS playback)
   */
  handleVAD(volume) {
    // VAD tracking for potential future use
    // Could be used for visual feedback (waveform animation, etc.)
  }

  /**
   * Handle Deepgram messages
   */
  handleDeepgramMessage(data) {
    if (data.type === "Results") {
      const transcript = data.channel?.alternatives?.[0]?.transcript
      const isFinal = data.is_final

      if (transcript) {
        if (isFinal) {
          // Track transcript latency
          this.performanceMetrics.transcriptReceivedTime = performance.now()
          const transcriptLatency = this.performanceMetrics.transcriptReceivedTime - this.performanceMetrics.speechStartTime
          console.log("✅ Final transcript chunk:", transcript)
          console.log(`⏱️ Transcript latency: ${transcriptLatency.toFixed(0)}ms`)

          // Buffer transcript - Deepgram often splits speech into multiple finals
          // Wait 800ms to see if more speech is coming
          this.addToTranscriptBuffer(transcript)
        } else {
          // High-frequency event - comment out to reduce console noise
          // console.log("💬 Interim transcript:", transcript)
          this.showInterimTranscript(transcript)
        }
      }
      // Note: Some Deepgram messages don't have transcripts (metadata, etc) - this is normal
    }
  }

  /**
   * Add transcript to buffer and wait for more speech
   * Deepgram often splits one utterance into multiple finals
   */
  addToTranscriptBuffer(transcript) {
    // Clear existing timeout
    if (this.transcriptBufferTimeout) {
      clearTimeout(this.transcriptBufferTimeout)
    }

    // Add to buffer (with space if buffer not empty)
    if (this.transcriptBuffer.length > 0) {
      this.transcriptBuffer += " " + transcript
      console.log(`📝 Buffering transcript: "${this.transcriptBuffer}"`)
    } else {
      this.transcriptBuffer = transcript
      console.log(`📝 Started transcript buffer: "${transcript}"`)
    }

    // Wait 500ms - if no more speech comes, process the buffered transcript
    // Reduced from 800ms for faster response (still catches split transcripts)
    this.transcriptBufferTimeout = setTimeout(() => {
      this.processBufferedTranscript()
    }, 500)
  }

  /**
   * Process the complete buffered transcript
   */
  processBufferedTranscript() {
    const completeTranscript = this.transcriptBuffer
    this.transcriptBuffer = ""  // Clear buffer
    this.transcriptBufferTimeout = null

    console.log(`🎯 Processing complete transcript: "${completeTranscript}"`)
    
    // Emit event for voice mode UI
    document.dispatchEvent(new CustomEvent('voice:final', {
      detail: { text: completeTranscript }
    }))

    // Check if TTS is currently playing and if the transcript matches what it's saying
    if (window.ttsManager && window.ttsManager.isPlaying) {
      const ttsText = window.ttsManager.currentlyPlayingText
      console.log("🎵 TTS Check - Playing:", window.ttsManager.isPlaying, "Text:", ttsText?.substring(0, 50) + "...")
      console.log("🎤 Transcript received:", completeTranscript)
      
      if (ttsText) {
        // Normalize both texts for comparison
        const normalizedTTS = ttsText.toLowerCase().replace(/[.,!?;:*\n]/g, '').trim()
        const normalizedTranscript = completeTranscript.toLowerCase().replace(/[.,!?;:]/g, '').trim()
        
        console.log("🔍 Comparing - TTS:", normalizedTTS.substring(0, 50) + "...")
        console.log("🔍 Comparing - Transcript:", normalizedTranscript)
        
        // Check if the transcript is part of what TTS is saying
        if (normalizedTTS.includes(normalizedTranscript) || normalizedTranscript.includes(normalizedTTS.substring(0, 50))) {
          console.log("🔇 Ignoring transcript - matches current TTS output")
          return
        }
      }
    }

    // Also check recent AI responses even if TTS isn't playing
    // This helps when TTS fails but we still want to prevent feedback
    const recentMessages = document.querySelectorAll('.ai-message')
    if (recentMessages.length > 0) {
      const lastAIMessage = recentMessages[recentMessages.length - 1]?.textContent || ''
      const normalizedAI = lastAIMessage.toLowerCase().replace(/[.,!?;:*\n]/g, '').trim()
      const normalizedTranscript = completeTranscript.toLowerCase().replace(/[.,!?;:]/g, '').trim()
      
      // Check if this matches recent AI output (within last 10 seconds)
      const messageElement = recentMessages[recentMessages.length - 1]
      const messageTime = messageElement?.dataset?.timestamp || Date.now()
      const timeDiff = Date.now() - parseInt(messageTime)
      
      if (timeDiff < 10000 && normalizedAI.includes(normalizedTranscript)) {
        console.log("🔇 Ignoring transcript - matches recent AI message")
        return
      }
    }

    // Process wake word if present
    const processedTranscript = this.processWakeWord(completeTranscript)

    // Send to Scout AI for processing (only if there's a command after wake word)
    if (processedTranscript) {
      // Clear 20-second timeout since we got valid input
      if (this.listeningTimeout) {
        clearTimeout(this.listeningTimeout)
        this.listeningTimeout = null
      }

      this.sendToScoutAI(processedTranscript)
    }

    // Gracefully stop after a short delay to allow any pending operations
    // (In continuous mode, this will just reset to waiting for wake word)
    console.log("🛑 Stopping voice assistant gracefully...")
    setTimeout(() => {
      this.stopVoice()
    }, 500)
  }

  /**
   * Process wake word from transcript
   * Detects "Hey Amos" and strips it from the command
   * Returns the command text, or null if no command after wake word
   */
  processWakeWord(transcript) {
    const wakeWords = ['hey amos', 'hi amos', 'amos']

    // Normalize transcript: lowercase and remove punctuation for matching
    const normalizedTranscript = transcript.toLowerCase().replace(/[.,!?;:]/g, '').trim()

    // Check if transcript starts with any wake word
    for (const wakeWord of wakeWords) {
      if (normalizedTranscript.startsWith(wakeWord)) {
        console.log(`🎤 Wake word detected: "${wakeWord}" in "${transcript}"`)

        // Extract command after wake word (from normalized version)
        const command = normalizedTranscript.substring(wakeWord.length).trim()

        if (command.length > 0) {
          console.log(`✅ Command extracted: "${command}"`)

          // Reset waiting state if in continuous mode
          if (this.waitingForWakeWord) {
            this.waitingForWakeWord = false
            this.updateStatus("Processing command...")
          }

          return command
        } else {
          console.log(`⚠️ Wake word detected but no command given`)
          return null  // Just "Hey Amos" with no command
        }
      }
    }

    // In continuous mode, accept any speech (wake word is optional)
    // Reset waiting state since we got valid input
    if (this.waitingForWakeWord) {
      this.waitingForWakeWord = false
      this.updateStatus("Processing command...")
      console.log(`✅ Accepting command without wake word: "${transcript}"`)
    }

    // No wake word found - send full transcript as-is
    return transcript
  }

  /**
   * Send transcript directly to Scout AI (bypasses webhook)
   */
  async sendToScoutAI(transcript) {
    try {
      this.performanceMetrics.scoutSentTime = performance.now()
      const sendDelay = this.performanceMetrics.scoutSentTime - this.performanceMetrics.transcriptReceivedTime
      console.log("🤖 Sending to Scout AI:", transcript)
      console.log(`⏱️ Send delay: ${sendDelay.toFixed(0)}ms`)

      // Check if chat input is currently disabled (e.g., during planning mode or streaming)
      const messageInput = document.getElementById('message-input')
      if (messageInput && messageInput.disabled) {
        console.warn("⚠️ Chat input is disabled (planning mode or streaming active)")
        
        // Check if there's an active stream - abort it for interruption
        if (window.currentStreamAbortController) {
          console.log("🛑 Aborting current stream for voice interruption")
          window.currentStreamAbortController.abort()
          window.currentStreamAbortController = null
          
          // Give a brief moment for cleanup
          await new Promise(resolve => setTimeout(resolve, 100))
          
          // Force re-enable input
          messageInput.disabled = false
          const sendButton = document.getElementById('send-button')
          if (sendButton) sendButton.disabled = false
        } else {
          // No active stream, but input is disabled (e.g., planning mode)
          // Wait briefly for it to be re-enabled
          await this.waitForChatReady(messageInput, 1000) // Reduced to 1 second
        }
      }

      // Use the global scoutSendMessage function to trigger Scout
      // Pass model override to use faster Haiku for voice responses
      if (window.scoutSendMessage && typeof window.scoutSendMessage === 'function') {
        window.scoutSendMessage(transcript, { model: 'claude-haiku-4-5' })
        console.log("✅ Sent to Scout via scoutSendMessage with Haiku model")
      } else {
        console.warn("⚠️ scoutSendMessage not available, trying direct method")

        // Fallback: programmatically submit to chat form
        const messageForm = document.getElementById('message-form')

        if (messageInput && messageForm) {
          // Temporarily enable input if disabled (to allow form submission)
          const wasDisabled = messageInput.disabled
          messageInput.disabled = false
          const sendButton = document.getElementById('send-button')
          if (sendButton) sendButton.disabled = false
          
          messageInput.value = transcript
          messageForm.dispatchEvent(new Event('submit'))
          
          console.log("✅ Submitted via chat form")
        } else {
          console.error("❌ Could not find chat form elements")
        }
      }
    } catch (error) {
      console.error("❌ Failed to send to Scout AI:", error)
      this.updateStatus("Error processing with AI")
    }
  }

  /**
   * Wait for chat input to become ready (not disabled)
   */
  async waitForChatReady(inputElement, maxWaitMs = 1000) { // Reduced default to 1 second
    const startTime = Date.now()
    const checkInterval = 50 // Check every 50ms

    while (inputElement.disabled && (Date.now() - startTime) < maxWaitMs) {
      console.log("⏳ Waiting for chat to be ready...")
      await new Promise(resolve => setTimeout(resolve, checkInterval))
    }

    if (inputElement.disabled) {
      console.warn("⚠️ Chat still disabled after waiting, will force enable for voice")
    } else {
      console.log("✅ Chat is now ready")
    }
  }


  /**
   * Add message to Scout chat UI
   */
  addMessageToScoutChat(role, content) {
    // Integrate with existing Scout chat UI using the global addMessage function
    console.log("Adding message to Scout chat:", role, content)

    // Try to use the global addMessage function defined in scout/index.html.erb
    if (window.addMessage && typeof window.addMessage === 'function') {
      window.addMessage(content, role)
      console.log("Message added via global addMessage function")
    } else {
      console.warn("Global addMessage function not found, attempting manual message creation")

      // Fallback: Try to find and call the Scout controller's method
      const scoutController = window.scoutController
      if (scoutController && scoutController.addMessage) {
        scoutController.addMessage(content, role)
      } else {
        // Last resort: Direct DOM manipulation matching Scout's message format
        const chatContainer = document.querySelector("#chat-messages")
        if (chatContainer) {
          const messageWrapper = document.createElement("div")
          messageWrapper.className = `message ${role === 'user' ? 'user-message' : 'ai-message'}`

          const messageContent = document.createElement("div")
          messageContent.className = "message-content"

          const avatar = document.createElement("div")
          avatar.className = "message-avatar"
          avatar.innerHTML = role === 'user' ? '<i data-lucide="user" style="width: 20px; height: 20px;"></i>' : '<i data-lucide="bot" style="width: 20px; height: 20px;"></i>'

          // Initialize Lucide icons
          if (typeof lucide !== 'undefined') {
            lucide.createIcons()
          }

          const bubble = document.createElement("div")
          bubble.className = "message-bubble"
          bubble.textContent = content

          messageContent.appendChild(avatar)
          messageContent.appendChild(bubble)
          messageWrapper.appendChild(messageContent)

          chatContainer.appendChild(messageWrapper)
          chatContainer.scrollTop = chatContainer.scrollHeight
        }
      }
    }
  }

  /**
   * Show interim transcript
   */
  showInterimTranscript(text) {
    // Emit event for voice mode UI
    document.dispatchEvent(new CustomEvent('voice:interim', {
      detail: { text: text }
    }))
    
    // Show in a temporary UI element
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = `Listening: "${text}"`
    }
  }

  /**
   * Update status display
   */
  updateStatus(status) {
    console.log("Status:", status)
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = status
      if (status) {
        this.statusTarget.classList.remove('d-none')
        this.statusTarget.classList.add('d-block')
      } else {
        this.statusTarget.classList.add('d-none')
        this.statusTarget.classList.remove('d-block')
      }
    }
  }

  /**
   * Update button appearance
   */
  updateButton(state) {
    if (this.hasButtonTarget) {
      if (state === "active" || state === "listening") {
        this.buttonTarget.classList.add("active")

        if (this.continuousMode) {
          this.buttonTarget.title = "Continuous mode active - click to stop"
          // Add pulsing effect for continuous mode
          this.buttonTarget.classList.add('voice-pulse-animation')
        } else {
          this.buttonTarget.title = "Stop voice input"
          this.buttonTarget.classList.remove('voice-pulse-animation')
        }
      } else {
        this.buttonTarget.classList.remove("active")
        this.buttonTarget.title = "Voice input"
        this.buttonTarget.classList.remove('voice-pulse-animation')
      }
    }
  }

  /**
   * Get CSRF token
   */
  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
  }

  /**
   * Toggle continuous listening mode
   */
  toggleContinuousMode() {
    this.continuousMode = !this.continuousMode

    if (this.continuousMode) {
      console.log("🔄 Continuous mode ENABLED - voice assistant will stay active after each command")
      this.updateStatus("Continuous mode enabled - say 'Hey Amos' multiple times")
    } else {
      console.log("🔄 Continuous mode DISABLED - voice assistant will stop after each command")
      this.updateStatus("Continuous mode disabled")

      // If we're currently waiting for wake word, stop fully
      if (this.waitingForWakeWord) {
        this.fullStop()
      }
    }
  }

  /**
   * Reset the continuous mode timeout (5 minutes)
   */
  resetContinuousTimeout() {
    // Clear existing timeout
    if (this.continuousTimeout) {
      clearTimeout(this.continuousTimeout)
    }

    // Set new 5-minute timeout
    this.continuousTimeout = setTimeout(() => {
      console.log("⏱️ Continuous mode timeout reached (5 min) - stopping voice assistant")
      this.updateStatus("Session timed out")
      this.fullStop()
    }, 5 * 60 * 1000)  // 5 minutes
  }

  /**
   * Unlock audio for iOS - call this during user gesture (mic button click)
   */
  unlockIOSAudio() {
    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || 
                  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
    
    if (isIOS && !this.iosAudioUnlocked) {
      // Create a reusable audio element for iOS
      if (!this.iosAudioElement) {
        this.iosAudioElement = new Audio()
        this.iosAudioElement.volume = 1.0
      }
      
      // Play silent audio to unlock
      try {
        const silentDataUrl = 'data:audio/mp3;base64,SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU4Ljc2LjEwMAAAAAAAAAAAAAAA/+M4wAAAAAAAAAAAAEluZm8AAAAPAAAAAgAAAbAAqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq//////////////////////////////////////////////////////////////////8AAAAATGF2YzU4LjEzAAAAAAAAAAAAAAAAJAAAAAAAAAAAAbD//////////////////////////////////////////////////////////////////'
        this.iosAudioElement.src = silentDataUrl
        this.iosAudioElement.play().then(() => {
          this.iosAudioUnlocked = true
          console.log("🔓 iOS audio unlocked for voice assistant")
        }).catch(e => {
          console.log("🔒 iOS audio unlock pending")
        })
      } catch (e) {
        console.warn("iOS unlock error:", e)
      }
    }
  }
  
  /**
   * Synthesize speech from text using backend API
   * Respects user preferences for provider and voice (Eleven Labs or Polly)
   */
  async synthesizeSpeech(text) {
    try {
      console.log("🔊 Requesting TTS from backend for:", text.substring(0, 50) + "...")

      // Call unified backend endpoint which handles provider selection based on user settings
      const response = await fetch('/api/tts/synthesize', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken()
        },
        body: JSON.stringify({
          text: text,
          // We don't specify voice_id or provider here, so the backend uses user preferences
          speech_marks: false
        })
      })

      if (!response.ok) {
        console.error("❌ TTS failed:", response.status, response.statusText)
        return
      }

      // Get audio data as blob
      const audioBlob = await response.blob()
      const audioUrl = URL.createObjectURL(audioBlob)

      // On iOS, use the pre-unlocked audio element
      const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || 
                    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
      
      let audio
      if (isIOS && this.iosAudioElement) {
        audio = this.iosAudioElement
        audio.src = audioUrl
      } else {
        audio = new Audio(audioUrl)
      }
      
      // Try to play, with iOS-specific handling
      try {
        await audio.play()
        console.log("✅ Playing TTS audio")
      } catch (playError) {
        console.error("❌ Audio play failed:", playError)
        // On iOS, might need user to tap again
        if (isIOS) {
          console.log("🔒 iOS: Audio blocked - will play on next user interaction")
          // Store for later playback
          this.pendingAudioUrl = audioUrl
        }
      }

      // Clean up blob URL after playing
      audio.onended = () => {
        URL.revokeObjectURL(audioUrl)
        console.log("🔇 Speech playback completed")
      }

    } catch (error) {
      console.error("❌ TTS error:", error)
    }
  }

  /**
   * Get Eleven Labs API key
   */
  async getElevenLabsApiKey() {
    // Use cached credentials if available
    if (this.cachedElevenLabsCreds && this.cachedElevenLabsCreds.api_key) {
      return this.cachedElevenLabsCreds.api_key
    }

    // Otherwise fetch from backend
    try {
      const sessionId = this.voiceSessionId || this.cachedSession?.session_id
      if (!sessionId) {
        throw new Error("No voice session available")
      }

      const response = await fetch(`/api/voice/sessions/${sessionId}/eleven_labs_credentials`, {
        headers: {
          "X-CSRF-Token": this.csrfToken()
        }
      })

      const creds = await response.json()
      return creds.api_key
    } catch (error) {
      console.error("❌ Failed to get Eleven Labs API key:", error)
      throw error
    }
  }

  /**
   * Fully stop voice assistant (used when exiting continuous mode)
   */
  async fullStop() {
    this.continuousMode = false
    this.waitingForWakeWord = false
    await this.stopVoice()
  }
}
