require "test_helper"

class UserTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # from_omniauth Tests - OAuth signup flow
  # ═══════════════════════════════════════════════════════════════════════════
  
  test "from_omniauth creates new user with entity and subdomain" do
    auth = mock_google_auth(
      email: "newuser@example.com",
      first_name: "John",
      last_name: "Doe"
    )
    
    assert_difference -> { User.count } => 1, -> { Entity.count } => 1, -> { EntityUser.count } => 1 do
      user = User.from_omniauth(auth)
      
      assert user.persisted?
      assert_equal "newuser@example.com", user.email
      assert_equal "John", user.first_name
      assert_equal "Doe", user.last_name
      assert_equal "google_oauth2", user.provider
      assert_equal "123456789", user.uid
      
      # Entity should be created with proper subdomain
      assert user.entity.present?
      assert_equal "John's Organization", user.entity.name
      assert user.entity.subdomain.present?
      assert_match(/^john-s-organization/, user.entity.subdomain)
      assert_equal "active", user.entity.status
      
      # User should be in entity_users (via callback)
      entity_user = EntityUser.find_by(user: user, entity: user.entity)
      assert entity_user.present?
    end
  end
  
  test "from_omniauth generates unique subdomain when collision exists" do
    # Create entity with subdomain that would collide
    Entity.create!(name: "Existing", subdomain: "jane-s-organization", status: "active")
    
    auth = mock_google_auth(
      email: "jane@example.com",
      first_name: "Jane",
      last_name: "Smith"
    )
    
    user = User.from_omniauth(auth)
    
    # Should have incremented subdomain to avoid collision
    assert user.entity.subdomain.present?
    assert_match(/^jane-s-organization-\d+$/, user.entity.subdomain)
  end
  
  test "from_omniauth uses random subdomain when name is blank" do
    auth = mock_google_auth(
      email: "noname@example.com",
      first_name: nil,
      last_name: nil,
      name: nil
    )
    
    user = User.from_omniauth(auth)
    
    # Should fall back to SecureRandom for subdomain
    assert user.entity.subdomain.present?
    assert user.entity.subdomain.length >= 6
  end
  
  test "from_omniauth returns existing user by provider and uid" do
    existing_entity = entities(:one)
    existing_user = User.create!(
      email: "existing@example.com",
      first_name: "Existing",
      last_name: "User",
      password: "Password123!",
      provider: "google_oauth2",
      uid: "existing_uid_123",
      entity: existing_entity,
      role: "admin"
    )
    
    auth = mock_google_auth(
      email: "existing@example.com",
      uid: "existing_uid_123"
    )
    
    assert_no_difference ["User.count", "Entity.count"] do
      user = User.from_omniauth(auth)
      assert_equal existing_user.id, user.id
    end
  end
  
  test "from_omniauth returns existing user by email and updates oauth details" do
    existing_entity = entities(:one)
    existing_user = User.create!(
      email: "existing@example.com",
      first_name: "Existing",
      last_name: "User",
      password: "Password123!",
      provider: nil,
      uid: nil,
      entity: existing_entity,
      role: "admin"
    )
    
    auth = mock_google_auth(
      email: "existing@example.com",
      uid: "new_oauth_uid"
    )
    
    assert_no_difference ["User.count", "Entity.count"] do
      user = User.from_omniauth(auth)
      assert_equal existing_user.id, user.id
      
      # OAuth details should be updated
      user.reload
      assert_equal "google_oauth2", user.provider
      assert_equal "new_oauth_uid", user.uid
    end
  end
  
  test "from_omniauth does not create duplicate EntityUser" do
    auth = mock_google_auth(
      email: "nodupe@example.com",
      first_name: "No",
      last_name: "Dupe"
    )
    
    # This should not raise an error about duplicate EntityUser
    user = User.from_omniauth(auth)
    
    # Should have exactly one EntityUser record
    entity_user_count = EntityUser.where(user: user, entity: user.entity).count
    assert_equal 1, entity_user_count
  end
  
  private
  
  def mock_google_auth(email:, first_name: "Test", last_name: "User", name: nil, uid: "123456789")
    auth = OpenStruct.new(
      provider: "google_oauth2",
      uid: uid,
      info: OpenStruct.new(
        email: email,
        first_name: first_name,
        last_name: last_name,
        name: name || [first_name, last_name].compact.join(" "),
        image: "https://example.com/avatar.jpg"
      )
    )
    auth
  end
end
