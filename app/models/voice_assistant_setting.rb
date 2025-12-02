# VoiceAssistantSetting - Global configuration for voice assistant features
#
# Settings include:
# - Deepgram transcription parameters (model, language, endpointing, etc.)
# - AWS Polly TTS parameters (voice, engine, sample rate, etc.)
# - Audio processing settings
class VoiceAssistantSetting < ApplicationRecord
  # Setting types
  SETTING_TYPES = %w[integer boolean string float].freeze

  validates :key, presence: true, uniqueness: true
  validates :setting_type, inclusion: { in: SETTING_TYPES }

  # Get a setting value with type casting
  def self.get(key, default = nil)
    setting = find_by(key: key)
    return default unless setting

    cast_value(setting.value, setting.setting_type)
  end

  # Set a setting value
  def self.set(key, value, setting_type: "string", description: nil)
    setting = find_or_initialize_by(key: key)
    setting.value = value.to_s
    setting.setting_type = setting_type
    setting.description = description if description
    setting.save!
    setting
  end

  # Get all settings as a hash
  def self.all_as_hash
    all.each_with_object({}) do |setting, hash|
      hash[setting.key] = cast_value(setting.value, setting.setting_type)
    end
  end

  # Type casting helper
  def self.cast_value(value, type)
    return nil if value.nil?

    case type
    when "integer"
      value.to_i
    when "boolean"
      value.to_s.downcase.in?(%w[true 1 yes])
    when "float"
      value.to_f
    else
      value.to_s
    end
  end

  # Initialize default settings
  def self.seed_defaults!
    # Deepgram Settings
    set("deepgram.model", "nova-3", setting_type: "string", description: "Deepgram model (nova-2, nova-3, etc.)")
    set("deepgram.language", "en-US", setting_type: "string", description: "Language code")
    set("deepgram.encoding", "linear16", setting_type: "string", description: "Audio encoding format")
    set("deepgram.sample_rate", 16000, setting_type: "integer", description: "Audio sample rate in Hz")
    set("deepgram.channels", 1, setting_type: "integer", description: "Number of audio channels (1 = mono)")
    set("deepgram.punctuate", true, setting_type: "boolean", description: "Add punctuation and capitalization")
    set("deepgram.interim_results", true, setting_type: "boolean", description: "Show real-time interim transcripts")
    set("deepgram.smart_format", true, setting_type: "boolean", description: "Smart formatting (dates, times, numbers)")
    set("deepgram.utterances", true, setting_type: "boolean", description: "Split into semantic units")
    set("deepgram.endpointing", 300, setting_type: "integer", description: "Silence duration for end-of-turn (ms)")
    set("deepgram.utterance_end_ms", 800, setting_type: "integer", description: "Finalize utterance after silence (ms)")
    set("deepgram.vad_events", true, setting_type: "boolean", description: "Voice activity detection events")
    set("deepgram.filler_words", false, setting_type: "boolean", description: "Transcribe filler words (um, uh)")
    set("deepgram.profanity_filter", false, setting_type: "boolean", description: "Filter profanity")
    set("deepgram.numerals", true, setting_type: "boolean", description: "Convert numbers to digits")
    set("deepgram.diarize", false, setting_type: "boolean", description: "Speaker detection")

    # Polly Settings
    set("polly.voice_id", "Matthew", setting_type: "string", description: "AWS Polly voice ID")
    set("polly.engine", "neural", setting_type: "string", description: "Polly engine (neural or standard)")
    set("polly.output_format", "pcm", setting_type: "string", description: "Audio output format")
    set("polly.sample_rate", "16000", setting_type: "string", description: "Audio sample rate")

    # Eleven Labs Settings
    set("eleven_labs.voice_id", "JBFqnCBsd6RMkjVDRZzb", setting_type: "string", description: "Default Eleven Labs voice ID (George)")
    set("eleven_labs.model_id", "eleven_turbo_v2_5", setting_type: "string", description: "Eleven Labs model ID")
    set("eleven_labs.default_provider", true, setting_type: "boolean", description: "Use Eleven Labs as default provider")

    # Audio Processing
    set("audio.buffer_size", 2048, setting_type: "integer", description: "Audio buffer size (lower = less latency)")
  end
end
