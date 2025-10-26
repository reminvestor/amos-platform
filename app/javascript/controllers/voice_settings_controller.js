import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["settings", "speedLabel", "volumeLabel", "successMessage"]
  
  connect() {
    console.log('🎛️ Voice settings controller connected')
    this.updateUI()
  }
  
  togglePreview(event) {
    const enabled = event.target.checked
    if (this.hasSettingsTarget) {
      this.settingsTarget.style.opacity = enabled ? '1' : '0.5'
      this.settingsTarget.style.pointerEvents = enabled ? 'auto' : 'none'
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
  
  async testVoice(event) {
    event.preventDefault()
    
    console.log('🎤 Test voice clicked')
    
    const button = event.currentTarget
    const originalText = button.innerHTML
    button.disabled = true
    button.innerHTML = '<i class="fas fa-spinner fa-spin me-2"></i>Testing...'
    
    const voiceId = document.getElementById('voice_id').value
    const engine = document.getElementById('engine').value
    const speed = parseFloat(document.getElementById('speed').value)
    const volume = parseFloat(document.getElementById('volume').value)
    
    console.log('🎤 Test settings:', { voiceId, engine, speed, volume })
    
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
      'Thiago': "Olá! Eu sou Thiago, seu assistente de IA. Como posso ajudar você?"
    }
    
    const text = testTexts[voiceId] || testTexts['Matthew']
    
    try {
      // Call TTS API - use query params for GET-style parameters
      const params = new URLSearchParams({
        text: text,
        voice_id: voiceId,
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
          }
          if (prefs.voice_id) {
            window.ttsManager.setVoice(prefs.voice_id)
            console.log('💾 Updated voice:', prefs.voice_id)
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
      this.settingsTarget.style.opacity = enabled ? '1' : '0.5'
      this.settingsTarget.style.pointerEvents = enabled ? 'auto' : 'none'
    }
  }
}
