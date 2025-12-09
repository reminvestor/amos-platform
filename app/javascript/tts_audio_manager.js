/**
 * TTS Audio Manager
 * Handles text-to-speech audio playback with interruption support
 */
export default class TTSAudioManager {
  constructor() {
    // Initialize with defaults, then load user preferences
    this.isEnabled = false  // Default to OFF
    this.voiceId = 'George' // Default Eleven Labs voice
    this.provider = 'eleven_labs' // Default provider
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
        console.log('🎧 TTS Preferences Loaded:', prefs)
        
        // Default to disabled if not explicitly set
        this.isEnabled = prefs.enabled === true
        this.provider = prefs.provider || 'eleven_labs'
        
        // Robustness: If provider says eleven_labs but we have no eleven_labs_voice_id, check if we have a voice_id that looks like an Eleven Labs ID?
        // Or if provider says polly but voice_id is missing.
        
        if (this.provider === 'eleven_labs') {
          // Only use eleven_labs_voice_id if present.
          // If falling back to voice_id, ensure it's NOT a known Polly voice.
          const pollyVoices = ['Matthew', 'Joanna', 'Ivy', 'Kendra', 'Kimberly', 'Salli', 'Joey', 'Justin', 'Kevin', 'Ruth', 'Stephen', 'Olivia', 'Aria', 'Ayanda', 'Bianca', 'Brian', 'Camila', 'Carla', 'Celine', 'Chantal', 'Conchita', 'Cristiano', 'Dora', 'Emma', 'Enrique', 'Ewa', 'Filiz', 'Gabrielle', 'Geraint', 'Giorgio', 'Gwyneth', 'Hans', 'Ines', 'Isabelle', 'Jacek', 'Jan', 'Karl', 'Lea', 'Liv', 'Lotte', 'Lucia', 'Lupe', 'Mads', 'Maja', 'Marlene', 'Mathieu', 'Maxim', 'Mia', 'Miguel', 'Mizuki', 'Naja', 'Nicole', 'Penelope', 'Raveena', 'Ricardo', 'Ruben', 'Russell', 'Seoyeon', 'Takumi', 'Tatyana', 'Vicki', 'Vitoria', 'Zeina', 'Zhiyu'];
          
          const preferredVoice = prefs.eleven_labs_voice_id;
          const legacyVoice = prefs.voice_id;
          
          if (preferredVoice && !pollyVoices.includes(preferredVoice)) {
             this.voiceId = preferredVoice;
          } else if (legacyVoice && !pollyVoices.includes(legacyVoice)) {
             this.voiceId = legacyVoice;
          } else {
             this.voiceId = 'George'; // Default Eleven Labs voice
          }
        } else {
          this.voiceId = prefs.voice_id || 'Matthew'
        }
        
        console.log(`🎧 TTS Configured: Provider=${this.provider}, Voice=${this.voiceId}`)

        this.playbackRate = prefs.speed || 1.0
        this.volume = prefs.volume || 1.0
      }
    } catch (error) {
      console.warn('Failed to load TTS preferences:', error)
      // Use defaults on error
    }
  }
  
  initAudioContext() {
    // iOS detection
    this.isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || 
                 (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
    
    // Create audio context and unlock iOS audio on first user interaction
    const initContext = () => {
      if (!this.audioContext) {
        this.audioContext = new (window.AudioContext || window.webkitAudioContext)()
        console.log('🎵 Audio context initialized')
      }
      
      // Resume audio context if suspended (required for iOS)
      if (this.audioContext.state === 'suspended') {
        this.audioContext.resume()
        console.log('🎵 Audio context resumed')
      }
      
      // iOS requires playing a sound during user gesture to unlock audio
      if (this.isIOS && !this.iosAudioUnlocked) {
        this.unlockIOSAudio()
      }
      
      // Remove listener after init
      document.removeEventListener('click', initContext)
      document.removeEventListener('touchstart', initContext)
      document.removeEventListener('keydown', initContext)
    }
    
    document.addEventListener('click', initContext, { once: false })
    document.addEventListener('touchstart', initContext, { once: false })
    document.addEventListener('keydown', initContext, { once: true })
  }
  
  /**
   * Unlock iOS audio by playing a silent sound during user gesture
   */
  unlockIOSAudio() {
    try {
      // Create and play a silent audio to unlock iOS audio playback
      const silentAudio = new Audio('data:audio/mp3;base64,SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU4Ljc2LjEwMAAAAAAAAAAAAAAA/+M4wAAAAAAAAAAAAEluZm8AAAAPAAAAAgAAAbAAqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq//////////////////////////////////////////////////////////////////8AAAAATGF2YzU4LjEzAAAAAAAAAAAAAAAAJAAAAAAAAAAAAbD//////////////////////////////////////////////////////////////////')
      silentAudio.volume = 0.01
      silentAudio.play().then(() => {
        this.iosAudioUnlocked = true
        console.log('🔓 iOS audio unlocked')
        silentAudio.pause()
        silentAudio.remove?.()
      }).catch(e => {
        console.log('🔒 iOS audio unlock pending (will retry on next interaction)')
      })
    } catch (e) {
      console.warn('iOS audio unlock error:', e)
    }
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
    
    // For longer text, use AWS Polly or Eleven Labs
    const audioData = {
      text: cleanedText,
      voiceId: options.voiceId || this.voiceId,
      provider: options.provider || this.provider,
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
      await this.speakWithProvider(audioData)
    } catch (error) {
      console.error('TTS playback error:', error)
      // Skip this item and continue with the queue
      // (No fallback to prevent voice switching)
    }
    
    // Process next item in queue
    this.processQueue()
  }
  
  /**
   * Speak using selected provider (AWS Polly or Eleven Labs)
   */
  async speakWithProvider(audioData) {
    const { text, voiceId, provider } = audioData
    
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
            provider: provider || 'eleven_labs',
            speech_marks: true // Eleven Labs ignores this for now
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
          console.error('TTS error after all retries:', error)
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
  setVoice(voiceId, provider = 'eleven_labs') {
    this.voiceId = voiceId
    this.provider = provider
    
    // Update based on provider
    if (provider === 'eleven_labs') {
      this.updateServerPreference({ provider: 'eleven_labs', voice_id: voiceId })
    } else {
      this.updateServerPreference({ provider: 'polly', voice_id: voiceId })
    }
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
  async getVoices(provider = 'eleven_labs') {
    try {
      const response = await fetch(`/api/tts/voices?provider=${provider}`, {
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
