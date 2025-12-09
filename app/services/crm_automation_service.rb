# frozen_string_literal: true

# CRM Automation Service
# Handles automated CRM tasks like lead scoring, stale alerts, and follow-up reminders
class CrmAutomationService
  # Lead scoring rules - points for various activities
  LEAD_SCORING_RULES = {
    # Engagement actions
    landing_page_submission: 10,
    email_opened: 2,
    email_clicked: 5,
    email_replied: 15,
    form_submission: 10,
    
    # Sales interactions
    call_connected: 10,
    call_voicemail: 3,
    meeting_scheduled: 20,
    meeting_completed: 25,
    proposal_sent: 30,
    
    # Lifecycle progression
    promoted_to_lead: 5,
    promoted_to_mql: 10,
    promoted_to_sql: 15,
    opportunity_created: 20,
    
    # Negative signals
    email_bounced: -10,
    email_unsubscribed: -25,
    marked_spam: -50,
    inactive_30_days: -5,
    inactive_60_days: -10,
    inactive_90_days: -20
  }.freeze

  # Stale thresholds in days
  STALE_THRESHOLDS = {
    lead: 7,
    qualified: 14,
    proposal: 7,
    negotiation: 5
  }.freeze

  class << self
    # Process all automations for an entity
    def process_entity(entity)
      Rails.logger.info "[CRM Automation] Processing entity #{entity.id}: #{entity.name}"
      
      results = {
        lead_scores_updated: 0,
        stale_opportunities_flagged: 0,
        follow_up_reminders_created: 0,
        lifecycle_promotions: 0
      }
      
      # Update lead scores based on recent activity
      results[:lead_scores_updated] = update_lead_scores(entity)
      
      # Flag stale opportunities
      results[:stale_opportunities_flagged] = flag_stale_opportunities(entity)
      
      # Create follow-up reminders for overdue items
      results[:follow_up_reminders_created] = create_follow_up_reminders(entity)
      
      # Auto-promote contacts based on engagement
      results[:lifecycle_promotions] = auto_promote_contacts(entity)
      
      Rails.logger.info "[CRM Automation] Results for entity #{entity.id}: #{results}"
      results
    end

    # Update lead scores based on recent activity
    def update_lead_scores(entity)
      updated_count = 0
      
      # Get contacts with recent activity
      entity.contacts.where("last_activity_at > ?", 24.hours.ago).find_each do |contact|
        score_delta = calculate_score_delta(contact)
        
        if score_delta != 0
          contact.adjust_lead_score!(score_delta, reason: "automated_daily_update")
          updated_count += 1
        end
      end
      
      # Apply decay for inactive contacts
      entity.contacts
            .where("last_activity_at < ? OR last_activity_at IS NULL", 30.days.ago)
            .where("lead_score > 0")
            .find_each do |contact|
        days_inactive = contact.last_activity_at ? 
                        ((Time.current - contact.last_activity_at) / 1.day).to_i : 
                        90
        
        decay = if days_inactive >= 90
                  LEAD_SCORING_RULES[:inactive_90_days]
                elsif days_inactive >= 60
                  LEAD_SCORING_RULES[:inactive_60_days]
                elsif days_inactive >= 30
                  LEAD_SCORING_RULES[:inactive_30_days]
                else
                  0
                end
        
        if decay != 0
          contact.adjust_lead_score!(decay, reason: "inactivity_decay")
          updated_count += 1
        end
      end
      
      updated_count
    end

    # Flag stale opportunities that need attention
    def flag_stale_opportunities(entity)
      flagged_count = 0
      
      entity.opportunities.open.find_each do |opportunity|
        threshold = STALE_THRESHOLDS[opportunity.stage.to_sym] || 14
        
        if opportunity.days_in_stage >= threshold && !opportunity.metadata&.dig("stale_notified")
          # Mark as notified to avoid duplicate alerts
          opportunity.update!(
            metadata: (opportunity.metadata || {}).merge(
              "stale_notified" => true,
              "stale_notified_at" => Time.current.iso8601
            )
          )
          
          # Create an activity to alert the team
          Activity.create!(
            entity: entity,
            opportunity: opportunity,
            contact: opportunity.contact,
            activity_type: "task",
            subject: "⚠️ Stale Opportunity Alert: #{opportunity.name}",
            description: "This opportunity has been in the '#{opportunity.stage_label}' stage for #{opportunity.days_in_stage} days. Please review and take action.",
            status: "pending",
            priority: "high",
            due_at: 1.day.from_now,
            assigned_user_id: opportunity.user_id,
            assigned_agent_id: opportunity.assigned_agent_id
          )
          
          flagged_count += 1
        end
      end
      
      flagged_count
    end

    # Create follow-up reminders for contacts without recent activity
    def create_follow_up_reminders(entity)
      created_count = 0
      
      # Find contacts that need follow-up
      entity.contacts
            .where(lifecycle_stage: %w[lead mql sql])
            .where("next_follow_up_at IS NULL OR next_follow_up_at < ?", Time.current)
            .where("last_contacted_at IS NULL OR last_contacted_at < ?", 7.days.ago)
            .limit(50) # Process in batches
            .find_each do |contact|
        
        # Check if there's already a pending follow-up task
        existing_task = contact.activities
                               .where(activity_type: "task", status: "pending")
                               .where("subject LIKE ?", "%follow-up%")
                               .exists?
        
        next if existing_task
        
        # Create follow-up task
        Activity.create!(
          entity: entity,
          contact: contact,
          activity_type: "task",
          subject: "Follow up with #{contact.full_name}",
          description: "This contact hasn't been contacted in over 7 days. Consider reaching out to maintain engagement.",
          status: "pending",
          priority: "normal",
          due_at: 1.business_day.from_now,
          assigned_user_id: contact.assigned_user_id,
          assigned_agent_id: contact.assigned_agent_id
        )
        
        # Update next follow-up date
        contact.update!(next_follow_up_at: 1.business_day.from_now)
        
        created_count += 1
      end
      
      created_count
    end

    # Auto-promote contacts based on engagement thresholds
    def auto_promote_contacts(entity)
      promoted_count = 0
      
      # Define promotion thresholds
      promotions = {
        subscriber: { min_score: 25, target: "lead" },
        lead: { min_score: 50, target: "mql" },
        mql: { min_score: 75, target: "sql" }
      }
      
      promotions.each do |current_stage, config|
        entity.contacts
              .where(lifecycle_stage: current_stage.to_s)
              .where("lead_score >= ?", config[:min_score])
              .find_each do |contact|
          
          contact.promote_lifecycle!(config[:target])
          
          # Log the promotion
          Activity.create!(
            entity: entity,
            contact: contact,
            activity_type: "note",
            subject: "🎯 Auto-promoted to #{config[:target].upcase}",
            description: "Contact automatically promoted based on lead score of #{contact.lead_score}.",
            status: "completed",
            completed_at: Time.current,
            metadata: { automation: "lifecycle_promotion", previous_stage: current_stage.to_s }
          )
          
          promoted_count += 1
        end
      end
      
      promoted_count
    end

    # Calculate score delta for a contact based on recent activities
    def calculate_score_delta(contact)
      delta = 0
      recent_activities = contact.activities.where("created_at > ?", 24.hours.ago)
      
      recent_activities.find_each do |activity|
        case activity.activity_type
        when "call"
          delta += activity.outcome == "connected" ? 
                   LEAD_SCORING_RULES[:call_connected] : 
                   LEAD_SCORING_RULES[:call_voicemail]
        when "meeting"
          delta += activity.status == "completed" ? 
                   LEAD_SCORING_RULES[:meeting_completed] : 
                   LEAD_SCORING_RULES[:meeting_scheduled]
        when "email"
          # Check email engagement from metadata
          if activity.metadata&.dig("clicked")
            delta += LEAD_SCORING_RULES[:email_clicked]
          elsif activity.metadata&.dig("opened")
            delta += LEAD_SCORING_RULES[:email_opened]
          end
        end
      end
      
      # Check for landing page submissions
      recent_submissions = contact.landing_page_submissions
                                  .where("created_at > ?", 24.hours.ago)
                                  .count
      delta += recent_submissions * LEAD_SCORING_RULES[:landing_page_submission]
      
      delta
    end

    # Score a specific action for a contact
    def score_action(contact, action, metadata = {})
      return unless LEAD_SCORING_RULES.key?(action)
      
      score = LEAD_SCORING_RULES[action]
      contact.adjust_lead_score!(score, reason: action.to_s, metadata: metadata)
      
      # Check for auto-promotion after scoring
      check_auto_promotion(contact)
    end

    # Check if contact should be auto-promoted
    def check_auto_promotion(contact)
      promotions = {
        "subscriber" => { min_score: 25, target: "lead" },
        "lead" => { min_score: 50, target: "mql" },
        "mql" => { min_score: 75, target: "sql" }
      }
      
      config = promotions[contact.lifecycle_stage]
      return unless config && contact.lead_score >= config[:min_score]
      
      contact.promote_lifecycle!(config[:target])
    end
  end
end
