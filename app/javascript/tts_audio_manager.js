/**
 * TTS Audio Manager
 * Handles text-to-speech audio playback with interruption support
 */
export default class TTSAudioManager {
  constructor() {
    // Initialize with defaults, then load user preferences
    this.isEnabled = false  // Default to OFF
    this.voiceId = 'Matthew'
    this.playbackRate = 1.0
    this.volume = 1.0
    
    this.audioQueue = []
    this.isPlaying = false
    this.currentAudio = null
    this.currentSpeechMarks = null
    this.interruptCallback = null
    this.currentlyPlayingText = null  // Track what TTS is currently saying
    this.lastRequestTime = 0  // Rate limiting
    this.minRequestInterval = 100  // Minimum 100ms between requests
    
    // Preload audio context for low latency
    this.audioContext = null
    this.initAudioContext()
    
    // Load user preferences from server
    this.loadUserPreferences()
    
    // Bind methods
    this.speak = this.speak.bind(this)
    this.interrupt = this.interrupt.bind(this)
    this.toggle = this.toggle.bind(this)
  }
  
  /**
   * Load user preferences from server
   */
  async loadUserPreferences() {
    try {
      const response = await fetch('/api/tts/preferences', {
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        const prefs = data.preferences || {}
        
        // Default to disabled if not explicitly set
        this.isEnabled = prefs.enabled === true
        this.voiceId = prefs.voice_id || 'Matthew'
        this.playbackRate = prefs.speed || 1.0
        this.volume = prefs.volume || 1.0
      }
    } catch (error) {
      console.warn('Failed to load TTS preferences:', error)
      // Use defaults on error
    }
  }
  
  initAudioContext() {
    // Create audio context on first user interaction
    const initContext = () => {
      if (!this.audioContext) {
        this.audioContext = new (window.AudioContext || window.webkitAudioContext)()
        console.log('🎵 Audio context initialized')
      }
      // Remove listener after init
      document.removeEventListener('click', initContext)
      document.removeEventListener('keydown', initContext)
    }
    
    document.addEventListener('click', initContext, { once: true })
    document.addEventListener('keydown', initContext, { once: true })
  }
  
  /**
   * Speak text using TTS
   * @param {string} text - Text to speak
   * @param {Object} options - Speaking options
   * @returns {Promise<void>}
   */
  async speak(text, options = {}) {
    console.log('🔊 TTS speak() called:', {
      enabled: this.isEnabled,
      textLength: text?.length,
      text: text?.substring(0, 50) + '...'
    })
    
    if (!this.isEnabled || !text || text.trim().length === 0) {
      console.log('❌ TTS skipped - enabled:', this.isEnabled, 'text:', !!text)
      return
    }
    
    // Clean text (remove markdown, excessive punctuation, etc.)
    const cleanedText = this.cleanText(text)
    console.log('🧹 Cleaned text:', cleanedText.substring(0, 50) + '...')
    
    // Always use AWS Polly for consistent voice
    // (Removed Web Speech API fallback to prevent voice switching)
    
    // For longer text, use AWS Polly
    const audioData = {
      text: cleanedText,
      voiceId: options.voiceId || this.voiceId,
      messageId: options.messageId,
      priority: options.priority || 'normal'
    }
    
    if (options.immediate) {
      // Interrupt current playback for immediate messages
      this.interrupt()
      this.audioQueue = [audioData]
    } else {
      // Add to queue
      this.audioQueue.push(audioData)
    }
    
    // Start processing queue if not already playing
    if (!this.isPlaying) {
      this.processQueue()
    }
  }
  
  /**
   * Use Web Speech API for short text (instant playback)
   */
  speakWithWebAPI(text) {
    if (!window.speechSynthesis) {
      console.warn('Web Speech API not supported')
      return this.speakWithPolly({ text, voiceId: this.voiceId })
    }
    
    // Cancel any ongoing speech
    window.speechSynthesis.cancel()
    
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.rate = this.playbackRate
    utterance.pitch = 1.0
    utterance.volume = this.volume
    
    // Try to find a good voice
    const voices = window.speechSynthesis.getVoices()
    const preferredVoice = voices.find(v => 
      v.name.includes('Google') && v.lang.startsWith('en')
    ) || voices.find(v => v.lang.startsWith('en'))
    
    if (preferredVoice) {
      utterance.voice = preferredVoice
    }
    
    // Speak
    window.speechSynthesis.speak(utterance)
  }
  
  /**
   * Process audio queue
   */
  async processQueue() {
    if (this.audioQueue.length === 0) {
      this.isPlaying = false
      this.currentlyPlayingText = null
      // Dispatch event when TTS stops
      window.dispatchEvent(new CustomEvent('tts:stop'))
      document.dispatchEvent(new CustomEvent('tts:stopped'))
      return
    }
    
    this.isPlaying = true
    const audioData = this.audioQueue.shift()
    this.currentlyPlayingText = audioData.text
    
    // Dispatch event when TTS starts playing
    window.dispatchEvent(new CustomEvent('tts:start', { 
      detail: { text: audioData.text }
    }))
    
    // Also dispatch the playing event that the UI listens for
    document.dispatchEvent(new CustomEvent('tts:playing', { 
      detail: { 
        text: audioData.text,
        messageId: audioData.messageId 
      }
    }))
    
    try {
      await this.speakWithPolly(audioData)
    } catch (error) {
      console.error('TTS playback error:', error)
      // Skip this item and continue with the queue
      // (No fallback to prevent voice switching)
    }
    
    // Process next item in queue
    this.processQueue()
  }
  
  /**
   * Speak using AWS Polly
   */
  async speakWithPolly(audioData) {
    const { text, voiceId } = audioData
    
    // Rate limiting to prevent 503 errors
    const now = Date.now()
    const timeSinceLastRequest = now - this.lastRequestTime
    if (timeSinceLastRequest < this.minRequestInterval) {
      await new Promise(resolve => setTimeout(resolve, this.minRequestInterval - timeSinceLastRequest))
    }
    this.lastRequestTime = Date.now()
    
    // Retry logic for failed requests
    let retries = 3
    let lastError = null
    
    while (retries > 0) {
      try {
        // Call our TTS API
        const response = await fetch('/api/tts/synthesize', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
          },
          body: JSON.stringify({
            text: text,
            voice_id: voiceId,
            speech_marks: true
          })
        })
        
        if (!response.ok) {
          if (response.status === 503 && retries > 1) {
            // Service unavailable, wait and retry
            console.warn(`TTS 503 error, retrying in ${retries * 500}ms...`)
            await new Promise(resolve => setTimeout(resolve, retries * 500))
            retries--
            continue
          }
          throw new Error(`TTS API error: ${response.status}`)
        }
      
      // Get speech marks from header
      const speechMarksHeader = response.headers.get('X-Speech-Marks')
      if (speechMarksHeader) {
        try {
          this.currentSpeechMarks = JSON.parse(atob(speechMarksHeader))
        } catch (e) {
          console.warn('Failed to parse speech marks')
        }
      }
      
      // Get audio data
      const audioBlob = await response.blob()
      const audioUrl = URL.createObjectURL(audioBlob)
      
        // Success! Play audio and return
        await this.playAudio(audioUrl, audioData)
        
        // Cleanup
        URL.revokeObjectURL(audioUrl)
        return // Exit successfully
        
      } catch (error) {
        lastError = error
        retries--
        if (retries === 0) {
          console.error('Polly TTS error after all retries:', error)
          throw error
        }
      }
    }
    
    // If we get here, all retries failed
    throw lastError || new Error('TTS request failed')
  }
  
  /**
   * Play audio with interruption support
   */
  playAudio(audioUrl, audioData) {
    return new Promise((resolve, reject) => {
      const audio = new Audio(audioUrl)
      audio.playbackRate = this.playbackRate
      audio.volume = this.volume
      
      this.currentAudio = audio
      
      // Handle playback events
      audio.onended = () => {
        this.currentAudio = null
        this.currentSpeechMarks = null
        resolve()
      }
      
      audio.onerror = (error) => {
        this.currentAudio = null
        this.currentSpeechMarks = null
        reject(error)
      }
      
      // Track playback position for speech marks
      if (this.currentSpeechMarks) {
        this.trackSpeechMarks(audio)
      }
      
      // Play
      audio.play().catch(reject)
    })
  }
  
  /**
   * Track speech marks for word-level highlighting
   */
  trackSpeechMarks(audio) {
    let lastWordIndex = -1
    
    const updateHighlight = () => {
      if (!this.currentSpeechMarks || !audio.currentTime) return
      
      const currentTimeMs = audio.currentTime * 1000
      
      // Find current word
      for (let i = 0; i < this.currentSpeechMarks.length; i++) {
        const mark = this.currentSpeechMarks[i]
        if (mark.type === 'word' && mark.time <= currentTimeMs) {
          if (i > lastWordIndex) {
            lastWordIndex = i
            this.highlightWord(mark)
          }
        }
      }
      
      if (!audio.paused && !audio.ended) {
        requestAnimationFrame(updateHighlight)
      }
    }
    
    updateHighlight()
  }
  
  /**
   * Highlight current word being spoken
   */
  highlightWord(mark) {
    // Dispatch event for UI to handle
    window.dispatchEvent(new CustomEvent('tts:word', {
      detail: {
        word: mark.value,
        start: mark.start,
        end: mark.end,
        time: mark.time
      }
    }))
  }
  
  /**
   * Interrupt current playback
   */
  interrupt() {
    // Stop Web Speech API
    if (window.speechSynthesis) {
      window.speechSynthesis.cancel()
    }
    
    // Stop Polly audio
    if (this.currentAudio) {
      this.currentAudio.pause()
      this.currentAudio = null
      this.currentSpeechMarks = null
    }
    
    // Clear queue and current text
    this.audioQueue = []
    this.isPlaying = false
    this.currentlyPlayingText = null
    
    // Dispatch stop event
    window.dispatchEvent(new CustomEvent('tts:stop'))
    document.dispatchEvent(new CustomEvent('tts:stopped'))
    
    // Call interrupt callback if set
    if (this.interruptCallback) {
      this.interruptCallback()
    }
  }
  
  /**
   * Toggle TTS on/off
   */
  toggle() {
    this.isEnabled = !this.isEnabled
    
    // Update server preference
    this.updateServerPreference({ enabled: this.isEnabled })
    
    if (!this.isEnabled) {
      this.interrupt()
    }
    
    return this.isEnabled
  }
  
  /**
   * Update voice
   */
  setVoice(voiceId) {
    this.voiceId = voiceId
    this.updateServerPreference({ voice_id: voiceId })
  }
  
  /**
   * Update playback speed
   */
  setSpeed(rate) {
    this.playbackRate = Math.max(0.5, Math.min(2.0, rate))
    
    if (this.currentAudio) {
      this.currentAudio.playbackRate = this.playbackRate
    }
    
    this.updateServerPreference({ speed: this.playbackRate })
  }
  
  /**
   * Update volume
   */
  setVolume(volume) {
    this.volume = Math.max(0, Math.min(1, volume))
    
    if (this.currentAudio) {
      this.currentAudio.volume = this.volume
    }
    
    this.updateServerPreference({ volume: this.volume })
  }
  
  /**
   * Update preference on server
   */
  async updateServerPreference(updates) {
    console.log('🔄 Updating TTS preferences on server:', updates)
    try {
      const response = await fetch('/api/tts/preferences', {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify(updates)
      })
      
      if (response.ok) {
        const data = await response.json()
        console.log('✅ TTS preferences updated:', data.preferences)
      }
    } catch (error) {
      console.warn('Failed to update TTS preference:', error)
    }
  }
  
  /**
   * Clean text for TTS
   */
  cleanText(text) {
    // Remove markdown formatting
    text = text.replace(/\*\*(.*?)\*\*/g, '$1') // Bold
    text = text.replace(/\*(.*?)\*/g, '$1')     // Italic
    text = text.replace(/`(.*?)`/g, '$1')       // Code
    text = text.replace(/```[\s\S]*?```/g, '')  // Code blocks
    text = text.replace(/^#+\s/gm, '')          // Headers
    text = text.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1') // Links
    
    // Remove excessive punctuation
    text = text.replace(/\.{3,}/g, '...')
    text = text.replace(/!{2,}/g, '!')
    text = text.replace(/\?{2,}/g, '?')
    
    // Trim and normalize whitespace
    text = text.trim().replace(/\s+/g, ' ')
    
    return text
  }
  
  /**
   * Get available voices
   */
  async getVoices() {
    try {
      const response = await fetch('/api/tts/voices', {
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        }
      })
      
      const data = await response.json()
      return data.voices || []
    } catch (error) {
      console.error('Failed to fetch voices:', error)
      return []
    }
  }
}

// Export singleton instance
export const ttsManager = new TTSAudioManager()
