class CreateDefaultEntityAndMigrateData < ActiveRecord::Migration[8.0]
  def up
    # Create the default Nuvola Networks entity
    nuvola = Entity.create!(
      name: "Nuvola Networks",
      subdomain: "nuvola",
      slug: "nuvola",
      status: "active",
      settings: {
        timezone: "Eastern Time (US & Canada)",
        primary_color: "#4a90e2"
      }
    )

    # Get all users and associate them with the entity as owners
    User.find_each do |user|
      EntityUser.create!(entity: nuvola, user: user, role: 'owner')
    end

    # Migrate all existing data to the new entity

    # Contacts
    puts "Migrating contacts..."
    Contact.update_all(entity_id: nuvola.id)

    # Contact Groups
    puts "Migrating contact groups..."
    ContactGroup.update_all(entity_id: nuvola.id)

    # Email Templates
    puts "Migrating email templates..."
    EmailTemplate.update_all(entity_id: nuvola.id)

    # Campaigns
    puts "Migrating campaigns..."
    Campaign.update_all(entity_id: nuvola.id)

    # Social Posts
    puts "Migrating social posts..."
    SocialPost.update_all(entity_id: nuvola.id)

    # Social Media Accounts
    puts "Migrating social media accounts..."
    SocialMediaAccount.update_all(entity_id: nuvola.id)

    # Business Profiles
    puts "Migrating business profiles..."
    BusinessProfile.update_all(entity_id: nuvola.id)

    puts "Migration completed successfully."
  end

  def down
    # Create the default entity if it doesn't exist
    nuvola = Entity.find_by(subdomain: "nuvola")
    return unless nuvola

    # Remove association of data with the entity
    [ Contact, ContactGroup, EmailTemplate, Campaign, SocialPost, SocialMediaAccount, BusinessProfile ].each do |model|
      model.where(entity_id: nuvola.id).update_all(entity_id: nil)
    end

    # Delete entity users
    EntityUser.where(entity_id: nuvola.id).delete_all

    # Delete the entity
    nuvola.destroy
  end
end
