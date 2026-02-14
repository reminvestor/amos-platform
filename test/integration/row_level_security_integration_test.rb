# frozen_string_literal: true

require 'test_helper'

class RowLevelSecurityIntegrationTest < ActionDispatch::IntegrationTest
  include RowLevelSecurityHelper

  setup do
    ensure_rls_enabled!

    @entity1 = entities(:one)
    @entity2 = entities(:two)

    # Create users - api_key is auto-generated via before_create
    @user1 = User.create!(
      email: "rls_int_user1_#{SecureRandom.hex(4)}@entity1.com",
      password: 'TestPassword123!',
      password_confirmation: 'TestPassword123!',
      entity: @entity1
    )

    @user2 = User.create!(
      email: "rls_int_user2_#{SecureRandom.hex(4)}@entity2.com",
      password: 'TestPassword123!',
      password_confirmation: 'TestPassword123!',
      entity: @entity2
    )

    # Create test data for each entity
    @campaign1 = Campaign.create!(
      name: 'RLS Int Entity 1 Campaign',
      entity: @entity1,
      user: @user1,
      description: 'Test Description 1',
      status: 'draft'
    )

    @campaign2 = Campaign.create!(
      name: 'RLS Int Entity 2 Campaign',
      entity: @entity2,
      user: @user2,
      description: 'Test Description 2',
      status: 'draft'
    )

    @contact1 = Contact.create!(
      email: "rls_int_c1_#{SecureRandom.hex(4)}@entity1.com",
      entity: @entity1,
      user: @user1,
      first_name: 'IntContact',
      last_name: 'One'
    )

    @contact2 = Contact.create!(
      email: "rls_int_c2_#{SecureRandom.hex(4)}@entity2.com",
      entity: @entity2,
      user: @user2,
      first_name: 'IntContact',
      last_name: 'Two'
    )
  end

  teardown do
    Contact.where(id: [@contact1&.id, @contact2&.id].compact).delete_all
    Campaign.where(id: [@campaign1&.id, @campaign2&.id].compact).delete_all
    Campaign.where(name: 'RLS Int Hacked Campaign').delete_all
    [@user1, @user2].compact.each do |user|
      ActiveRecord::Base.connection.execute(
        "DELETE FROM entity_users WHERE user_id = #{user.id}"
      ) rescue nil
      user.destroy rescue nil
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Campaign API - Cross-entity access tests
  # ═══════════════════════════════════════════════════════════════

  test "user can list own entity campaigns via API" do
    get api_v1_campaigns_url, headers: auth_headers(@user1)

    assert_response :success
    data = JSON.parse(response.body)['data']
    campaign_ids = data.map { |c| c['id'] }

    assert_includes campaign_ids, @campaign1.id, 'Should see entity 1 campaign'
    assert_not_includes campaign_ids, @campaign2.id, 'Should NOT see entity 2 campaign'
  end

  test "user cannot fetch specific campaign from other entity via API" do
    get api_v1_campaign_url(@campaign2), headers: auth_headers(@user1)

    assert_response :not_found
  end

  test "user can fetch specific campaign from same entity via API" do
    get api_v1_campaign_url(@campaign1), headers: auth_headers(@user1)

    assert_response :success
    campaign = JSON.parse(response.body)
    assert_equal @campaign1.id, campaign['id']
  end

  test "user cannot update campaign from other entity via API" do
    patch api_v1_campaign_url(@campaign2),
          headers: auth_headers(@user1),
          params: { name: 'Hacked Name' }

    assert_response :not_found
  end

  test "user can update campaign from same entity via API" do
    patch api_v1_campaign_url(@campaign1),
          headers: auth_headers(@user1),
          params: { name: 'Updated Campaign Name' }

    assert_response :success
    campaign = JSON.parse(response.body)
    assert_equal 'Updated Campaign Name', campaign['name']
  end

  test "user cannot delete campaign from other entity via API" do
    delete api_v1_campaign_url(@campaign2), headers: auth_headers(@user1)

    assert_response :not_found
    assert Campaign.exists?(@campaign2.id), 'Campaign should not be deleted'
  end

  test "user can delete campaign from same entity via API" do
    delete api_v1_campaign_url(@campaign1), headers: auth_headers(@user1)

    assert_response :no_content
    assert_not Campaign.exists?(@campaign1.id), 'Campaign should be deleted'
    @campaign1 = nil
  end

  # ═══════════════════════════════════════════════════════════════
  # Authentication tests
  # ═══════════════════════════════════════════════════════════════

  test "unauthenticated requests are rejected" do
    get api_v1_campaigns_url

    assert_response :unauthorized
  end

  test "invalid token is rejected" do
    get api_v1_campaigns_url, headers: {
      'Authorization' => 'Bearer invalid_token_12345'
    }

    assert_response :unauthorized
  end

  # ═══════════════════════════════════════════════════════════════
  # Cross-request isolation
  # ═══════════════════════════════════════════════════════════════

  test "RLS context is isolated between requests from different users" do
    # Request 1: User 1
    get api_v1_campaigns_url, headers: auth_headers(@user1)
    assert_response :success
    campaigns1 = JSON.parse(response.body)['data']

    # Request 2: User 2
    get api_v1_campaigns_url, headers: auth_headers(@user2)
    assert_response :success
    campaigns2 = JSON.parse(response.body)['data']

    # User 1 should only see entity 1 campaigns
    campaign_ids_1 = campaigns1.map { |c| c['id'] }
    assert_includes campaign_ids_1, @campaign1.id
    assert_not_includes campaign_ids_1, @campaign2.id

    # User 2 should only see entity 2 campaigns
    campaign_ids_2 = campaigns2.map { |c| c['id'] }
    assert_includes campaign_ids_2, @campaign2.id
    assert_not_includes campaign_ids_2, @campaign1.id
  end

  test "sequential requests from same user consistently return correct data" do
    3.times do
      get api_v1_campaigns_url, headers: auth_headers(@user1)
      assert_response :success
      data = JSON.parse(response.body)['data']
      campaign_ids = data.map { |c| c['id'] }

      assert_includes campaign_ids, @campaign1.id
      assert_not_includes campaign_ids, @campaign2.id
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Entity ID manipulation attempts
  # ═══════════════════════════════════════════════════════════════

  test "campaign creation is scoped to authenticated user entity" do
    post api_v1_campaigns_url,
         headers: auth_headers(@user1),
         params: {
           name: 'RLS Int Hacked Campaign',
           description: 'Attempting entity injection',
           status: 'draft',
           entity_id: @entity2.id  # Attempt to set other entity
         }

    if response.successful?
      campaign = JSON.parse(response.body)
      # Even if entity_id param is passed, it should be forced to user's entity
      created = Campaign.find(campaign['id'])
      assert_equal @entity1.id, created.entity_id, 'Campaign should belong to user entity, not injected entity'
      Campaign.where(id: created.id).delete_all
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Database-level RLS verification (defense-in-depth)
  # ═══════════════════════════════════════════════════════════════

  test "RLS blocks access at database level even with direct SQL" do
    with_entity_context(@entity1) do |conn|
      # Try to access entity 2 campaign via direct SQL
      rows = conn.execute("SELECT id FROM campaigns WHERE id = #{@campaign2.id}").to_a
      assert_empty rows, 'RLS should block direct SQL access to other entity data'

      # Try to access with explicit entity_id filter
      rows = conn.execute("SELECT id FROM campaigns WHERE entity_id = #{@entity2.id}").to_a
      assert_empty rows, 'RLS should block even with explicit entity_id filter'
    end
  end

  test "RLS denies all access without entity context" do
    without_entity_context do |conn|
      count = conn.execute("SELECT COUNT(*) as cnt FROM campaigns").first['cnt']
      assert_equal 0, count, 'No campaigns should be visible without entity context'
    end
  end

  private

  def auth_headers(user)
    { 'Authorization' => "Bearer #{user.api_key}" }
  end
end
