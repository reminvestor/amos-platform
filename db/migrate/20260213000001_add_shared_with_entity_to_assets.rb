# frozen_string_literal: true

# Add shared_with_entity to all asset types so users can choose
# to share their creations with the rest of their entity/team.
#
# AppModule already has a `visibility` column - the other assets
# use a simpler boolean since they don't need the full
# user_private/entity_private/entity_shared/public spectrum.
#
class AddSharedWithEntityToAssets < ActiveRecord::Migration[7.2]
  def change
    # Landing Pages - already has user_id
    add_column :landing_pages, :shared_with_entity, :boolean, default: false, null: false

    # Automation Codes - already has created_by_id
    add_column :automation_codes, :shared_with_entity, :boolean, default: false, null: false

    # Websites - already has created_by_id
    add_column :websites, :shared_with_entity, :boolean, default: false, null: false

    # Web Apps - already has created_by_id
    add_column :web_apps, :shared_with_entity, :boolean, default: false, null: false

    # Apps - already has created_by_id
    add_column :apps, :shared_with_entity, :boolean, default: false, null: false

    # Email Sequences - needs created_by_id (currently entity-scoped only)
    add_reference :email_sequences, :created_by, foreign_key: { to_table: :users }, null: true
    add_column :email_sequences, :shared_with_entity, :boolean, default: false, null: false

    # Add indexes for the sharing queries (user_id + shared_with_entity)
    add_index :landing_pages, [:entity_id, :shared_with_entity], name: "idx_lp_entity_shared"
    add_index :automation_codes, [:entity_id, :shared_with_entity], name: "idx_auto_entity_shared"
    add_index :websites, [:entity_id, :shared_with_entity], name: "idx_sites_entity_shared"
    add_index :web_apps, [:entity_id, :shared_with_entity], name: "idx_webapps_entity_shared"
    add_index :apps, [:entity_id, :shared_with_entity], name: "idx_apps_entity_shared"
    add_index :email_sequences, [:entity_id, :shared_with_entity], name: "idx_seqs_entity_shared"
  end
end
