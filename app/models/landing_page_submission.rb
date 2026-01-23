class LandingPageSubmission < ApplicationRecord
  belongs_to :landing_page
  belongs_to :contact, optional: true

  # Status enum
  enum :status, {
    pending: "pending",
    processed: "processed",
    failed: "failed",
    spam: "spam",
    duplicate: "duplicate"
  }

  # Form type enum
  FORM_TYPES = %w[
    contact newsletter lead_magnet demo_request quote_request
    consultation_booking event_registration download general
  ].freeze

  # Validations
  validates :form_type, presence: true, inclusion: { in: FORM_TYPES }
  validates :submitted_at, presence: true
  validates :submission_data, presence: true
  validate :validate_submission_data_structure

  # Scopes
  scope :recent, -> { order(submitted_at: :desc) }
  scope :by_form_type, ->(type) { where(form_type: type) }
  scope :by_landing_page, ->(page_id) { where(landing_page_id: page_id) }
  scope :unprocessed, -> { where(status: "pending") }
  scope :this_month, -> { where(submitted_at: 1.month.ago..Time.current) }
  scope :this_week, -> { where(submitted_at: 1.week.ago..Time.current) }
  scope :today, -> { where(submitted_at: Date.current.beginning_of_day..Time.current) }

  # Store accessors for JSONB fields
  # Note: forms may submit full_name, firstName, lastName, or first_name/last_name
  store_accessor :submission_data, :email, :first_name, :last_name, :phone, :company, :message
  store_accessor :metadata, :utm_source, :utm_medium, :utm_campaign, :utm_content, :utm_term
  
  # Parse names from various form field formats
  def parsed_first_name
    # Check explicit first_name fields first
    return first_name if first_name.present?
    return submission_data["firstName"] if submission_data&.dig("firstName").present?
    
    # Parse from full_name if available
    full = submission_data&.dig("full_name") || submission_data&.dig("fullName") || submission_data&.dig("name")
    if full.present?
      parts = full.to_s.strip.split(/\s+/, 2)
      return parts.first
    end
    
    nil
  end
  
  def parsed_last_name
    # Check explicit last_name fields first
    return last_name if last_name.present?
    return submission_data["lastName"] if submission_data&.dig("lastName").present?
    
    # Parse from full_name if available
    full = submission_data&.dig("full_name") || submission_data&.dig("fullName") || submission_data&.dig("name")
    if full.present?
      parts = full.to_s.strip.split(/\s+/, 2)
      return parts.second || parts.first  # Use first name as last if only one word
    end
    
    nil
  end

  # Callbacks
  before_validation :set_submitted_at, if: -> { submitted_at.blank? }
  after_create :process_submission_async
  after_create :fire_workflow_triggers

  # Class methods
  def self.conversion_rate_for_page(landing_page_id, period = 30.days)
    submissions = where(landing_page_id: landing_page_id)
                    .where(submitted_at: period.ago..Time.current)

    total_submissions = submissions.count
    processed_submissions = submissions.where(status: [ "processed", "duplicate" ]).count

    return 0.0 if total_submissions.zero?

    (processed_submissions.to_f / total_submissions * 100).round(2)
  end

  def self.daily_submissions(days = 30)
    where(submitted_at: days.days.ago..Time.current)
      .group("DATE(submitted_at)")
      .count
  end

  def self.by_form_type_stats
    group(:form_type).count
  end

  # Instance methods
  def full_name
    [ parsed_first_name, parsed_last_name ].compact.join(" ").presence || "Unknown"
  end

  def contact_info
    {
      name: full_name,
      email: email,
      phone: phone,
      company: company
    }.compact
  end

  def utm_params
    {
      source: utm_source,
      medium: utm_medium,
      campaign: utm_campaign,
      content: utm_content,
      term: utm_term
    }.compact
  end

  def mark_as_processed!
    update!(
      status: "processed",
      processed_at: Time.current
    )
  end

  def mark_as_failed!(reason = nil)
    update!(
      status: "failed",
      processed_at: Time.current,
      metadata: metadata.merge(failure_reason: reason).compact
    )
  end

  def mark_as_spam!
    update!(
      status: "spam",
      processed_at: Time.current
    )
  end

  def process_and_create_contact!
    return if contact.present? || email.blank?

    begin
      # Find existing contact by email and entity (Contact doesn't have landing_page_id column)
      existing_contact = Contact.find_by(
        email: email,
        entity: landing_page.entity
      ) || Contact.find_by(
        email: email,
        user: landing_page.user
      )

      if existing_contact
        # Update existing contact with new info if provided
        update_attrs = {}
        update_attrs[:first_name] = parsed_first_name if parsed_first_name.present? && existing_contact.first_name.blank?
        update_attrs[:last_name] = parsed_last_name if parsed_last_name.present? && existing_contact.last_name.blank?
        
        # Set lead_source if not already set
        update_attrs[:lead_source] = "landing_page" if existing_contact.lead_source.blank?
        
        # Update last activity time
        update_attrs[:last_activity_at] = Time.current

        # Store landing page engagement in metadata
        existing_metadata = existing_contact.metadata || {}
        existing_metadata["last_landing_page_engagement"] = submitted_at.to_s
        existing_metadata["landing_page_engagements"] ||= []
        existing_metadata["landing_page_engagements"] << {
          landing_page_id: landing_page_id,
          landing_page_title: landing_page.title,
          landing_page_slug: landing_page.slug,
          form_type: form_type,
          submitted_at: submitted_at.to_s,
          phone: phone,
          company: company,
          message: message,
          referrer: referrer
        }.compact
        
        # Update phone/company if we have it and contact doesn't
        existing_metadata["phone"] ||= phone if phone.present?
        existing_metadata["company"] ||= company if company.present?
        
        update_attrs[:metadata] = existing_metadata
        
        # Add landing_page tag if not present
        existing_tags = (existing_contact.tags || "").split(",").map(&:strip)
        unless existing_tags.include?("landing_page")
          existing_tags << "landing_page"
          update_attrs[:tags] = existing_tags.join(",")
        end

        existing_contact.update!(update_attrs) if update_attrs.present?
        self.contact = existing_contact
        self.status = "duplicate"
      else
        # Create new contact - first_name and last_name are required
        # Use parsed names (handles full_name, firstName, lastName, etc.)
        # Fall back to email prefix if not provided
        contact_first_name = parsed_first_name.presence || email.split("@").first.split(/[._]/).first&.capitalize || "Unknown"
        contact_last_name = parsed_last_name.presence || email.split("@").first.split(/[._]/).last&.capitalize || "Contact"

        # Build comprehensive metadata from submission
        contact_metadata = {
          source: "landing_page",
          landing_page_id: landing_page_id,
          landing_page_title: landing_page.title,
          landing_page_slug: landing_page.slug,
          form_type: form_type,
          submitted_at: submitted_at.to_s,
          utm_params: utm_params,
          original_first_name: parsed_first_name,
          original_last_name: parsed_last_name,
          original_full_name: submission_data&.dig("full_name") || submission_data&.dig("fullName") || submission_data&.dig("name"),
          phone: phone,
          company: company,
          message: message,
          referrer: referrer,
          source_ip: source_ip
        }.compact

        # Include any extra submission fields not covered above
        extra_fields = submission_data.except("email", "first_name", "last_name", "firstName", "lastName", "full_name", "fullName", "name", "phone", "company", "message")
        contact_metadata[:extra_fields] = extra_fields if extra_fields.present?

        new_contact = Contact.create!(
          email: email,
          first_name: contact_first_name,
          last_name: contact_last_name,
          status: "active",  # Use 'active' as the default status for new leads
          lead_source: "landing_page",  # Track where this lead came from
          tags: "landing_page,#{form_type}",
          user: landing_page.user,
          entity: landing_page.entity,
          metadata: contact_metadata,
          # Set lifecycle stage for new leads
          lifecycle_stage: "lead",
          lead: true,
          last_activity_at: Time.current
        )
        self.contact = new_contact
        self.status = "processed"
      end

      self.processed_at = Time.current
      save!

      # Trigger any follow-up actions (email notifications, etc.)
      trigger_follow_up_actions

    rescue => e
      mark_as_failed!(e.message)
      Rails.logger.error "Failed to process submission #{id}: #{e.message}"
      raise e
    end
  end

  def to_contact_params
    {
      email: email,
      first_name: first_name,
      last_name: last_name,
      phone: phone,
      company: company,
      metadata: {
        source: "landing_page_submission",
        submission_id: id,
        form_type: form_type,
        landing_page_id: landing_page_id,
        submitted_at: submitted_at,
        utm_params: utm_params
      }.merge(submission_data.except("email", "first_name", "last_name", "phone", "company"))
    }
  end

  private

  def set_submitted_at
    self.submitted_at = Time.current
  end

  def validate_submission_data_structure
    return if submission_data.blank?

    # Ensure email is present for most form types
    unless %w[general].include?(form_type)
      if submission_data["email"].blank?
        errors.add(:submission_data, "must include email address")
      end
    end

    # Validate email format if present
    if submission_data["email"].present?
      unless submission_data["email"].match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
        errors.add(:submission_data, "email format is invalid")
      end
    end
  end

  def process_submission_async
    # Process in background to avoid blocking the form submission
    ProcessLandingPageSubmissionJob.perform_later(id)
  end

  def fire_workflow_triggers
    # Fire any workflow triggers attached to this landing page
    return unless landing_page.respond_to?(:fire_workflows!)

    landing_page.fire_workflows!(:form, {
      submission: submission_data,
      form_data: submission_data,
      form_type: form_type,
      submitter: {
        email: email,
        name: full_name,
        phone: phone,
        company: company
      },
      landing_page_id: landing_page_id,
      landing_page_title: landing_page.title,
      submission_id: id,
      submitted_at: submitted_at&.iso8601,
      utm_params: utm_params,
      user: landing_page.user
    })
  rescue => e
    Rails.logger.error "[LandingPageSubmission] Failed to fire workflows: #{e.message}"
    # Don't fail the submission if workflow firing fails
  end

  def trigger_follow_up_actions
    return unless contact.present?

    # Create activity for the form submission
    create_submission_activity

    # Update lead score
    score_lead_for_submission

    # Create follow-up tasks based on form type
    case form_type
    when "demo_request"
      create_demo_request_task
    when "consultation_booking"
      create_consultation_task
    when "quote_request"
      create_quote_request_task
    when "lead_magnet", "download"
      # Just score, no immediate follow-up needed
    when "newsletter"
      # Add to newsletter engagement
    end
  end

  def create_submission_activity
    return unless contact.present? && landing_page.entity.present?

    Activity.create!(
      entity: landing_page.entity,
      contact: contact,
      user: landing_page.user,
      activity_type: "note",
      subject: "📝 Form Submission: #{landing_page.title}",
      description: build_activity_description,
      status: "completed",
      completed_at: submitted_at,
      metadata: {
        source: "landing_page_submission",
        submission_id: id,
        form_type: form_type,
        landing_page_id: landing_page_id,
        landing_page_slug: landing_page.slug,
        utm_params: utm_params
      }
    )

    # Update contact's last activity
    contact.update!(last_activity_at: submitted_at)
  end

  def score_lead_for_submission
    return unless contact.present?

    # Score based on form type (higher intent = higher score)
    score_map = {
      "demo_request" => 25,
      "consultation_booking" => 25,
      "quote_request" => 20,
      "lead_magnet" => 15,
      "download" => 15,
      "contact" => 10,
      "newsletter" => 5,
      "event_registration" => 10,
      "general" => 5
    }

    score = score_map[form_type] || 10

    # Score the action using the automation service
    if defined?(CrmAutomationService)
      CrmAutomationService.score_action(contact, :landing_page_submission, {
        form_type: form_type,
        landing_page_id: landing_page_id
      })
    else
      # Fallback if service not available
      contact.adjust_lead_score!(score, reason: "landing_page_submission")
    end
  end

  def create_demo_request_task
    Activity.create!(
      entity: landing_page.entity,
      contact: contact,
      user: landing_page.user,
      activity_type: "task",
      subject: "🎯 Demo Request: #{contact.full_name}",
      description: "#{contact.full_name} requested a demo via #{landing_page.title}. #{message.present? ? "Message: #{message}" : ""}",
      status: "pending",
      priority: "high",
      due_at: 1.business_day.from_now,
      assigned_user_id: landing_page.user_id
    )

    contact.update!(next_follow_up_at: 1.business_day.from_now)
  end

  def create_consultation_task
    Activity.create!(
      entity: landing_page.entity,
      contact: contact,
      user: landing_page.user,
      activity_type: "task",
      subject: "📅 Consultation Request: #{contact.full_name}",
      description: "#{contact.full_name} requested a consultation via #{landing_page.title}.",
      status: "pending",
      priority: "high",
      due_at: 1.business_day.from_now,
      assigned_user_id: landing_page.user_id
    )

    contact.update!(next_follow_up_at: 1.business_day.from_now)
  end

  def create_quote_request_task
    Activity.create!(
      entity: landing_page.entity,
      contact: contact,
      user: landing_page.user,
      activity_type: "task",
      subject: "💰 Quote Request: #{contact.full_name}",
      description: "#{contact.full_name} requested a quote via #{landing_page.title}. #{message.present? ? "Details: #{message}" : ""}",
      status: "pending",
      priority: "high",
      due_at: 1.business_day.from_now,
      assigned_user_id: landing_page.user_id
    )

    contact.update!(next_follow_up_at: 1.business_day.from_now)
  end

  def build_activity_description
    parts = ["Submitted #{form_type.titleize} form on landing page: #{landing_page.title}"]
    parts << "Company: #{company}" if company.present?
    parts << "Phone: #{phone}" if phone.present?
    parts << "Message: #{message}" if message.present?

    # Add UTM info if present
    if utm_params.any?
      utm_info = utm_params.map { |k, v| "#{k}: #{v}" }.join(", ")
      parts << "Campaign: #{utm_info}"
    end

    parts.join("\n")
  end
end
