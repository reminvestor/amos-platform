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
  store_accessor :submission_data, :email, :first_name, :last_name, :phone, :company, :message
  store_accessor :metadata, :utm_source, :utm_medium, :utm_campaign, :utm_content, :utm_term

  # Callbacks
  before_validation :set_submitted_at, if: -> { submitted_at.blank? }
  after_create :process_submission_async

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
    [ first_name, last_name ].compact.join(" ").presence || "Unknown"
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
        update_attrs[:first_name] = first_name if first_name.present? && existing_contact.first_name.blank?
        update_attrs[:last_name] = last_name if last_name.present? && existing_contact.last_name.blank?

        # Store landing page engagement in metadata
        existing_metadata = existing_contact.metadata || {}
        existing_metadata["last_landing_page_engagement"] = submitted_at.to_s
        existing_metadata["landing_page_engagements"] ||= []
        existing_metadata["landing_page_engagements"] << {
          landing_page_id: landing_page_id,
          landing_page_title: landing_page.title,
          form_type: form_type,
          submitted_at: submitted_at.to_s,
          phone: phone,
          company: company,
          message: message
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
        # Use email prefix as fallback if not provided
        contact_first_name = first_name.presence || email.split("@").first.split(/[._]/).first&.capitalize || "Unknown"
        contact_last_name = last_name.presence || email.split("@").first.split(/[._]/).last&.capitalize || "Contact"

        # Build comprehensive metadata from submission
        contact_metadata = {
          source: "landing_page",
          landing_page_id: landing_page_id,
          landing_page_title: landing_page.title,
          landing_page_slug: landing_page.slug,
          form_type: form_type,
          submitted_at: submitted_at.to_s,
          utm_params: utm_params,
          original_first_name: first_name,
          original_last_name: last_name,
          phone: phone,
          company: company,
          message: message,
          referrer: referrer,
          source_ip: source_ip
        }.compact

        # Include any extra submission fields not covered above
        extra_fields = submission_data.except("email", "first_name", "last_name", "firstName", "lastName", "phone", "company", "message")
        contact_metadata[:extra_fields] = extra_fields if extra_fields.present?

        new_contact = Contact.create!(
          email: email,
          first_name: contact_first_name,
          last_name: contact_last_name,
          status: "new",
          tags: "landing_page,#{form_type}",
          user: landing_page.user,
          entity: landing_page.entity,
          metadata: contact_metadata
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

  def trigger_follow_up_actions
    # Send notification emails, webhooks, etc.
    case form_type
    when "newsletter"
      # Add to newsletter list
    when "demo_request"
      # Notify sales team
    when "consultation_booking"
      # Send calendar link
    end
  end
end
