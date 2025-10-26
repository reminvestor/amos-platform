import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["settings", "speedLabel", "volumeLabel", "successMessage"]
  
  connect() {
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
    
    const button = event.currentTarget
    const originalText = button.innerHTML
    button.disabled = true
    button.innerHTML = '<i class="fas fa-spinner fa-spin me-2"></i>Testing...'
    
    const voiceId = document.getElementById('voice_id').value
    const engine = document.getElementById('engine').value
    const speed = parseFloat(document.getElementById('speed').value)
    const volume = parseFloat(document.getElementById('volume').value)
    
    // Test text in the selected language
    const testTexts = {
      'Matthew': "Hello! I'm Matthew, your AI assistant. How can I help you today?",
      'Joanna': "Hi there! I'm Joanna, ready to assist you with any questions.",
      'Amy': "Good day! I'm Amy, your British AI assistant. How may I be of service?",
      'Brian': "Hello! I'm Brian. Pleased to assist you today.",
      'Camila': "Olá! Eu sou Camila, sua assistente de IA. Como posso ajudar?",
      'Lupe': "¡Hola! Soy Lupe, tu asistente de IA. ¿En qué puedo ayudarte?",
      'Takumi': "こんにちは！タクミです。今日はどのようなご用件でしょうか？"
    }
    
    const text = testTexts[voiceId] || testTexts['Matthew']
    
    try {
      // Call TTS API
      const response = await fetch('/api/tts/synthesize', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({
          text: text,
          voice_id: voiceId,
          speech_marks: false
        })
      })
      
      if (!response.ok) throw new Error('Failed to synthesize speech')
      
      // Play audio
      const audioBlob = await response.blob()
      const audioUrl = URL.createObjectURL(audioBlob)
      const audio = new Audio(audioUrl)
      audio.playbackRate = speed
      audio.volume = volume
      
      audio.onended = () => {
        URL.revokeObjectURL(audioUrl)
        button.disabled = false
        button.innerHTML = originalText
      }
      
      audio.onerror = () => {
        URL.revokeObjectURL(audioUrl)
        button.disabled = false
        button.innerHTML = originalText
        alert('Failed to play audio. Please try again.')
      }
      
      await audio.play()
      
    } catch (error) {
      console.error('Test voice error:', error)
      button.disabled = false
      button.innerHTML = originalText
      alert('Failed to test voice. Please check your settings.')
    }
  }
  
  onSaveSuccess(event) {
    // Show success message
    this.successMessageTarget.classList.remove('d-none')
    
    // Update TTS manager if it exists
    if (window.ttsManager) {
      const data = JSON.parse(event.detail.fetchResponse.response.text)
      const prefs = data.preferences
      
      if (prefs.enabled !== undefined) {
        window.ttsManager.isEnabled = prefs.enabled
      }
      if (prefs.voice_id) {
        window.ttsManager.setVoice(prefs.voice_id)
      }
      if (prefs.speed !== undefined) {
        window.ttsManager.setSpeed(prefs.speed)
      }
      if (prefs.volume !== undefined) {
        window.ttsManager.setVolume(prefs.volume)
      }
    }
    
    // Hide message after 3 seconds
    setTimeout(() => {
      this.successMessageTarget.classList.add('d-none')
    }, 3000)
  }
  
  onSaveError(event) {
    alert('Failed to save voice settings. Please try again.')
  }
  
  updateUI() {
    const enabled = document.getElementById('tts_enabled')?.checked
    if (this.hasSettingsTarget) {
      this.settingsTarget.style.opacity = enabled ? '1' : '0.5'
      this.settingsTarget.style.pointerEvents = enabled ? 'auto' : 'none'
    }
  }
}
