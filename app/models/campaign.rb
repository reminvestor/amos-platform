class Campaign < ApplicationRecord
  belongs_to :user
  
  # Associations
  has_many :campaign_groups, dependent: :destroy
  has_many :contact_groups, through: :campaign_groups
  has_many :email_deliveries, dependent: :destroy
  belongs_to :email_template, optional: true
  
  # Status options
  STATUSES = %w[draft scheduled in_progress completed paused stopped].freeze
  
  # Validations
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :scheduled_at, presence: true, if: -> { status == 'scheduled' }
  
  # Scopes
  scope :active, -> { where(status: ['scheduled', 'in_progress']) }
  scope :upcoming, -> { where(status: 'scheduled').where('scheduled_at > ?', Time.current) }
  scope :completed, -> { where(status: 'completed') }
  
  # Methods
  def contacts
    Contact.joins(:contact_groups).where(contact_groups: { id: contact_group_ids }).distinct
  end
  
  def contact_count
    contacts.count
  end
  
  def sent_count
    if mailgun_stats.present? && mailgun_stats["delivered"].present?
      mailgun_stats["delivered"]
    else
      email_deliveries.where.not(sent_at: nil).count
    end
  end
  
  def sent_at
    # Return the first sent date of any delivery in this campaign
    email_deliveries.where.not(sent_at: nil).order(sent_at: :asc).first&.sent_at
  end
  
  def open_rate
    # Count emails that were opened from our database
    db_opened_count = email_deliveries.where.not(opened_at: nil).count
    db_clicked_count = email_deliveries.where.not(clicked_at: nil).count
    db_sent_count = email_deliveries.where.not(sent_at: nil).count
    
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
    return 0
  end
  
  def click_rate
    # Count emails that were clicked from our database
    db_clicked_count = email_deliveries.where.not(clicked_at: nil).count
    db_sent_count = email_deliveries.where.not(sent_at: nil).count
    
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
    return 0
  end
  
  def unsubscribe_rate
    # Use Mailgun stats if available
    if mailgun_stats.present? && mailgun_stats["delivered"].present? && mailgun_stats["delivered"] > 0 && mailgun_stats["complained"].present?
      (mailgun_stats["complained"].to_f / mailgun_stats["delivered"] * 100).round(2)
    else
      # Fall back to our internal tracking
      return 0 if sent_count.zero?
      
      # Get the contacts who received this campaign
      campaign_contacts = email_deliveries.where.not(sent_at: nil).joins(:contact).pluck('contacts.id')
      return 0 if campaign_contacts.empty?
      
      # Count how many of them have opted out after the campaign started
      # (only count those who unsubscribed after receiving this campaign)
      first_send_time = sent_at
      unsubscribed_count = Contact.where(id: campaign_contacts)
                                 .where(opted_out: true)
                                 .where('opted_out_at >= ?', first_send_time)
                                 .count
      
      (unsubscribed_count.to_f / campaign_contacts.count * 100).round(2)
    end
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
      (email_deliveries.where(status: 'bounced').count.to_f / sent_count * 100).round(2)
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
    
    hours.map { |hour, count| [hour, count] }
  end
  
  def performance_percentile
    # Compare with other campaigns by the same user
    return nil if user.campaigns.completed.count < 3
    
    better_campaigns = user.campaigns.completed.where('id != ?', id).where('(SELECT COUNT(*) FROM email_deliveries WHERE campaign_id = campaigns.id AND opened_at IS NOT NULL) / (SELECT COUNT(*) FROM email_deliveries WHERE campaign_id = campaigns.id AND sent_at IS NOT NULL) > ?', open_rate / 100.0).count
    
    total_other_campaigns = user.campaigns.completed.where('id != ?', id).count
    
    return nil if total_other_campaigns.zero?
    
    percentile = 100 - (better_campaigns.to_f / total_other_campaigns * 100).round
    [0, [100, percentile].min].max  # Ensure between 0 and 100
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
    # Don't try to sync if we don't have a tag
    return false unless mailgun_tag.present?
    
    # Queue the sync job
    SyncMailgunStatsJob.perform_later(id)
    true
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
end
