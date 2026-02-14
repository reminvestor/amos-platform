# frozen_string_literal: true

require 'test_helper'

class RowLevelSecurityTest < ActiveSupport::TestCase
  include RowLevelSecurityHelper

  # Must disable transactional tests because the app_user connection
  # is separate from the Rails test connection. Transactional data
  # created by ActiveRecord is not visible to the separate connection.
  self.use_transactional_tests = false

  setup do
    # Ensure RLS is enabled on test tables (idempotent)
    ensure_rls_enabled!

    @entity1 = entities(:one)
    @entity2 = entities(:two)

    # Create users via superuser connection (bypasses RLS - fine for setup)
    @user1 = User.create!(
      email: "rls_user1_#{SecureRandom.hex(4)}@entity1.com",
      password: 'TestPassword123!',
      password_confirmation: 'TestPassword123!',
      entity: @entity1
    )
    @user2 = User.create!(
      email: "rls_user2_#{SecureRandom.hex(4)}@entity2.com",
      password: 'TestPassword123!',
      password_confirmation: 'TestPassword123!',
      entity: @entity2
    )

    # Create test data via superuser connection (bypasses RLS)
    @campaign1 = Campaign.create!(
      name: "RLS Test Campaign E1 #{SecureRandom.hex(4)}",
      entity: @entity1,
      user: @user1,
      description: 'Test Description',
      status: 'draft'
    )
    @campaign2 = Campaign.create!(
      name: "RLS Test Campaign E2 #{SecureRandom.hex(4)}",
      entity: @entity2,
      user: @user2,
      description: 'Test Description',
      status: 'draft'
    )

    @contact1 = Contact.create!(
      email: "rls_e1_#{SecureRandom.hex(4)}@example.com",
      entity: @entity1,
      user: @user1,
      first_name: 'RLSContact',
      last_name: 'One'
    )
    @contact2 = Contact.create!(
      email: "rls_e2_#{SecureRandom.hex(4)}@example.com",
      entity: @entity2,
      user: @user2,
      first_name: 'RLSContact',
      last_name: 'Two'
    )

    @landing_page1 = LandingPage.create!(
      title: 'RLS Entity 1 Landing Page',
      entity: @entity1,
      user: @user1,
      slug: "rls-e1-page-#{SecureRandom.hex(4)}",
      html_content: '<h1>Entity 1</h1>',
      status: 'draft'
    )
    @landing_page2 = LandingPage.create!(
      title: 'RLS Entity 2 Landing Page',
      entity: @entity2,
      user: @user2,
      slug: "rls-e2-page-#{SecureRandom.hex(4)}",
      html_content: '<h1>Entity 2</h1>',
      status: 'draft'
    )
  end

  teardown do
    # Clean up test data since we're not using transactional tests
    # Use superuser connection (ActiveRecord::Base) to bypass RLS for cleanup
    # Order matters: delete dependent records first to avoid FK violations
    LandingPage.where(id: [@landing_page1&.id, @landing_page2&.id].compact).delete_all
    Contact.where(id: [@contact1&.id, @contact2&.id].compact).delete_all
    Campaign.where(id: [@campaign1&.id, @campaign2&.id].compact).delete_all
    Campaign.where(name: 'RLS Valid Insert').delete_all

    # Clean up users - need to handle entity_users FK
    [@user1, @user2].compact.each do |user|
      ActiveRecord::Base.connection.execute(
        "DELETE FROM entity_users WHERE user_id = #{user.id}"
      ) rescue nil
      user.destroy rescue nil
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Infrastructure tests (use superuser - just checking metadata)
  # ═══════════════════════════════════════════════════════════════

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

  # ═══════════════════════════════════════════════════════════════
  # RLS enforcement tests (use app_user via rls_connection)
  # All queries below go through the non-superuser connection
  # ═══════════════════════════════════════════════════════════════

  # --- SELECT isolation ---

  test "user can only see own entity campaigns" do
    with_entity_context(@entity1) do |conn|
      rows = conn.execute("SELECT id, entity_id FROM campaigns").to_a

      entity_ids = rows.map { |r| r['entity_id'] }
      assert entity_ids.all? { |eid| eid == @entity1.id }, 'All visible campaigns should belong to entity 1'
      assert rows.any? { |r| r['id'] == @campaign1.id }, 'Should see entity 1 campaign'
      assert rows.none? { |r| r['id'] == @campaign2.id }, 'Should not see entity 2 campaign'
    end
  end

  test "user can only see own entity contacts" do
    with_entity_context(@entity1) do |conn|
      rows = conn.execute("SELECT id, entity_id FROM contacts").to_a

      entity_ids = rows.map { |r| r['entity_id'] }
      assert entity_ids.all? { |eid| eid == @entity1.id }, 'All visible contacts should belong to entity 1'
      assert rows.any? { |r| r['id'] == @contact1.id }, 'Should see entity 1 contact'
      assert rows.none? { |r| r['id'] == @contact2.id }, 'Should not see entity 2 contact'
    end
  end

  test "user can only see own entity landing pages" do
    with_entity_context(@entity1) do |conn|
      rows = conn.execute("SELECT id, entity_id FROM landing_pages").to_a

      entity_ids = rows.map { |r| r['entity_id'] }
      assert entity_ids.all? { |eid| eid == @entity1.id }, 'All visible landing pages should belong to entity 1'
      assert rows.any? { |r| r['id'] == @landing_page1.id }, 'Should see entity 1 landing page'
      assert rows.none? { |r| r['id'] == @landing_page2.id }, 'Should not see entity 2 landing page'
    end
  end

  # --- Context switching ---

  test "switching entity context changes visible data" do
    with_entity_context(@entity1) do |conn|
      rows = conn.execute("SELECT id FROM campaigns").to_a
      ids = rows.map { |r| r['id'] }
      assert_includes ids, @campaign1.id, 'Should see entity 1 campaign'
      assert_not_includes ids, @campaign2.id, 'Should not see entity 2 campaign'
    end

    with_entity_context(@entity2) do |conn|
      rows = conn.execute("SELECT id FROM campaigns").to_a
      ids = rows.map { |r| r['id'] }
      assert_includes ids, @campaign2.id, 'Should see entity 2 campaign'
      assert_not_includes ids, @campaign1.id, 'Should not see entity 1 campaign'
    end
  end

  # --- Cannot find other entity records ---

  test "cannot find record from other entity by ID" do
    with_entity_context(@entity1) do |conn|
      rows = conn.execute("SELECT id FROM campaigns WHERE id = #{@campaign2.id}").to_a
      assert_empty rows, 'Should not find entity 2 campaign'
    end
  end

  test "can find record from same entity by ID" do
    with_entity_context(@entity1) do |conn|
      rows = conn.execute("SELECT id FROM campaigns WHERE id = #{@campaign1.id}").to_a
      assert_equal 1, rows.count, 'Should find entity 1 campaign'
    end
  end

  # --- INSERT operations ---

  test "cannot insert data for other entity" do
    with_entity_context(@entity1) do |conn|
      assert_raises(ActiveRecord::StatementInvalid) do
        conn.execute(<<-SQL)
          INSERT INTO campaigns (name, entity_id, user_id, status, created_at, updated_at)
          VALUES ('Hacked', #{@entity2.id}, #{@user1.id}, 'draft', NOW(), NOW())
        SQL
      end
    end
  end

  test "can insert data for current entity" do
    with_entity_context(@entity1) do |conn|
      count_before = conn.execute("SELECT COUNT(*) as cnt FROM campaigns").first['cnt']

      conn.execute(<<-SQL)
        INSERT INTO campaigns (name, entity_id, user_id, status, created_at, updated_at)
        VALUES ('RLS Valid Insert', #{@entity1.id}, #{@user1.id}, 'draft', NOW(), NOW())
      SQL

      count_after = conn.execute("SELECT COUNT(*) as cnt FROM campaigns").first['cnt']
      assert_equal count_before + 1, count_after, 'Should see one more campaign after insert'
    end
  end

  # --- UPDATE operations ---

  test "cannot update record to belong to other entity" do
    with_entity_context(@entity1) do |conn|
      assert_raises(ActiveRecord::StatementInvalid) do
        conn.execute(<<-SQL)
          UPDATE campaigns SET entity_id = #{@entity2.id} WHERE id = #{@campaign1.id}
        SQL
      end
    end
  end

  test "can update record within same entity" do
    with_entity_context(@entity1) do |conn|
      conn.execute(<<-SQL)
        UPDATE campaigns SET name = 'Updated Name' WHERE id = #{@campaign1.id}
      SQL

      rows = conn.execute("SELECT name FROM campaigns WHERE id = #{@campaign1.id}").to_a
      assert_equal 'Updated Name', rows.first['name']
    end
  end

  # --- DELETE operations ---

  test "cannot delete record from other entity" do
    with_entity_context(@entity1) do |conn|
      # This should silently affect 0 rows (RLS hides the record)
      conn.execute("DELETE FROM campaigns WHERE id = #{@campaign2.id}")

      # Verify it still exists via superuser
      assert Campaign.exists?(@campaign2.id), 'Entity 2 campaign should still exist'
    end
  end

  test "can delete record from same entity" do
    with_entity_context(@entity1) do |conn|
      conn.execute("DELETE FROM campaigns WHERE id = #{@campaign1.id}")

      rows = conn.execute("SELECT id FROM campaigns WHERE id = #{@campaign1.id}").to_a
      assert_empty rows, 'Campaign should be deleted'
    end

    # Mark as nil so teardown doesn't try to clean it up
    @campaign1 = nil
  end

  # --- No entity context (should deny all) ---

  test "without entity context, SELECT returns no data" do
    without_entity_context do |conn|
      count = conn.execute("SELECT COUNT(*) as cnt FROM campaigns").first['cnt']
      assert_equal 0, count, 'Should see no campaigns without entity context'
    end
  end

  test "without entity context, INSERT is blocked" do
    without_entity_context do |conn|
      assert_raises(ActiveRecord::StatementInvalid) do
        conn.execute(<<-SQL)
          INSERT INTO campaigns (name, entity_id, user_id, status, created_at, updated_at)
          VALUES ('No Context', #{@entity1.id}, #{@user1.id}, 'draft', NOW(), NOW())
        SQL
      end
    end
  end

  # --- Direct SQL bypass attempts ---

  test "direct SQL bypasses are blocked by RLS" do
    with_entity_context(@entity1) do |conn|
      rows = conn.execute("SELECT * FROM campaigns WHERE id = #{@campaign2.id}").to_a
      assert_equal 0, rows.count, 'RLS should block direct SQL access to other entity data'
    end
  end

  # --- Helper methods ---

  test "current_rls_entity_id returns correct entity ID" do
    with_entity_context(@entity1) do |_conn|
      assert_equal @entity1.id, current_rls_entity_id
    end

    with_entity_context(@entity2) do |_conn|
      assert_equal @entity2.id, current_rls_entity_id
    end

    without_entity_context do |_conn|
      assert_nil current_rls_entity_id
    end
  end

  # --- WHERE clause filtering ---

  test "where clause filtering still respects RLS" do
    with_entity_context(@entity1) do |conn|
      rows = conn.execute(
        "SELECT id FROM campaigns WHERE entity_id = #{@entity2.id}"
      ).to_a

      assert_empty rows, 'RLS should block access even with explicit entity_id filter'
    end
  end

  # --- COUNT queries ---

  test "count queries respect RLS" do
    with_entity_context(@entity1) do |conn|
      count = conn.execute("SELECT COUNT(*) as cnt FROM campaigns").first['cnt']
      assert count >= 1, 'Should see at least 1 campaign for entity 1'

      # Verify all counted records belong to entity 1
      entity_ids = conn.execute("SELECT DISTINCT entity_id FROM campaigns").to_a.map { |r| r['entity_id'] }
      assert_equal [@entity1.id], entity_ids, 'All campaigns should belong to entity 1'
    end

    without_entity_context do |conn|
      assert_equal 0, conn.execute("SELECT COUNT(*) as cnt FROM campaigns").first['cnt']
    end
  end

  # --- EXISTS queries ---

  test "exists queries respect RLS" do
    with_entity_context(@entity1) do |conn|
      e1 = conn.execute("SELECT EXISTS(SELECT 1 FROM campaigns WHERE id = #{@campaign1.id}) as ex").first['ex']
      e2 = conn.execute("SELECT EXISTS(SELECT 1 FROM campaigns WHERE id = #{@campaign2.id}) as ex").first['ex']

      assert e1, 'Should find entity 1 campaign'
      assert_not e2, 'Should not find entity 2 campaign'
    end
  end

  # --- Cross-table consistency ---

  test "RLS is consistent across multiple entity-scoped tables" do
    with_entity_context(@entity1) do |conn|
      campaign_ids = conn.execute("SELECT DISTINCT entity_id FROM campaigns").to_a.map { |r| r['entity_id'] }
      contact_ids = conn.execute("SELECT DISTINCT entity_id FROM contacts").to_a.map { |r| r['entity_id'] }
      page_ids = conn.execute("SELECT DISTINCT entity_id FROM landing_pages").to_a.map { |r| r['entity_id'] }

      assert_equal [@entity1.id], campaign_ids, 'All campaigns should belong to entity 1'
      assert_equal [@entity1.id], contact_ids, 'All contacts should belong to entity 1'
      assert_equal [@entity1.id], page_ids, 'All landing pages should belong to entity 1'
    end

    with_entity_context(@entity2) do |conn|
      campaign_ids = conn.execute("SELECT DISTINCT entity_id FROM campaigns").to_a.map { |r| r['entity_id'] }
      contact_ids = conn.execute("SELECT DISTINCT entity_id FROM contacts").to_a.map { |r| r['entity_id'] }
      page_ids = conn.execute("SELECT DISTINCT entity_id FROM landing_pages").to_a.map { |r| r['entity_id'] }

      assert_equal [@entity2.id], campaign_ids, 'All campaigns should belong to entity 2'
      assert_equal [@entity2.id], contact_ids, 'All contacts should belong to entity 2'
      assert_equal [@entity2.id], page_ids, 'All landing pages should belong to entity 2'
    end
  end
end
