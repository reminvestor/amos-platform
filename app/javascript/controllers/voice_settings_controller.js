import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["settings", "speedLabel", "volumeLabel", "successMessage"]

  connect() {
    console.log('🎛️ Voice settings controller connected')
    this.updateUI()
    this.previewTimeout = null
    this.currentAudio = null
  }

  disconnect() {
    // Clean up audio when controller disconnects
    if (this.currentAudio) {
      this.currentAudio.pause()
      this.currentAudio = null
    }
    if (this.previewTimeout) {
      clearTimeout(this.previewTimeout)
    }
  }
  
  togglePreview(event) {
    const enabled = event.target.checked
    if (this.hasSettingsTarget) {
      if (enabled) {
        this.settingsTarget.classList.remove('settings-disabled')
      } else {
        this.settingsTarget.classList.add('settings-disabled')
      }
    }
  }
  
  toggleProvider(event) {
    const provider = event.target.value
    console.log('🎛️ Toggling provider to:', provider)
    
    const elevenLabsContainer = document.getElementById('eleven_labs_voices_container')
    const pollyContainer = document.getElementById('polly_voices_container')

    if (provider === 'eleven_labs') {
      if (elevenLabsContainer) elevenLabsContainer.style.display = 'block'
      if (pollyContainer) pollyContainer.style.display = 'none'
      
      // Trigger preview for the newly visible voice
      const voiceEl = document.getElementById('eleven_labs_voice_id')
      if (voiceEl) this.playVoicePreview(voiceEl.value)
    } else {
      if (elevenLabsContainer) elevenLabsContainer.style.display = 'none'
      if (pollyContainer) pollyContainer.style.display = 'block'
      
      // Trigger preview for the newly visible voice
      const voiceEl = document.getElementById('voice_id')
      if (voiceEl) this.playVoicePreview(voiceEl.value)
    }
  }

  updateSpeedLabel(event) {
    const value = parseFloat(event.target.value).toFixed(1)
    this.speedLabelTarget.textContent = `${value}x`
  }
  
  updateVolumeLabel(event) {
    const value = Math.round(parseFloat(event.target.value) * 100)
    this.volumeLabelTarget.textContent = `${value}%`
  }

  // Auto-play voice sample when dropdown changes (debounced)
  updatePreview(event) {
    console.log('🎤 Voice changed, scheduling preview...')

    // Stop any currently playing audio
    if (this.currentAudio) {
      this.currentAudio.pause()
      this.currentAudio = null
    }

    // Clear any pending preview
    if (this.previewTimeout) {
      clearTimeout(this.previewTimeout)
    }

    // Debounce: wait 300ms after user stops changing voices
    this.previewTimeout = setTimeout(() => {
      this.playVoicePreview(event.target.value)
    }, 300)
  }

  // Play a short voice preview sample
  async playVoicePreview(voiceId) {
    console.log('🎤 Playing preview for voice:', voiceId)

    const speed = parseFloat(document.getElementById('speed')?.value || 1.0)
    const volume = parseFloat(document.getElementById('volume')?.value || 1.0)
    const engine = document.getElementById('engine')?.value || 'neural'
    // Correctly identify the provider based on the voice ID if needed, or use the dropdown
    // If the user is switching providers, the dropdown might be updated but we need to be sure
    const providerDropdown = document.getElementById('provider')
    const provider = providerDropdown ? providerDropdown.value : 'eleven_labs'
    
    // If the voiceId passed doesn't match the provider, try to fix it
    // This happens when switching provider and the event is fired before we updated voiceId
    let actualVoiceId = voiceId;
    if (provider === 'eleven_labs') {
        actualVoiceId = document.getElementById('eleven_labs_voice_id')?.value || voiceId;
    } else {
        actualVoiceId = document.getElementById('voice_id')?.value || voiceId;
    }
    
    console.log('🎤 Resolved preview params:', { provider, actualVoiceId, engine, speed })

    // Short preview texts for quick sampling
    const previewTexts = {
      // US English
      'Aria': "Hello! I'm Aria.",
      'Matthew': "Hello! I'm Matthew.",
      'Joanna': "Hi there! I'm Joanna.",
      'Ivy': "Hi! I'm Ivy.",
      'Kendra': "Hello! I'm Kendra.",
      'Kimberly': "Hi there! I'm Kimberly.",
      'Salli': "Hello! I'm Salli.",
      'Joey': "Hey there! I'm Joey.",
      'Justin': "Hello! I'm Justin.",
      'Kevin': "Hi! I'm Kevin.",
      'Ruth': "Hello! I'm Ruth.",
      'Stephen': "Good day! I'm Stephen.",
      // UK English
      'Amy': "Hello! I'm Amy.",
      'Emma': "Hello! I'm Emma.",
      'Brian': "Hello! I'm Brian.",
      'Arthur': "Hello! I'm Arthur.",
      // Australian
      'Olivia': "Hi there! I'm Olivia.",
      // Spanish
      'Lucia': "¡Hola! Soy Lucía.",
      'Sergio': "¡Hola! Soy Sergio.",
      'Lupe': "¡Hola! Soy Lupe.",
      'Pedro': "¡Hola! Soy Pedro.",
      'Mia': "¡Hola! Soy Mía.",
      'Andres': "¡Hola! Soy Andrés.",
      'Conchita': "¡Hola! Soy Conchita.",
      // French
      'Lea': "Bonjour! Je suis Léa.",
      'Mathieu': "Bonjour! Je suis Mathieu.",
      'Celine': "Bonjour! Je suis Céline.",
      // German
      'Vicki': "Hallo! Ich bin Vicki.",
      'Hans': "Hallo! Ich bin Hans.",
      // Italian
      'Bianca': "Ciao! Sono Bianca.",
      'Adriano': "Ciao! Sono Adriano.",
      // Portuguese
      'Camila': "Olá! Eu sou Camila.",
      'Vitoria': "Olá! Eu sou Vitória.",
      'Thiago': "Olá! Eu sou Thiago.",
      'Ricardo': "Olá! Eu sou Ricardo.",
      // Eleven Labs
      'Rachel': "Hi! I'm Rachel.",
      'Drew': "Hello, I'm Drew.",
      'Clyde': "Hello, I'm Clyde.",
      'Mimi': "Hi! I'm Mimi.",
      'Fin': "Hello! I'm Fin.",
      'Nicole': "Hi, I'm Nicole.",
      'George': "Hello! I'm George.",
      'Emily': "Hi! I'm Emily.",
      'Charlie': "G'day! I'm Charlie."
    }

    const text = previewTexts[actualVoiceId] || previewTexts['Matthew'] || "Hello! This is a voice preview."

    try {
      const params = new URLSearchParams({
        text: text,
        voice_id: actualVoiceId,
        provider: provider,
        engine: engine,
        speech_marks: 'false'
      })

      const response = await fetch(`/api/tts/synthesize?${params}`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        }
      })

      if (!response.ok) {
        console.error('🔴 TTS preview API error:', response.status)
        return // Silently fail for preview
      }

      // Play audio
      const audioBlob = await response.blob()
      const audioUrl = URL.createObjectURL(audioBlob)
      const audio = new Audio(audioUrl)
      audio.playbackRate = speed
      audio.volume = volume

      // Store reference to current audio
      this.currentAudio = audio

      audio.onended = () => {
        URL.revokeObjectURL(audioUrl)
        if (this.currentAudio === audio) {
          this.currentAudio = null
        }
      }

      audio.onerror = () => {
        URL.revokeObjectURL(audioUrl)
        if (this.currentAudio === audio) {
          this.currentAudio = null
        }
      }

      await audio.play()
      console.log('✅ Voice preview playing')

    } catch (error) {
      console.error('Preview error (silently handled):', error)
      // Don't show alert for preview errors - just log them
    }
  }

  async testVoice(event) {
    event.preventDefault()
    
    console.log('🎤 Test voice clicked')
    
    const button = event.currentTarget
    const originalText = button.innerHTML
    button.disabled = true
    button.innerHTML = '<i data-lucide="loader" class="icon-spin me-2"></i>Testing...'
    // Re-initialize Lucide icons for the new icon
    if (typeof lucide !== 'undefined') lucide.createIcons()
    
    const providerEl = document.getElementById('provider')
    const provider = providerEl ? providerEl.value : 'unknown'
    
    let voiceId
    const elevenLabsEl = document.getElementById('eleven_labs_voice_id')
    const pollyEl = document.getElementById('voice_id')
    
    if (provider === 'eleven_labs') {
      voiceId = elevenLabsEl ? elevenLabsEl.value : null
      // Fallback if element exists but value is empty (e.g. not selected yet)
      if (!voiceId && elevenLabsEl && elevenLabsEl.options.length > 0) {
         voiceId = elevenLabsEl.options[0].value
      }
      console.log('🎤 Selected Eleven Labs voice:', voiceId, 'from element:', elevenLabsEl)
    } else {
      voiceId = pollyEl ? pollyEl.value : null
      console.log('🎤 Selected Polly voice:', voiceId, 'from element:', pollyEl)
    }
    
    if (!voiceId) {
       console.error('❌ No voice ID found for provider:', provider)
       button.disabled = false
       button.innerHTML = originalText
       alert('Please select a voice first.')
       return
    }
    
    const engine = document.getElementById('engine')?.value || 'neural'
    const speed = parseFloat(document.getElementById('speed').value)
    const volume = parseFloat(document.getElementById('volume').value)
    
    console.log('🎤 Test settings:', { provider, voiceId, engine, speed, volume })
    
    // Test text in the selected language
    const testTexts = {
      // US English
      'Matthew': "Hello! I'm Matthew, your AI assistant. How can I help you today?",
      'Joanna': "Hi there! I'm Joanna, ready to assist you with any questions.",
      'Ivy': "Hi! I'm Ivy. I'm here to help you learn new things!",
      'Kendra': "Hello! I'm Kendra, your friendly AI assistant.",
      'Kimberly': "Hi there! I'm Kimberly. Let me know how I can assist you.",
      'Salli': "Hello! I'm Salli, happy to help with whatever you need.",
      'Joey': "Hey there! I'm Joey, your AI assistant. What can I do for you?",
      'Justin': "Hello! I'm Justin. How may I assist you today?",
      'Kevin': "Hi! I'm Kevin. I'm excited to help you!",
      'Ruth': "Hello! I'm Ruth, your AI assistant. I'm here to make things easier for you.",
      'Stephen': "Good day! I'm Stephen, ready to assist with any task.",
      'Olivia': "Hi there! I'm Olivia, your friendly AI companion.",
      // Spanish - US
      'Lupe': "¡Hola! Soy Lupe, tu asistente de IA. ¿En qué puedo ayudarte?",
      'Pedro': "¡Hola! Soy Pedro, tu asistente virtual. ¿Cómo puedo servirte?",
      // Spanish - Spain
      'Lucia': "¡Hola! Soy Lucía, tu asistente de inteligencia artificial. ¿En qué puedo ayudarte?",
      'Sergio': "¡Hola! Soy Sergio, tu asistente virtual. ¿Qué necesitas?",
      // Spanish - Mexico
      'Mia': "¡Hola! Soy Mía, tu asistente de IA. ¿En qué te puedo ayudar?",
      'Andres': "¡Hola! Soy Andrés, tu asistente virtual. ¿Cómo te puedo servir?",
      // Portuguese - Portugal
      'Ines': "Olá! Eu sou Inês, a sua assistente de IA. Como posso ajudar?",
      // Portuguese - Brazil
      'Camila': "Olá! Eu sou Camila, sua assistente de IA. Como posso ajudar?",
      'Vitoria': "Olá! Eu sou Vitória, sua assistente virtual. Em que posso ajudar?",
      'Thiago': "Olá! Eu sou Thiago, seu assistente de IA. Como posso ajudar você?",
      // Eleven Labs
      'Rachel': "Hi! I'm Rachel, your AI assistant. I'm here to help you with whatever you need.",
      'Drew': "Hello, I'm Drew. I can read the latest news or help you with information.",
      'Clyde': "Hello, I'm Clyde. I've got a deep voice for serious matters.",
      'Mimi': "Hi! I'm Mimi. I'm young and full of energy!",
      'Fin': "Hello! I'm Fin. I'm ready to get things done quickly!",
      'Nicole': "Hi, I'm Nicole. I can speak softly if you prefer.",
      'George': "Hello! I'm George. I can assist you with a proper British accent.",
      'Emily': "Hi! I'm Emily. I'm calm and ready to listen.",
      'Charlie': "G'day! I'm Charlie. Let's have a chat, mate!"
    }
    
    const text = testTexts[voiceId] || testTexts['Matthew'] || "Hello! This is a test of the voice synthesis system."
    
    try {
      // Call TTS API - use query params for GET-style parameters
      // Ensure we force the provider if it's Eleven Labs but voiceId might be ambiguous or stale
      const params = new URLSearchParams({
        text: text,
        voice_id: voiceId,
        provider: provider,
        engine: engine,
        speech_marks: 'false'
      })
      
      const response = await fetch(`/api/tts/synthesize?${params}`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        }
      })
      
      if (!response.ok) {
        const errorText = await response.text()
        console.error('🔴 TTS API error:', response.status, errorText)
        throw new Error(`Failed to synthesize speech: ${response.status}`)
      }
      
      console.log('✅ TTS API response OK, creating audio...')
      
      // Play audio
      const audioBlob = await response.blob()
      console.log('🎵 Audio blob created:', audioBlob.size, 'bytes, type:', audioBlob.type)
      
      const audioUrl = URL.createObjectURL(audioBlob)
      const audio = new Audio(audioUrl)
      audio.playbackRate = speed
      audio.volume = volume
      
      console.log('🔊 Playing audio with speed:', speed, 'volume:', volume)
      
      audio.onended = () => {
        console.log('✅ Audio playback ended')
        URL.revokeObjectURL(audioUrl)
        button.disabled = false
        button.innerHTML = originalText
      }
      
      audio.onerror = (err) => {
        console.error('🔴 Audio playback error:', err)
        URL.revokeObjectURL(audioUrl)
        button.disabled = false
        button.innerHTML = originalText
        alert('Failed to play audio. Please try again.')
      }
      
      try {
        await audio.play()
        console.log('🎤 Audio playing...')
      } catch (playError) {
        console.error('🔴 Play failed:', playError)
        throw playError
      }
      
    } catch (error) {
      console.error('Test voice error:', error)
      button.disabled = false
      button.innerHTML = originalText
      alert('Failed to test voice. Please check your settings.')
    }
  }
  
  async saveSettings(event) {
    event.preventDefault()
    
    console.log('💾 Saving voice settings...')
    
    const form = event.target
    const formData = new FormData(form)
    
    // Handle dynamic voice ID based on provider
    const provider = formData.get('provider')
    if (provider === 'eleven_labs') {
      formData.set('voice_id', formData.get('eleven_labs_voice_id'))
    } else {
      formData.set('voice_id', formData.get('voice_id'))
    }
    
    // Log what we're sending
    console.log('💾 Form data:', Object.fromEntries(formData))
    
    try {
      const response = await fetch(form.action, {
        method: 'PATCH',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: formData
      })
      
      console.log('💾 Save response status:', response.status)
      
      if (!response.ok) {
        const errorText = await response.text()
        console.error('💾 Save failed:', response.status, errorText)
        throw new Error(`Save failed: ${response.status}`)
      }
      
      const data = await response.json()
      console.log('💾 Saved preferences:', data)
      
      // Show success message
      this.successMessageTarget.classList.remove('d-none')
      
      // Update TTS manager if it exists
      if (window.ttsManager && data.preferences) {
        console.log('💾 Updating TTS manager with new preferences')
        const prefs = data.preferences
        
        try {
          if (prefs.enabled !== undefined) {
            window.ttsManager.isEnabled = prefs.enabled
            console.log('💾 Updated enabled:', prefs.enabled)
            
            // Update the TTS button in the Scout interface
            if (window.updateTTSButton && typeof window.updateTTSButton === 'function') {
              window.updateTTSButton()
              console.log('💾 Updated TTS button state')
            }
          }
          if (prefs.provider) {
            // We don't track provider in TTS manager currently, but could
            console.log('💾 Updated provider:', prefs.provider)
          }
          // Set voice ID regardless of provider - manager handles routing
          const newVoiceId = prefs.eleven_labs_voice_id || prefs.voice_id
          if (newVoiceId) {
            window.ttsManager.setVoice(newVoiceId, prefs.provider || 'eleven_labs')
            console.log('💾 Updated voice:', newVoiceId)
          }
          if (prefs.speed !== undefined) {
            window.ttsManager.setSpeed(prefs.speed)
            console.log('💾 Updated speed:', prefs.speed)
          }
          if (prefs.volume !== undefined) {
            window.ttsManager.setVolume(prefs.volume)
            console.log('💾 Updated volume:', prefs.volume)
          }
        } catch (ttsError) {
          console.error('💾 Error updating TTS manager:', ttsError)
        }
      }
      
      // Hide message after 3 seconds
      setTimeout(() => {
        this.successMessageTarget.classList.add('d-none')
      }, 3000)
      
    } catch (error) {
      console.error('Save settings error:', error)
      alert('Failed to save voice settings. Please try again.')
    }
  }
  
  updateUI() {
    const enabled = document.getElementById('tts_enabled')?.checked
    if (this.hasSettingsTarget) {
      if (enabled) {
        this.settingsTarget.classList.remove('settings-disabled')
      } else {
        this.settingsTarget.classList.add('settings-disabled')
      }
    }
  }
}
