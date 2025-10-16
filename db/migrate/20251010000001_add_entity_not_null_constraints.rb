class AddEntityNotNullConstraints < ActiveRecord::Migration[8.0]
  def up
    # First, ensure all existing records have an entity_id
    # Set to the first available entity if null
    default_entity = Entity.first

    if default_entity
      Contact.where(entity_id: nil).update_all(entity_id: default_entity.id)
      Campaign.where(entity_id: nil).update_all(entity_id: default_entity.id)
      ContactGroup.where(entity_id: nil).update_all(entity_id: default_entity.id)
      EmailTemplate.where(entity_id: nil).update_all(entity_id: default_entity.id)
      LandingPage.where(entity_id: nil).update_all(entity_id: default_entity.id)
      EmailSequence.where(entity_id: nil).update_all(entity_id: default_entity.id)
      SequenceEnrollment.where(entity_id: nil).update_all(entity_id: default_entity.id)
    end

    # Now add NOT NULL constraints
    change_column_null :contacts, :entity_id, false
    change_column_null :campaigns, :entity_id, false
    change_column_null :contact_groups, :entity_id, false
    change_column_null :email_templates, :entity_id, false
    change_column_null :landing_pages, :entity_id, false
    change_column_null :email_sequences, :entity_id, false
    change_column_null :sequence_enrollments, :entity_id, false
  end

  def down
    # Remove NOT NULL constraints
    change_column_null :contacts, :entity_id, true
    change_column_null :campaigns, :entity_id, true
    change_column_null :contact_groups, :entity_id, true
    change_column_null :email_templates, :entity_id, true
    change_column_null :landing_pages, :entity_id, true
    change_column_null :email_sequences, :entity_id, true
    change_column_null :sequence_enrollments, :entity_id, true
  end
end
