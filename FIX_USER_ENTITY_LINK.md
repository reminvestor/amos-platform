# Fix User-Entity Link in Production

## The Problem
After migrating to a 1:1 User→Entity relationship, existing users need their `entity_id` set.

## Option 1: Via Rails Console on AWS (Quick Fix)

### Step 1: Open Rails Console
```bash
./aws/rails-console.sh
```

### Step 2: Link User to Entity
```ruby
# Find your user
user = User.find(1)

# Find entity 1  
entity = Entity.find(1)

# Link them
user.update(entity_id: entity.id)

# Verify
puts "User #{user.email} is now linked to Entity #{entity.name}"
puts "user.entity = #{user.entity.name}"

# Exit
exit
```

## Option 2: Via Migration (Permanent Fix)

Create a migration to link all users to their primary entities:

```bash
bin/rails generate migration LinkUsersToEntities
```

Then edit the migration:

```ruby
class LinkUsersToEntities < ActiveRecord::Migration[8.0]
  def up
    # Link each user to their first EntityUser entity
    User.find_each do |user|
      # Find user's primary entity via EntityUser with 'owner' role
      entity_user = EntityUser.find_by(user: user, role: 'owner')
      entity_user ||= EntityUser.find_by(user: user) # Fallback to any entity
      
      if entity_user
        user.update_column(:entity_id, entity_user.entity_id)
        puts "Linked User #{user.id} to Entity #{entity_user.entity_id}"
      else
        puts "⚠️  User #{user.id} has no entities"
      end
    end
  end
  
  def down
    # Optionally clear the entity_id links
    User.update_all(entity_id: nil)
  end
end
```

Run it:
```bash
bin/rails db:migrate
```

## What the Fix Does

**Before:**
- `user.entity` → `nil` (entity_id not set)
- `user.entity_users` → has links
- System redirects to create entity

**After:**
- `user.entity` → `Entity #1` ✅
- `user.entity_id` → `1` ✅
- System works normally

## Quick Console Commands

```ruby
# Check current status
User.find(1).entity_id
User.find(1).entity

# Fix user 1
User.find(1).update(entity_id: 1)

# Fix all users
User.find_each do |user|
  entity = user.entity_users.first&.entity
  user.update(entity_id: entity.id) if entity
end
```

