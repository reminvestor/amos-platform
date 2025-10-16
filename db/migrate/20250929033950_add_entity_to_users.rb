class AddEntityToUsers < ActiveRecord::Migration[8.0]
  def up
    # Add the entity_id column without foreign key constraint first
    add_reference :users, :entity, null: true, foreign_key: false

    # Migrate existing users to have their first entity
    User.reset_column_information

    # Use raw SQL to find entities for users since we removed the association
    User.find_each do |user|
      entity_user = execute("SELECT entity_id FROM entity_users WHERE user_id = #{user.id} LIMIT 1").first

      if entity_user
        user.update_column(:entity_id, entity_user['entity_id'])
      else
        # Create a default entity for users without one
        entity = Entity.create!(
          name: "#{user.first_name} #{user.last_name}'s Organization",
          subdomain: "user-#{user.id}",
          slug: "user-#{user.id}",
          status: 'active'
        )
        user.update_column(:entity_id, entity.id)
      end
    end

    # Now make the column not null and add foreign key
    change_column_null :users, :entity_id, false
    add_foreign_key :users, :entities
  end

  def down
    remove_foreign_key :users, :entities
    remove_reference :users, :entity
  end
end
