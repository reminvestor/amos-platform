class Campaign < ApplicationRecord
  include HasCustomFields
  
  belongs_to :user
  belongs_to :entity

  # Associations
  has_many :campaign_groups, dependent: :destroy
  has_many :contact_groups, through: :campaign_groups
  has_many :email_deliveries, dependent: :destroy
  belongs_to :email_template, optional: true

  # Drip campaign associations
  has_many :parent_drip_sequences, class_name: "DrippedCampaign", foreign_key: "original_campaign_id", dependent: :destroy
  has_many :follow_up_campaigns, through: :parent_drip_sequences

  has_many :child_drip_sequences, class_name: "DrippedCampaign", foreign_key: "follow_up_campaign_id", dependent: :destroy
  has_many :parent_campaigns, through: :child_drip_sequences, source: :original_campaign

  # Status options
  STATUSES = %w[draft scheduled in_progress completed paused stopped].freeze

  attribute :status, :string, default: "draft"

  # Validations
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :scheduled_at, presence: true, if: -> { status == "scheduled" }

  # Scopes
  scope :active, -> { where(status: [ "scheduled", "in_progress" ]) }
  scope :upcoming, -> { where(status: "scheduled").where("scheduled_at > ?", Time.current) }
  scope :completed, -> { where(status: "completed") }
  scope :recent, -> { order(updated_at: :desc) }
  scope :potentially_stalled, -> {
    where(status: "in_progress")
    .where("updated_at < ?", 15.minutes.ago)
    .joins(:email_deliveries)
    .where(email_deliveries: { status: "pending" })
    .distinct
  }

  # Methods
  def contacts
    Contact.joins(:contact_groups).where(contact_groups: { id: contact_group_ids }).distinct
  end

  def contact_count
    contacts.count
  end

  # Check if campaign appears to be stalled
  def stalled?
    return false unless status == "in_progress"
    return false if pending_deliveries_count == 0

    # Get the last time emails were actually sent
    last_sent = email_deliveries.where.not(sent_at: nil).maximum(:sent_at)

    # If no emails have been sent yet, check how long since campaign started
    if last_sent.nil?
      # Campaign just started - not stalled yet if it's been less than 30 minutes
      return Time.current - updated_at > 30.minutes
    end

    # Stalled if no emails sent for more than 15 minutes
    Time.current - last_sent > 15.minutes
  end

  # Get count of pending deliveries
  def pending_deliveries_count
    email_deliveries.where(status: "pending").count
  end

  # Get stall information for UI display
  def stall_info
    return nil unless stalled?

    last_sent = email_deliveries.where.not(sent_at: nil).maximum(:sent_at)
    last_activity = last_sent || updated_at

    {
      stalled_for: Time.current - last_activity,
      pending_count: pending_deliveries_count,
      last_activity: last_activity,
      last_sent: last_sent
    }
  end

  def sent_count
    # Use cached count if available
    return @cached_sent_count if defined?(@cached_sent_count)

    # Get actual count from our database first
    db_count = email_deliveries.where.not(sent_at: nil).count

    # If we have database records, use that count
    if db_count > 0
      return db_count
    end

    # Only fall back to Mailgun if we don't have db records
    if mailgun_stats.present? && mailgun_stats["delivered"].present?
      return mailgun_stats["delivered"]
    end

    # Default to 0 if nothing else works
    0
  end

  def sent_at
    # Use cached value if available
    return @cached_first_sent_at if defined?(@cached_first_sent_at)

    # Return the first sent date of any delivery in this campaign
    email_deliveries.where.not(sent_at: nil).order(sent_at: :asc).first&.sent_at
  end

  def open_rate
    # Use cached counts if available
    if defined?(@cached_opened_count) && defined?(@cached_sent_count)
      db_opened_count = @cached_opened_count
      db_clicked_count = @cached_clicked_count || 0
      db_sent_count = @cached_sent_count
    else
      # Count emails that were opened from our database
      db_opened_count = email_deliveries.where.not(opened_at: nil).count
      db_clicked_count = email_deliveries.where.not(clicked_at: nil).count
      db_sent_count = email_deliveries.where.not(sent_at: nil).count
    end

    # If we have actual opens in the database, prioritize that data
    if db_opened_count > 0 && db_sent_count > 0
      return (db_opened_count.to_f / db_sent_count * 100).round(2)
    end

    # If we have clicks but no opens in the database, use clicks as minimum opens
    if db_opened_count == 0 && db_clicked_count > 0 && db_sent_count > 0
      return (db_clicked_count.to_f / db_sent_count * 100).round(2)
    end

    # Only use Mailgun stats if we don't have good database data
    if mailgun_stats.present? && mailgun_stats["delivered"].present? && mailgun_stats["delivered"] > 0
      # If we have "opened" stats, use them
      if mailgun_stats["opened"].present? && mailgun_stats["opened"] > 0
        return (mailgun_stats["opened"].to_f / mailgun_stats["delivered"] * 100).round(2)
      # If no opens but we have clicks, clicks imply opens
      elsif mailgun_stats["clicked"].present? && mailgun_stats["clicked"] > 0
        # Use at least the click count for opens (logical minimum)
        return (mailgun_stats["clicked"].to_f / mailgun_stats["delivered"] * 100).round(2)
      end
    end

    # If nothing else worked, return 0
    0
  end

  def click_rate
    # Use cached counts if available
    if defined?(@cached_clicked_count) && defined?(@cached_sent_count)
      db_clicked_count = @cached_clicked_count
      db_sent_count = @cached_sent_count
    else
      # Count emails that were clicked from our database
      db_clicked_count = email_deliveries.where.not(clicked_at: nil).count
      db_sent_count = email_deliveries.where.not(sent_at: nil).count
    end

    # If we have actual clicks in the database, prioritize that data
    if db_clicked_count > 0 && db_sent_count > 0
      return (db_clicked_count.to_f / db_sent_count * 100).round(2)
    end

    # Only use Mailgun stats if we don't have good database data
    if mailgun_stats.present? && mailgun_stats["delivered"].present? && mailgun_stats["delivered"] > 0 &&
       mailgun_stats["clicked"].present?
      return (mailgun_stats["clicked"].to_f / mailgun_stats["delivered"] * 100).round(2)
    end

    # If nothing else worked, return 0
    0
  end

  def unsubscribe_rate
    # Get the contacts who received this campaign
    campaign_contacts = email_deliveries.where.not(sent_at: nil).joins(:contact).pluck("contacts.id")

    # If we have contacts who received this campaign, check their unsubscribe status
    if campaign_contacts.present?
      # Count how many of those contacts have opted out
      unsubscribed_count = Contact.where(id: campaign_contacts)
                                 .where(opted_out: true)
                                 .count

      return (unsubscribed_count.to_f / campaign_contacts.count * 100).round(2)
    end

    # Fall back to Mailgun stats if we don't have database records
    if mailgun_stats.present? && mailgun_stats["delivered"].present? &&
       mailgun_stats["delivered"] > 0 && mailgun_stats["complained"].present?
      return (mailgun_stats["complained"].to_f / mailgun_stats["delivered"] * 100).round(2)
    end

    # Default to 0 if nothing else works
    0
  end

  # Advanced analytics methods for AI-driven insights

  def bounce_rate
    # Use Mailgun stats if available
    if mailgun_stats.present? && mailgun_stats["delivered"].present? && mailgun_stats["failed"].present?
      total_sent = mailgun_stats["delivered"] + mailgun_stats["failed"]
      return 0 if total_sent.zero?

      (mailgun_stats["failed"].to_f / total_sent * 100).round(2)
    else
      # Fall back to internal tracking
      return 0 if sent_count.zero?
      (email_deliveries.where(status: "bounced").count.to_f / sent_count * 100).round(2)
    end
  end

  def engagement_score
    # Calculate a weighted engagement score (0-100)
    return 0 if sent_count.zero?

    # Weights for different engagement actions
    open_weight = 0.3
    click_weight = 0.7

    # Calculate scores
    open_score = open_rate * open_weight
    click_score = click_rate * click_weight

    # Sum up for final score (max 100)
    (open_score + click_score).round(2)
  end

  def time_to_open
    # Average time between sending and opening in minutes
    opened = email_deliveries.where.not(opened_at: nil, sent_at: nil)
    return nil if opened.empty?

    total_minutes = 0
    valid_count = 0

    opened.each do |delivery|
      if delivery.opened_at.present? && delivery.sent_at.present?
        total_minutes += ((delivery.opened_at - delivery.sent_at) / 60).round
        valid_count += 1
      end
    end

    return nil if valid_count.zero?
    (total_minutes.to_f / valid_count).round(2)
  end

  def most_active_hours
    # Returns array of [hour, count] pairs showing when emails were opened most
    opened = email_deliveries.where.not(opened_at: nil)
    return [] if opened.empty?

    hours = opened.group_by { |delivery| delivery.opened_at.hour }
                  .transform_values(&:count)
                  .sort_by { |_hour, count| -count }
                  .first(3)

    hours.map { |hour, count| [ hour, count ] }
  end

  def performance_percentile
    # Compare with other campaigns by the same user
    return nil if user.campaigns.completed.count < 3

    better_campaigns = user.campaigns.completed.where("id != ?", id).where("(SELECT COUNT(*) FROM email_deliveries WHERE campaign_id = campaigns.id AND opened_at IS NOT NULL) / (SELECT COUNT(*) FROM email_deliveries WHERE campaign_id = campaigns.id AND sent_at IS NOT NULL) > ?", open_rate / 100.0).count

    total_other_campaigns = user.campaigns.completed.where("id != ?", id).count

    return nil if total_other_campaigns.zero?

    percentile = 100 - (better_campaigns.to_f / total_other_campaigns * 100).round
    [ 0, [ 100, percentile ].min ].max  # Ensure between 0 and 100
  end

  def device_breakdown
    # Mock data for now, in a real implementation this would come from tracking data
    {
      desktop: 45,
      mobile: 42,
      tablet: 13
    }
  end

  def sync_mailgun_stats
    # No-op now, Mailgun is deprecated
    # Keeping method signature for compatibility
    false
  end

  def last_synced_at
    if mailgun_stats.present? && mailgun_stats["last_synced_at"].present?
      # Convert string to DateTime if it's not already a DateTime object
      last_synced = mailgun_stats["last_synced_at"]
      last_synced.is_a?(String) ? DateTime.parse(last_synced) : last_synced
    else
      nil
    end
  end

  # Methods for drip campaigns
  def create_drip_follow_up(delay_days: 3, condition: "not_opened", subject_prefix: "[Reminder] ")
    # Make sure this campaign is valid for creating a follow-up
    unless [ "in_progress", "completed" ].include?(status)
      errors.add(:base, "Campaign must be in progress or completed to create a follow-up")
      return nil
    end

    # Make sure there's an email template
    unless email_template.present?
      errors.add(:base, "Campaign must have an email template to create a follow-up")
      return nil
    end

    # Create a duplicate of this campaign as a template for follow-ups
    follow_up_template = self.dup
    follow_up_template.name = "Template: Follow-up for #{name}"

    # Clone and modify the email template
    original_template = email_template
    new_template = original_template.dup
    new_template.name = "Follow-up for #{original_template.name}"
    new_template.subject = "#{subject_prefix}#{original_template.subject}"

    # Save the new template
    if new_template.save
      # Associate with the new campaign
      follow_up_template.email_template_id = new_template.id

      # Insert a follow-up note in the email body
      if new_template.body.present?
        followup_note = "<p><em>This is a follow-up to our previous email that you may have missed.</em></p>"

        # Insert after the first paragraph or at beginning
        if new_template.body.include?("</p>")
          # Insert after the first paragraph
          new_template.body = new_template.body.sub("</p>", "</p>\n#{followup_note}")
        else
          # Insert at the beginning
          new_template.body = "#{followup_note}\n#{new_template.body}"
        end

        # Save the modified body
        new_template.save
      end
    end

    # Set to draft status
    follow_up_template.status = "draft"

    # Save the template
    if follow_up_template.save
      # Determine the next position in the sequence
      next_position = parent_drip_sequences.maximum(:sequence_position).to_i + 1

      # Create the drip campaign relationship
      drip_campaign = DrippedCampaign.create!(
        original_campaign_id: self.id,
        follow_up_campaign_id: follow_up_template.id,
        delay_days: delay_days,
        condition: condition,
        sequence_position: next_position,
        scheduled_at: Time.current + delay_days.days
      )

      drip_campaign
    else
      nil
    end
  end

  def create_follow_up_now!
    # Find the next drip campaign in the sequence
    next_drip = parent_drip_sequences.order(sequence_position: :asc).first

    # Execute it if found
    if next_drip.present?
      next_drip.create_next_follow_up!
    else
      nil
    end
  end

  def has_follow_ups?
    parent_drip_sequences.exists?
  end

  def is_follow_up?
    child_drip_sequences.exists?
  end

  def next_scheduled_follow_up
    parent_drip_sequences.where("scheduled_at > ?", Time.current).order(scheduled_at: :asc).first
  end
end
