# frozen_string_literal: true

module Learning
  # ImplicitFeedbackDetector - Extract learning signals from conversation patterns
  #
  # Users often don't click thumbs up/down, but their behavior speaks volumes:
  # - "Thanks, perfect!" = positive signal
  # - "No, that's wrong" = negative signal
  # - Asking the same thing again = retry (negative)
  # - User edits the output = partial success
  # - Quick follow-up with unrelated topic = task complete (positive)
  #
  # This service parses conversation history to extract these implicit signals
  # and converts them to soft feedback that influences experience learning.
  #
  # Integration:
  # - Called after conversation turns
  # - Creates ImplicitFeedback records
  # - Feeds into DecisionTrace outcome recording
  #
  class ImplicitFeedbackDetector
    attr_reader :entity, :session_id

    # Signal strength (0-1) - how confident we are in the signal
    POSITIVE_KEYWORDS = {
      'thanks' => 0.6,
      'thank you' => 0.7,
      'perfect' => 0.8,
      'exactly' => 0.8,
      'great' => 0.6,
      'awesome' => 0.7,
      'looks good' => 0.7,
      'love it' => 0.8,
      'nice' => 0.5,
      'works' => 0.5,
      "that's what i wanted" => 0.9,
      "that's right" => 0.7
    }.freeze

    NEGATIVE_KEYWORDS = {
      'no,' => 0.6,
      'no that' => 0.7,
      'wrong' => 0.7,
      "that's not" => 0.7,
      'not what i' => 0.8,
      'try again' => 0.7,
      'actually' => 0.4,  # Often indicates correction
      "don't" => 0.4,
      'incorrect' => 0.8,
      'not right' => 0.7,
      'fix' => 0.5,
      'undo' => 0.6,
      'revert' => 0.6
    }.freeze

    # Retry detection - user asks similar thing again
    RETRY_SIMILARITY_THRESHOLD = 0.75

    def initialize(entity:, session_id:)
      @entity = entity
      @session_id = session_id
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MAIN ENTRY POINT
    # ═══════════════════════════════════════════════════════════════════════════

    # Analyze a conversation and extract implicit feedback signals
    def analyze_conversation(messages)
      return [] if messages.blank? || messages.count < 2

      signals = []

      # Analyze consecutive message pairs (Amos response -> User reply)
      messages.each_cons(2) do |prev_msg, curr_msg|
        # Skip if not Amos -> User pattern
        next unless assistant_message?(prev_msg) && user_message?(curr_msg)

        # Detect signals
        signal = detect_signal(prev_msg, curr_msg, messages)
        signals << signal if signal.present?
      end

      signals
    end

    # Process signals and update learning systems
    def process_signals!(signals)
      return if signals.empty?

      signals.each do |signal|
        process_signal!(signal)
      end

      Rails.logger.info "[ImplicitFeedback] Processed #{signals.count} signals for session #{session_id}"
    end

    # Convenience: analyze and process in one call
    def analyze_and_process!(messages)
      signals = analyze_conversation(messages)
      process_signals!(signals)
      signals
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # SIGNAL DETECTION
    # ═══════════════════════════════════════════════════════════════════════════

    def detect_signal(amos_message, user_reply, all_messages)
      user_content = extract_content(user_reply).downcase.strip

      # Check for positive keywords
      positive_score = detect_positive_signal(user_content)
      if positive_score > 0
        return build_signal(:positive, positive_score, amos_message, user_reply, 'keyword_match')
      end

      # Check for negative keywords
      negative_score = detect_negative_signal(user_content)
      if negative_score > 0
        return build_signal(:negative, negative_score, amos_message, user_reply, 'keyword_match')
      end

      # Check for retry pattern (user asks same thing again)
      if retry_detected?(amos_message, user_reply, all_messages)
        return build_signal(:negative, 0.7, amos_message, user_reply, 'retry_detected')
      end

      # Check for quick topic change (often indicates task complete)
      if quick_topic_change?(amos_message, user_reply)
        return build_signal(:positive, 0.4, amos_message, user_reply, 'topic_change')
      end

      nil
    end

    def detect_positive_signal(content)
      max_score = 0

      POSITIVE_KEYWORDS.each do |keyword, score|
        if content.include?(keyword.downcase)
          max_score = [max_score, score].max
        end
      end

      max_score
    end

    def detect_negative_signal(content)
      max_score = 0

      NEGATIVE_KEYWORDS.each do |keyword, score|
        if content.include?(keyword.downcase)
          max_score = [max_score, score].max
        end
      end

      max_score
    end

    def retry_detected?(amos_message, user_reply, all_messages)
      # Find the original user message that Amos was responding to
      amos_index = all_messages.index(amos_message)
      return false unless amos_index && amos_index > 0

      original_user_message = all_messages[amos_index - 1]
      return false unless user_message?(original_user_message)

      # Compare original request with current reply
      original_content = extract_content(original_user_message)
      current_content = extract_content(user_reply)

      # Simple word overlap similarity
      similarity = calculate_similarity(original_content, current_content)
      similarity >= RETRY_SIMILARITY_THRESHOLD
    end

    def quick_topic_change?(amos_message, user_reply)
      # If user's reply is very different from Amos's message, might indicate moving on
      amos_content = extract_content(amos_message)
      user_content = extract_content(user_reply)

      # Very low similarity might indicate topic change (task was handled)
      similarity = calculate_similarity(amos_content, user_content)

      # Also check that user isn't asking a question (which would be continuation)
      is_new_request = !user_content.match?(/\?$/) && 
                       !user_content.match?(/^(what|how|why|can you|could you)/i)

      similarity < 0.2 && is_new_request && user_content.length > 20
    end

    def calculate_similarity(text1, text2)
      return 0 if text1.blank? || text2.blank?

      words1 = Set.new(text1.downcase.gsub(/[^\w\s]/, '').split)
      words2 = Set.new(text2.downcase.gsub(/[^\w\s]/, '').split)

      # Remove common stop words
      stop_words = Set.new(%w[the a an is are was were be been being have has had do does did will would could should may might must shall can])
      words1 -= stop_words
      words2 -= stop_words

      return 0 if words1.empty? || words2.empty?

      intersection = words1 & words2
      union = words1 | words2

      intersection.size.to_f / union.size
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # SIGNAL PROCESSING
    # ═══════════════════════════════════════════════════════════════════════════

    def build_signal(type, strength, amos_message, user_reply, detection_method)
      {
        type: type,
        strength: strength,
        amos_message_id: extract_id(amos_message),
        user_reply_id: extract_id(user_reply),
        detection_method: detection_method,
        detected_at: Time.current,
        context: {
          amos_content_preview: extract_content(amos_message).truncate(100),
          user_content_preview: extract_content(user_reply).truncate(100)
        }
      }
    end

    def process_signal!(signal)
      # Find related DecisionTraces
      traces = find_related_traces(signal)

      if traces.any?
        outcome = signal[:type] == :positive ? 'success' : 'failure'
        quality = signal[:type] == :positive ? 0.7 : 0.4

        traces.each do |trace|
          # Only update if not already set (don't override explicit feedback)
          next if trace.outcome.present?

          trace.update!(
            outcome: outcome,
            outcome_quality_score: quality,
            outcome_recorded_at: Time.current,
            outcome_details: {
              source: 'implicit_feedback',
              detection_method: signal[:detection_method],
              signal_strength: signal[:strength],
              amos_message_id: signal[:amos_message_id]
            }
          )

          Rails.logger.info "[ImplicitFeedback] Updated trace #{trace.id} with #{outcome} " \
                            "(strength: #{signal[:strength]}, method: #{signal[:detection_method]})"
        end
      end

      # Update experience utility scores
      update_experience_scores(signal)
    end

    def find_related_traces(signal)
      return [] unless signal[:amos_message_id]

      # Find traces from around the time of the Amos message
      message = ScoutMessage.find_by(id: signal[:amos_message_id])
      return [] unless message

      DecisionTrace.where(entity: entity)
                   .where("metadata->>'session_id' = ?", session_id)
                   .where('created_at BETWEEN ? AND ?',
                          message.created_at - 2.minutes,
                          message.created_at + 1.minute)
    end

    def update_experience_scores(signal)
      return unless entity.present?

      # Get task type from related traces or metadata
      traces = find_related_traces(signal)
      task_type = traces.first&.metadata&.dig('task_type')
      return unless task_type.present?

      success = signal[:type] == :positive

      # Find recently applied experiences for this task type
      # Use a smaller weight since implicit signals are less certain
      weight = signal[:strength] * 0.5  # Half weight for implicit signals

      TaskExperience.where(entity: entity, task_type: task_type)
                    .active
                    .where('last_applied_at > ?', 30.minutes.ago)
                    .each do |experience|
        adjustment = success ? (0.05 * weight) : (-0.02 * weight)
        experience.adjust_utility_score!(adjustment)

        Rails.logger.debug "[ImplicitFeedback] Adjusted experience #{experience.id} by #{adjustment.round(4)}"
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    def assistant_message?(msg)
      role = msg.respond_to?(:role) ? msg.role : msg[:role] || msg['role']
      role.to_s == 'assistant'
    end

    def user_message?(msg)
      role = msg.respond_to?(:role) ? msg.role : msg[:role] || msg['role']
      role.to_s == 'user'
    end

    def extract_content(msg)
      if msg.respond_to?(:content)
        msg.content.to_s
      else
        (msg[:content] || msg['content']).to_s
      end
    end

    def extract_id(msg)
      if msg.respond_to?(:id)
        msg.id
      else
        msg[:id] || msg['id']
      end
    end
  end
end
