# CommunicationLearningJob
#
# Analyzes user interactions with Amos to learn communication preferences.
# Runs periodically (via nightly job) or after significant feedback events.
#
class CommunicationLearningJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    Rails.logger.info "[CommunicationLearning] Analyzing preferences for user #{user.id}"

    # Get recent feedback
    recent_feedback = UserFeedback.where(user: user)
                                  .where('created_at > ?', 30.days.ago)
                                  .order(created_at: :desc)
                                  .limit(100)

    return if recent_feedback.empty?

    # Analyze feedback patterns
    analysis = analyze_feedback_patterns(recent_feedback)

    # Get or create communication preferences
    comm_pref = user.communication_preference || user.build_communication_preference

    # Apply learned patterns
    apply_learned_patterns(comm_pref, analysis)

    comm_pref.last_learning_update = Time.current
    comm_pref.save!

    Rails.logger.info "[CommunicationLearning] Updated preferences for user #{user.id}: #{comm_pref.attributes.slice('formality_level', 'verbosity_level')}"
  end

  private

  def analyze_feedback_patterns(feedbacks)
    patterns = {
      positive_count: 0,
      negative_count: 0,
      verbosity_signals: [],
      formality_signals: [],
      message_lengths: []
    }

    feedbacks.each do |feedback|
      if feedback.rating == 'positive' || feedback.helpful == true
        patterns[:positive_count] += 1
      elsif feedback.rating == 'negative' || feedback.helpful == false
        patterns[:negative_count] += 1
      end

      # Check for verbosity-related feedback
      comment = feedback.comment&.downcase || ''
      if comment.include?('too long') || comment.include?('too verbose') || comment.include?('too much')
        patterns[:verbosity_signals] << :decrease
      elsif comment.include?('too short') || comment.include?('more detail') || comment.include?('explain more')
        patterns[:verbosity_signals] << :increase
      end

      # Check for formality-related feedback
      if comment.include?('too formal') || comment.include?('too stiff')
        patterns[:formality_signals] << :decrease
      elsif comment.include?('too casual') || comment.include?('more professional')
        patterns[:formality_signals] << :increase
      end
    end

    # Analyze message lengths from recent conversations
    messages = ScoutMessage.where(user: feedbacks.first.user)
                           .where('created_at > ?', 30.days.ago)
                           .where(role: 'user')
                           .limit(50)

    messages.each do |msg|
      patterns[:message_lengths] << msg.content.to_s.length
    end

    patterns
  end

  def apply_learned_patterns(comm_pref, analysis)
    # Adjust verbosity based on signals
    verbosity_adjustment = analysis[:verbosity_signals].count(:decrease) - analysis[:verbosity_signals].count(:increase)
    if verbosity_adjustment > 0
      comm_pref.verbosity_level = [comm_pref.verbosity_level - 1, 1].max
    elsif verbosity_adjustment < 0
      comm_pref.verbosity_level = [comm_pref.verbosity_level + 1, 5].min
    end

    # Adjust formality based on signals
    formality_adjustment = analysis[:formality_signals].count(:decrease) - analysis[:formality_signals].count(:increase)
    if formality_adjustment > 0
      comm_pref.formality_level = [comm_pref.formality_level - 1, 1].max
    elsif formality_adjustment < 0
      comm_pref.formality_level = [comm_pref.formality_level + 1, 5].min
    end

    # Store analysis results
    comm_pref.learned_patterns = comm_pref.learned_patterns.merge({
      last_analysis: Time.current.iso8601,
      feedback_count: analysis[:positive_count] + analysis[:negative_count],
      positive_ratio: analysis[:positive_count].to_f / [(analysis[:positive_count] + analysis[:negative_count]), 1].max,
      avg_message_length: analysis[:message_lengths].any? ? (analysis[:message_lengths].sum / analysis[:message_lengths].length.to_f).round : nil
    })
  end
end
