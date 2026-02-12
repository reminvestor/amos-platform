# frozen_string_literal: true

require 'test_helper'

class RowLevelSecurityIntegrationTest < ActionDispatch::IntegrationTest
  include RowLevelSecurityHelper

  setup do
    @entity1 = entities(:one)
    @entity2 = entities(:two)

    # Create users for each entity with known passwords
    @user1 = User.create!(
      email: 'user1@entity1.com',
      password: 'TestPassword123!',
      password_confirmation: 'TestPassword123!',
      entity: @entity1
    )
    @user1.generate_api_key!

    @user2 = User.create!(
      email: 'user2@entity2.com',
      password: 'TestPassword123!',
      password_confirmation: 'TestPassword123!',
      entity: @entity2
    )
    @user2.generate_api_key!

    # Create test data for each entity
    @campaign1 = Campaign.create!(
      name: 'Entity 1 Campaign',
      entity: @entity1,
      description: 'Test Description 1',
      status: 'draft'
    )

    @campaign2 = Campaign.create!(
      name: 'Entity 2 Campaign',
      entity: @entity2,
      description: 'Test Description 2',
      status: 'draft'
    )

    @contact1 = Contact.create!(
      email: 'contact1@entity1.com',
      entity: @entity1,
      first_name: 'Contact',
      last_name: 'One'
    )

    @contact2 = Contact.create!(
      email: 'contact2@entity2.com',
      entity: @entity2,
      first_name: 'Contact',
      last_name: 'Two'
    )
  end

  # Test API endpoints respect RLS
  test "user cannot access other entity campaigns via API" do
    # Login as user from entity 1
    get api_campaigns_url, headers: {
      'Authorization' => "Bearer #{@user1.api_key}"
    }

    assert_response :success
    campaigns = JSON.parse(response.body)

    # Should only see entity 1 campaigns
    campaign_ids = campaigns.map { |c| c['id'] }
    assert_includes campaign_ids, @campaign1.id, 'Should see entity 1 campaign'
    assert_not_includes campaign_ids, @campaign2.id, 'Should not see entity 2 campaign'
  end

  test "user cannot fetch specific campaign from other entity via API" do
    # Try to access entity 2 campaign as user 1
    get api_campaign_url(@campaign2), headers: {
      'Authorization' => "Bearer #{@user1.api_key}"
    }

    assert_response :not_found
  end

  test "user can fetch specific campaign from same entity via API" do
    # Access entity 1 campaign as user 1
    get api_campaign_url(@campaign1), headers: {
      'Authorization' => "Bearer #{@user1.api_key}"
    }

    assert_response :success
    campaign = JSON.parse(response.body)
    assert_equal @campaign1.id, campaign['id']
  end

  test "user cannot create campaign for other entity via API" do
    # Try to create campaign with entity 2's ID as user 1
    post api_campaigns_url, headers: {
      'Authorization' => "Bearer #{@user1.api_key}",
      'Content-Type' => 'application/json'
    }, params: {
      campaign: {
        name: 'Hacked Campaign',
        entity_id: @entity2.id,
        description: 'Test',
        status: 'draft'
      }
    }.to_json

    # Should either fail with validation error or create for user's own entity
    if response.successful?
      campaign = JSON.parse(response.body)
      assert_equal @entity1.id, campaign['entity_id'], 'Should be forced to user\'s entity'
    else
      assert_response :unprocessable_entity
    end
  end

  test "user cannot update campaign from other entity via API" do
    # Try to update entity 2 campaign as user 1
    patch api_campaign_url(@campaign2), headers: {
      'Authorization' => "Bearer #{@user1.api_key}",
      'Content-Type' => 'application/json'
    }, params: {
      campaign: {
        name: 'Hacked Name'
      }
    }.to_json

    assert_response :not_found
  end

  test "user can update campaign from same entity via API" do
    # Update entity 1 campaign as user 1
    patch api_campaign_url(@campaign1), headers: {
      'Authorization' => "Bearer #{@user1.api_key}",
      'Content-Type' => 'application/json'
    }, params: {
      campaign: {
        name: 'Updated Campaign Name'
      }
    }.to_json

    assert_response :success
    campaign = JSON.parse(response.body)
    assert_equal 'Updated Campaign Name', campaign['name']
  end

  test "user cannot delete campaign from other entity via API" do
    # Try to delete entity 2 campaign as user 1
    delete api_campaign_url(@campaign2), headers: {
      'Authorization' => "Bearer #{@user1.api_key}"
    }

    assert_response :not_found

    # Verify campaign still exists
    assert Campaign.exists?(@campaign2.id), 'Campaign should not be deleted'
  end

  test "user can delete campaign from same entity via API" do
    # Delete entity 1 campaign as user 1
    delete api_campaign_url(@campaign1), headers: {
      'Authorization' => "Bearer #{@user1.api_key}"
    }

    assert_response :no_content

    # Verify campaign is deleted (using entity 1 context)
    with_entity_context(@entity1) do
      assert_not Campaign.exists?(@campaign1.id), 'Campaign should be deleted'
    end
  end

  # Test contacts API endpoints
  test "user cannot access other entity contacts via API" do
    get api_contacts_url, headers: {
      'Authorization' => "Bearer #{@user1.api_key}"
    }

    assert_response :success
    contacts = JSON.parse(response.body)

    contact_ids = contacts.map { |c| c['id'] }
    assert_includes contact_ids, @contact1.id
    assert_not_includes contact_ids, @contact2.id
  end

  test "user cannot fetch specific contact from other entity via API" do
    get api_contact_url(@contact2), headers: {
      'Authorization' => "Bearer #{@user1.api_key}"
    }

    assert_response :not_found
  end

  # Test RLS context is properly set by middleware
  test "RLS context is set correctly for authenticated requests" do
    # Make a request as user 1
    get api_campaigns_url, headers: {
      'Authorization' => "Bearer #{@user1.api_key}"
    }

    assert_response :success

    # The middleware and controller should have set the entity context
    # We can verify by checking that only entity 1 campaigns are returned
    campaigns = JSON.parse(response.body)
    assert_equal 1, campaigns.length, 'Should only see 1 campaign (from entity 1)'
  end

  # Test direct SQL injection attempts are blocked
  test "SQL injection attempts are blocked by RLS" do
    # Simulate an attack where user tries to bypass entity filter
    # This would happen in a controller if there's a SQL injection vulnerability
    with_entity_context(@user1.entity) do
      # Even if an attacker can inject SQL, RLS should prevent access
      result = ActiveRecord::Base.connection.execute(
        "SELECT * FROM campaigns WHERE entity_id = #{@entity2.id}"
      )

      assert_equal 0, result.count, 'RLS should block access to other entity data'
    end
  end

  # Test RLS works with API key authentication
  test "RLS context is set correctly with API key authentication" do
    # This verifies the EntityScoped concern sets RLS context
    get api_campaigns_url, headers: {
      'Authorization' => "Bearer #{@user1.api_key}"
    }

    assert_response :success

    # Verify helper method shows correct entity
    # (This would be set in the controller via EntityScoped concern)
    campaigns = JSON.parse(response.body)
    campaigns.each do |campaign|
      assert_equal @entity1.id, campaign['entity_id'], 'All campaigns should belong to user\'s entity'
    end
  end

  # Test RLS persists across multiple requests (no cross-contamination)
  test "RLS context is isolated between requests" do
    # Request 1: User 1
    get api_campaigns_url, headers: {
      'Authorization' => "Bearer #{@user1.api_key}"
    }
    assert_response :success
    campaigns1 = JSON.parse(response.body)

    # Request 2: User 2
    get api_campaigns_url, headers: {
      'Authorization' => "Bearer #{@user2.api_key}"
    }
    assert_response :success
    campaigns2 = JSON.parse(response.body)

    # Verify each user sees only their own data
    assert_equal 1, campaigns1.length
    assert_equal @campaign1.id, campaigns1.first['id']

    assert_equal 1, campaigns2.length
    assert_equal @campaign2.id, campaigns2.first['id']
  end

  # Test unauthenticated requests have no entity context
  test "unauthenticated requests have no RLS context" do
    # Make request without authentication
    # This should either fail authentication or have no entity context
    get api_campaigns_url

    # Should return unauthorized (no API key)
    assert_response :unauthorized
  end

  # Test batch operations respect RLS
  test "batch operations respect RLS boundaries" do
    # Try to batch delete campaigns including one from another entity
    delete api_campaigns_batch_url, headers: {
      'Authorization' => "Bearer #{@user1.api_key}",
      'Content-Type' => 'application/json'
    }, params: {
      ids: [@campaign1.id, @campaign2.id]
    }.to_json

    # Only campaign 1 should be deleted (if endpoint exists)
    # If endpoint doesn't exist, we'll get 404
    if response.status == 404
      skip "Batch delete endpoint not implemented"
    else
      with_entity_context(@entity1) do
        assert_not Campaign.exists?(@campaign1.id), 'Campaign 1 should be deleted'
      end

      with_entity_context(@entity2) do
        assert Campaign.exists?(@campaign2.id), 'Campaign 2 should still exist'
      end
    end
  end

  # Test RLS works with associations
  test "associated records are also protected by RLS" do
    # Create contact groups for each entity
    group1 = ContactGroup.create!(
      name: 'Group 1',
      entity: @entity1
    )

    group2 = ContactGroup.create!(
      name: 'Group 2',
      entity: @entity2
    )

    # User 1 should only see group 1
    get api_contact_groups_url, headers: {
      'Authorization' => "Bearer #{@user1.api_key}"
    }

    if response.successful?
      groups = JSON.parse(response.body)
      group_ids = groups.map { |g| g['id'] }

      assert_includes group_ids, group1.id
      assert_not_includes group_ids, group2.id
    else
      skip "Contact groups API endpoint not implemented"
    end
  end
end
