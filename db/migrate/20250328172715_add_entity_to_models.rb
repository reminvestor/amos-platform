class AddEntityToModels < ActiveRecord::Migration[8.0]
  def change
    # Add entity reference to contacts
    add_reference :contacts, :entity, foreign_key: true
    
    # Add entity reference to contact groups
    add_reference :contact_groups, :entity, foreign_key: true
    
    # Add entity reference to email templates
    add_reference :email_templates, :entity, foreign_key: true
    
    # Add entity reference to campaigns
    add_reference :campaigns, :entity, foreign_key: true
    
    # Add entity reference to social posts
    add_reference :social_posts, :entity, foreign_key: true
    
    # Add entity reference to social media accounts
    add_reference :social_media_accounts, :entity, foreign_key: true
    
    # Add entity reference to business profiles
    add_reference :business_profiles, :entity, foreign_key: true
  end
end
