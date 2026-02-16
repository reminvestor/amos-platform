# frozen_string_literal: true

module Admin
  class AmosMindController < Admin::BaseController
    def index
      @entity = current_entity

      # Thinking sessions
      @recent_sessions = AmosThinkingSession.where(entity: @entity)
                                             .recent
                                             .limit(10)

      # Working memory
      @active_thoughts = AmosWorkingMemory.active
                                           .where(entity: @entity)
                                           .by_salience
                                           .limit(20)

      @thought_stats = {
        active: AmosWorkingMemory.active.where(entity: @entity).count,
        resolved: AmosWorkingMemory.where(entity: @entity, status: 'resolved').count,
        archived: AmosWorkingMemory.where(entity: @entity, status: 'archived').count,
        avg_salience: AmosWorkingMemory.active.where(entity: @entity).average(:salience)&.round(2) || 0,
        high_salience: AmosWorkingMemory.active.where(entity: @entity).where('salience >= 0.7').count,
        concerns: AmosWorkingMemory.active.where(entity: @entity, thought_type: 'concern').count
      }

      # Attention log
      @recent_attention = AmosAttentionLog.where(entity: @entity)
                                           .recent
                                           .limit(20)

      @attention_stats = {
        total_decisions: AmosAttentionLog.where(entity: @entity).where('created_at > ?', 7.days.ago).count,
        acted_on: AmosAttentionLog.where(entity: @entity).acted_on.where('created_at > ?', 7.days.ago).count,
        deferred: AmosAttentionLog.where(entity: @entity).deferred.where('created_at > ?', 7.days.ago).count,
        total_tokens: AmosAttentionLog.where(entity: @entity).where('created_at > ?', 7.days.ago).sum(:token_cost)
      }

      # Bounty grooming stats
      @grooming_stats = {
        total_open: Bounty.where(entity: @entity).open_bounties.count,
        demand_boosted: Bounty.where(entity: @entity).open_bounties.where('demand_multiplier > ?', 1.0).count,
        sprint_labeled: Bounty.where(entity: @entity).open_bounties.where.not(sprint_label: [nil, '']).count,
        stale: Bounty.where(entity: @entity).open_bounties.where('created_at < ?', 14.days.ago).count,
        last_groomed: Bounty.where(entity: @entity).maximum(:last_groomed_at)
      }

      # Signal queue (Stage 2)
      @pending_signals = AmosSignal.where(entity: @entity).pending.by_strength.limit(15)
      @signal_stats = {
        pending: AmosSignal.where(entity: @entity).pending.count,
        acted_on_24h: AmosSignal.where(entity: @entity).where(status: 'acted_on').where('acted_on_at > ?', 24.hours.ago).count,
        total_24h: AmosSignal.where(entity: @entity).where('created_at > ?', 24.hours.ago).count,
        strongest: AmosSignal.where(entity: @entity).pending.maximum(:strength)&.round(2),
        reactive_sessions_24h: AmosThinkingSession.where(entity: @entity, session_type: 'reactive').where('created_at > ?', 24.hours.ago).count
      }
    end

    def trigger_session
      mode = params[:mode] || 'autonomous'

      AmosThinkingTimeJob.perform_later(entity_id: current_entity.id, mode: mode)

      redirect_to admin_amos_mind_path, notice: "#{mode.titleize} thinking session queued for #{current_entity.name}"
    end

    def trigger_grooming
      BountyGroomingService.new(current_entity).groom!

      redirect_to admin_amos_mind_path, notice: "Bounty grooming completed"
    rescue => e
      redirect_to admin_amos_mind_path, alert: "Grooming failed: #{e.message}"
    end

    def thought_detail
      @thought = AmosWorkingMemory.find(params[:id])
      @related = AmosWorkingMemory.where(id: @thought.related_thought_ids) if @thought.related_thought_ids.any?
      @children = @thought.child_thoughts.by_salience
    end

    def resolve_thought
      thought = AmosWorkingMemory.find(params[:id])
      thought.resolve!(resolution: params[:resolution] || "Manually resolved by admin")

      redirect_to admin_amos_mind_path, notice: "Thought '#{thought.topic}' resolved"
    end
  end
end
