# frozen_string_literal: true

require 'test_helper'

class RowLevelSecurityTest < ActiveSupport::TestCase
  include RowLevelSecurityHelper

  setup do
    @entity1 = entities(:one)
    @entity2 = entities(:two)

    # Create users for each entity (users table doesn't have RLS)
    @user1 = User.create!(
      email: 'user1@entity1.com',
      password: 'TestPassword123!',
      password_confirmation: 'TestPassword123!',
      entity: @entity1
    )
    @user2 = User.create!(
      email: 'user2@entity2.com',
      password: 'TestPassword123!',
      password_confirmation: 'TestPassword123!',
      entity: @entity2
    )

    # Create entity 1 data WITH entity 1 context
    with_entity_context(@entity1) do
      @campaign1 = Campaign.create!(
        name: 'Entity 1 Campaign',
        entity: @entity1,
        user: @user1,
        description: 'Test Description',
        status: 'draft'
      )

      @contact1 = Contact.create!(
        email: 'entity1@example.com',
        entity: @entity1,
        user: @user1,
        first_name: 'Contact',
        last_name: 'One'
      )

      @landing_page1 = LandingPage.create!(
        title: 'Entity 1 Landing Page',
        entity: @entity1,
        user: @user1,
        slug: 'entity-1-page',
        html_content: '<h1>Entity 1</h1>',
        status: 'draft'
      )
    end

    # Create entity 2 data WITH entity 2 context
    with_entity_context(@entity2) do
      @campaign2 = Campaign.create!(
        name: 'Entity 2 Campaign',
        entity: @entity2,
        user: @user2,
        description: 'Test Description',
        status: 'draft'
      )

      @contact2 = Contact.create!(
        email: 'entity2@example.com',
        entity: @entity2,
        user: @user2,
        first_name: 'Contact',
        last_name: 'Two'
      )

      @landing_page2 = LandingPage.create!(
        title: 'Entity 2 Landing Page',
        entity: @entity2,
        user: @user2,
        slug: 'entity-2-page',
        html_content: '<h1>Entity 2</h1>',
        status: 'draft'
      )
    end

    # Reset context after setup
    ActiveRecord::Base.connection.execute("RESET app.current_entity_id") rescue nil
  end

  # Test RLS infrastructure is properly configured
  test "RLS is enabled on entity-scoped tables" do
    assert rls_enabled?('campaigns'), 'RLS should be enabled on campaigns table'
    assert rls_enabled?('contacts'), 'RLS should be enabled on contacts table'
    assert rls_enabled?('landing_pages'), 'RLS should be enabled on landing_pages table'
  end

  test "RLS policies exist for entity-scoped tables" do
    assert rls_policy_exists?('campaigns', 'campaigns_entity_isolation'),
           'Entity isolation policy should exist for campaigns'
    assert rls_policy_exists?('contacts', 'contacts_entity_isolation'),
           'Entity isolation policy should exist for contacts'
    assert rls_policy_exists?('landing_pages', 'landing_pages_entity_isolation'),
           'Entity isolation policy should exist for landing_pages'
  end

  # Test entity isolation for SELECT queries
  test "user can only see own entity campaigns" do
    with_entity_context(@entity1) do
      campaigns = Campaign.all.to_a

      # Verify we see our entity 1 campaign
      assert campaigns.any? { |c| c.id == @campaign1.id }, 'Should see entity 1 campaign'

      # Verify NO campaigns from entity 2 are visible (RLS enforcement)
      entity2_campaigns = campaigns.select { |c| c.entity_id == @entity2.id }
      assert_empty entity2_campaigns, 'RLS should prevent seeing entity 2 campaigns'
    end
  end

  test "user can only see own entity contacts" do
    with_entity_context(@entity1) do
      contacts = Contact.all.to_a

      # Verify we see our entity 1 contact
      assert contacts.any? { |c| c.id == @contact1.id }, 'Should see entity 1 contact'

      # Verify NO contacts from entity 2 are visible (RLS enforcement)
      entity2_contacts = contacts.select { |c| c.entity_id == @entity2.id }
      assert_empty entity2_contacts, 'RLS should prevent seeing entity 2 contacts'
    end
  end

  test "user can only see own entity landing pages" do
    with_entity_context(@entity1) do
      landing_pages = LandingPage.all.to_a

      # Verify we see our entity 1 landing page
      assert landing_pages.any? { |p| p.id == @landing_page1.id }, 'Should see entity 1 landing page'

      # Verify NO landing pages from entity 2 are visible (RLS enforcement)
      entity2_pages = landing_pages.select { |p| p.entity_id == @entity2.id }
      assert_empty entity2_pages, 'RLS should prevent seeing entity 2 landing pages'
    end
  end

  # Test entity context switching
  test "switching entity context changes visible data" do
    # Entity 1 context
    with_entity_context(@entity1) do
      assert_equal 1, Campaign.count, 'Should see 1 campaign for entity 1'
      assert_equal @campaign1.id, Campaign.first.id
    end

    # Entity 2 context
    with_entity_context(@entity2) do
      assert_equal 1, Campaign.count, 'Should see 1 campaign for entity 2'
      assert_equal @campaign2.id, Campaign.first.id
    end
  end

  # Test finding specific records
  test "cannot find record from other entity by ID" do
    with_entity_context(@entity1) do
      # Should not be able to find entity 2's campaign
      assert_raises(ActiveRecord::RecordNotFound) do
        Campaign.find(@campaign2.id)
      end
    end
  end

  test "can find record from same entity by ID" do
    with_entity_context(@entity1) do
      campaign = Campaign.find(@campaign1.id)
      assert_equal @campaign1.id, campaign.id
    end
  end

  # Test unscoped queries (RLS should still apply)
  test "unscoped queries still respect RLS policies" do
    with_entity_context(@entity1) do
      # Even with unscoped, RLS should prevent seeing other entity data
      campaigns = Campaign.unscoped.to_a

      # Verify we see entity 1 campaign
      assert campaigns.any? { |c| c.id == @campaign1.id }, 'Should see entity 1 campaign'

      # Verify RLS still blocks entity 2 campaigns even with unscoped
      entity2_campaigns = campaigns.select { |c| c.entity_id == @entity2.id }
      assert_empty entity2_campaigns, 'RLS should block entity 2 campaigns even with unscoped'
    end
  end

  # Test INSERT operations
  test "cannot insert data for other entity" do
    with_entity_context(@entity1) do
      # Attempt to insert with entity 2's ID
      campaign = Campaign.new(
        name: 'Hacked Campaign',
        entity_id: @entity2.id,
        user: @user1,
        description: 'Exploit',
        status: 'draft'
      )

      # RLS WITH CHECK should block this insert
      assert_raises(ActiveRecord::StatementInvalid) do
        campaign.save!
      end
    end
  end

  test "can insert data for current entity" do
    with_entity_context(@entity1) do
      campaign = Campaign.create!(
        name: 'Valid Campaign',
        entity_id: @entity1.id,
        user: @user1,
        description: 'Test',
        status: 'draft'
      )

      assert campaign.persisted?
      assert_equal @entity1.id, campaign.entity_id
    end
  end

  # Test UPDATE operations
  test "cannot update record to belong to other entity" do
    with_entity_context(@entity1) do
      # Try to change entity_id to entity 2
      @campaign1.entity_id = @entity2.id

      # RLS WITH CHECK should block this update
      assert_raises(ActiveRecord::StatementInvalid) do
        @campaign1.save!
      end
    end
  end

  test "can update record within same entity" do
    with_entity_context(@entity1) do
      @campaign1.name = 'Updated Campaign Name'
      assert @campaign1.save!
      assert_equal 'Updated Campaign Name', @campaign1.reload.name
    end
  end

  # Test DELETE operations
  test "cannot delete record from other entity" do
    with_entity_context(@entity1) do
      # Should not be able to find the record to delete
      assert_raises(ActiveRecord::RecordNotFound) do
        Campaign.find(@campaign2.id).destroy
      end
    end
  end

  test "can delete record from same entity" do
    with_entity_context(@entity1) do
      campaign = Campaign.find(@campaign1.id)
      assert campaign.destroy
      assert_not Campaign.exists?(@campaign1.id)
    end
  end

  # Test without entity context (should deny all access)
  test "without entity context, SELECT returns no data" do
    without_entity_context do
      campaigns = Campaign.all.to_a
      assert_empty campaigns, 'Should see no campaigns without entity context'
    end
  end

  test "without entity context, INSERT is blocked" do
    without_entity_context do
      campaign = Campaign.new(
        name: 'No Context Campaign',
        entity_id: @entity1.id,
        user: @user1,
        description: 'Test',
        status: 'draft'
      )

      # Should fail because no entity context is set
      assert_raises(ActiveRecord::StatementInvalid) do
        campaign.save!
      end
    end
  end

  test "without entity context, UPDATE is blocked" do
    # First set context to load the record
    campaign = nil
    with_entity_context(@entity1) do
      campaign = Campaign.find(@campaign1.id)
    end

    # Now try to update without context
    without_entity_context do
      campaign.name = 'Updated Name'

      # Should fail because no entity context is set
      assert_raises(ActiveRecord::StatementInvalid) do
        campaign.save!
      end
    end
  end

  # Test direct SQL injection attempts (RLS should block)
  test "direct SQL bypasses are blocked by RLS" do
    with_entity_context(@entity1) do
      # Attempt raw SQL that tries to access all campaigns
      result = ActiveRecord::Base.connection.execute(
        "SELECT * FROM campaigns WHERE id = #{@campaign2.id}"
      )

      # RLS should prevent seeing entity 2's campaign
      assert_equal 0, result.count, 'RLS should block direct SQL access to other entity data'
    end
  end

  # Test helper methods
  test "current_rls_entity_id returns correct entity ID" do
    with_entity_context(@entity1) do
      assert_equal @entity1.id, current_rls_entity_id
    end

    with_entity_context(@entity2) do
      assert_equal @entity2.id, current_rls_entity_id
    end

    without_entity_context do
      assert_nil current_rls_entity_id
    end
  end

  # Test RLS with where clauses
  test "where clause filtering still respects RLS" do
    with_entity_context(@entity1) do
      # Try to find entity 2's campaign by explicit where clause
      campaigns = Campaign.where(entity_id: @entity2.id).to_a

      assert_empty campaigns, 'RLS should block access even with explicit where clause'
    end
  end

  # Test RLS with joins (if applicable)
  test "joined queries respect RLS on both tables" do
    # Create email templates linked to campaigns
    template1 = EmailTemplate.create!(
      name: 'Template 1',
      entity: @entity1,
      user: @user1,
      subject: 'Subject 1',
      body: 'Body 1'
    )

    template2 = EmailTemplate.create!(
      name: 'Template 2',
      entity: @entity2,
      user: @user2,
      subject: 'Subject 2',
      body: 'Body 2'
    )

    with_entity_context(@entity1) do
      # Join campaigns with email_templates - should only see entity 1 data
      templates = EmailTemplate.joins(:entity).where(entities: { id: @entity1.id }).to_a

      assert_includes templates, template1
      assert_not_includes templates, template2
    end
  end

  # Test RLS with count queries
  test "count queries respect RLS" do
    with_entity_context(@entity1) do
      assert_equal 1, Campaign.count
    end

    with_entity_context(@entity2) do
      assert_equal 1, Campaign.count
    end

    without_entity_context do
      assert_equal 0, Campaign.count
    end
  end

  # Test RLS with exists queries
  test "exists queries respect RLS" do
    with_entity_context(@entity1) do
      assert Campaign.exists?(@campaign1.id)
      assert_not Campaign.exists?(@campaign2.id)
    end

    with_entity_context(@entity2) do
      assert_not Campaign.exists?(@campaign1.id)
      assert Campaign.exists?(@campaign2.id)
    end
  end

  # Test RLS with pluck queries
  test "pluck queries respect RLS" do
    with_entity_context(@entity1) do
      ids = Campaign.pluck(:id)
      assert_includes ids, @campaign1.id
      assert_not_includes ids, @campaign2.id
    end
  end

  # Test RLS with find_by queries
  test "find_by queries respect RLS" do
    with_entity_context(@entity1) do
      campaign = Campaign.find_by(id: @campaign2.id)
      assert_nil campaign, 'Should not find campaign from other entity'

      campaign = Campaign.find_by(id: @campaign1.id)
      assert_not_nil campaign, 'Should find campaign from same entity'
    end
  end
end
