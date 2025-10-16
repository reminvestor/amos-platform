class DrippedCampaign < ApplicationRecord
  belongs_to :original_campaign, class_name: "Campaign"
  belongs_to :follow_up_campaign, class_name: "Campaign"

  validates :delay_days, presence: true, numericality: { greater_than_or_equal_to: 1 }
  validates :sequence_position, presence: true, numericality: { greater_than_or_equal_to: 1 }
  validates :sequence_position, uniqueness: { scope: :original_campaign_id }

  # Valid conditions for sending follow-up emails
  VALID_CONDITIONS = [ "not_opened", "not_clicked", "opened", "clicked", "always" ]

  validates :condition, inclusion: { in: VALID_CONDITIONS, message: "must be one of: #{VALID_CONDITIONS.join(', ')}" }, allow_blank: true

  before_validation :set_defaults

  # Create the next follow-up in a sequence
  def create_next_follow_up!
    return nil unless active?

    # Apply the condition to filter contacts
    filtered_contacts = case condition
    when "not_opened"
      # Get contacts who haven't opened the original email
      deliveries = original_campaign.email_deliveries.where(opened_at: nil)
      deliveries.pluck(:contact_id).uniq
    when "not_clicked"
      # Get contacts who haven't clicked the original email
      deliveries = original_campaign.email_deliveries.where(clicked_at: nil)
      deliveries.pluck(:contact_id).uniq
    when "opened"
      # Get contacts who have opened the original email
      deliveries = original_campaign.email_deliveries.where.not(opened_at: nil)
      deliveries.pluck(:contact_id).uniq
    when "clicked"
      # Get contacts who have clicked the original email
      deliveries = original_campaign.email_deliveries.where.not(clicked_at: nil)
      deliveries.pluck(:contact_id).uniq
    else
      # Default to all contacts in the original campaign
      original_campaign.email_deliveries.pluck(:contact_id).uniq
    end

    # Skip if no contacts match the condition
    return nil if filtered_contacts.empty?

    # Create a new contact group for the follow-up
    new_group = ContactGroup.create!(
      name: "Drip follow-up #{sequence_position} for campaign #{original_campaign.id}",
      entity_id: original_campaign.entity_id,
      user_id: original_campaign.user_id
    )

    # Add contacts to the new group
    associations = filtered_contacts.map do |contact_id|
      {
        contact_id: contact_id,
        contact_group_id: new_group.id,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # Skip if no associations to create
    return nil if associations.empty?

    # Bulk insert the associations
    ContactGroupsContact.insert_all(associations)

    # Create a new campaign based on the follow-up campaign template
    new_campaign = follow_up_campaign.dup
    new_campaign.status = "draft"  # Set as draft initially
    new_campaign.entity_id = original_campaign.entity_id

    # Save the campaign first so we can establish associations
    new_campaign.save!

    # Create association with the new contact group
    CampaignGroup.create!(
      campaign_id: new_campaign.id,
      contact_group_id: new_group.id
    )

    # Return the new campaign
    new_campaign
  end

  private

  def set_defaults
    self.condition ||= "not_opened"
    self.active = true if active.nil?
    self.delay_days ||= 3
    self.sequence_position ||= 1
  end
end
