require "test_helper"

class Amos::ConversationContextTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # ConversationContext Tests - Context management and caching
  # ═══════════════════════════════════════════════════════════════════════════
  
  setup do
    @entity = entities(:one)
    @user = create_valid_user(entity: @entity)
    @session_id = SecureRandom.uuid
  end
  
  # ─────────────────────────────────────────────────────────────────────────────
  # Basic Initialization
  # ─────────────────────────────────────────────────────────────────────────────
  
  test "initializes with session, user, and entity" do
    context = Amos::ConversationContext.new(@session_id, @user, @entity)
    
    assert_equal @session_id, context.session_id
    assert_equal @user, context.user
    assert_equal @entity, context.entity
  end
  
  # ─────────────────────────────────────────────────────────────────────────────
  # Message Management
  # ─────────────────────────────────────────────────────────────────────────────
  
  test "adds messages to context" do
    context = Amos::ConversationContext.new(@session_id, @user, @entity)
    
    context.add_message(:user, "Hello")
    context.add_message(:assistant, "Hi there!")
    
    messages = context.recent_messages(10)
    assert_equal 2, messages.length
    assert_equal "user", messages[0][:role]
    assert_equal "Hello", messages[0][:content]
    assert_equal "assistant", messages[1][:role]
    assert_equal "Hi there!", messages[1][:content]
  end
  
  test "limits messages to last 50" do
    context = Amos::ConversationContext.new(@session_id, @user, @entity)
    
    60.times { |i| context.add_message(:user, "Message #{i}") }
    
    # Should have trimmed to 50
    assert_equal 50, context.messages.length
  end
  
  test "handles ActionController::Parameters in metadata" do
    context = Amos::ConversationContext.new(@session_id, @user, @entity)
    
    # ActionController::Parameters must be permitted before conversion
    params = ActionController::Parameters.new({ canvas: "dashboard", voice: true })
    params.permit!  # Permit all params for test
    context.add_message(:user, "Test", params)
    
    messages = context.recent_messages(1)
    assert messages[0][:metadata].is_a?(Hash)
    assert_equal "dashboard", messages[0][:metadata][:canvas]
  end
  
  # ─────────────────────────────────────────────────────────────────────────────
  # Entity Snapshot Caching
  # ─────────────────────────────────────────────────────────────────────────────
  
  test "entity_snapshot returns entity data" do
    context = Amos::ConversationContext.new(@session_id, @user, @entity)
    
    snapshot = context.entity_snapshot
    
    assert_equal @entity.name, snapshot[:name]
    assert_equal @entity.subdomain, snapshot[:subdomain]
    assert snapshot.key?(:has_stripe)
    assert snapshot.key?(:landing_pages_count)
    assert snapshot.key?(:contacts_count)
  end
  
  test "entity_snapshot is cached" do
    # Use memory store for this test to verify caching behavior
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    
    begin
      context = Amos::ConversationContext.new(@session_id, @user, @entity)
      
      # Clear any existing cache
      Rails.cache.delete("entity_snapshot:#{@entity.id}")
      
      # First call should hit database
      snapshot1 = context.entity_snapshot
      
      # Second call should use cache (verify by checking cache exists)
      assert Rails.cache.exist?("entity_snapshot:#{@entity.id}"), "Cache should exist after first call"
      
      snapshot2 = context.entity_snapshot
      
      # Results should be identical
      assert_equal snapshot1, snapshot2
    ensure
      Rails.cache = original_cache
    end
  end
  
  test "entity_snapshot cache expires after 2 minutes" do
    # Use memory store for this test to verify caching behavior
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    
    begin
      context = Amos::ConversationContext.new(@session_id, @user, @entity)
      
      # Clear cache and get snapshot
      Rails.cache.delete("entity_snapshot:#{@entity.id}")
      context.entity_snapshot
      
      # Cache should exist
      assert Rails.cache.exist?("entity_snapshot:#{@entity.id}"), "Cache should exist after first call"
      
      # Travel forward 3 minutes
      travel 3.minutes do
        # Cache should have expired
        assert_not Rails.cache.exist?("entity_snapshot:#{@entity.id}"), "Cache should expire after 2 minutes"
      end
    ensure
      Rails.cache = original_cache
    end
  end
  
  # ─────────────────────────────────────────────────────────────────────────────
  # Snapshot Generation
  # ─────────────────────────────────────────────────────────────────────────────
  
  test "snapshot includes all required fields" do
    context = Amos::ConversationContext.new(@session_id, @user, @entity)
    context.add_message(:user, "Test message")
    
    snapshot = context.snapshot
    
    assert_equal @session_id, snapshot[:session_id]
    assert_equal @user.id, snapshot[:user_id]
    assert_equal @entity.id, snapshot[:entity_id]
    assert snapshot[:recent_messages].is_a?(Array)
    assert snapshot[:entity_context].is_a?(Hash)
    assert snapshot[:timestamp].present?
  end
  
  # ─────────────────────────────────────────────────────────────────────────────
  # Fresh Start Filtering
  # ─────────────────────────────────────────────────────────────────────────────
  
  test "respects fresh_start_at filter" do
    # Create some scout messages before fresh start
    old_message = ScoutMessage.create!(
      session_id: @session_id,
      user: @user,
      entity: @entity,
      role: "user",
      content: "Old message",
      created_at: 10.minutes.ago
    )
    
    fresh_start_time = 5.minutes.ago
    
    # Create message after fresh start
    new_message = ScoutMessage.create!(
      session_id: @session_id,
      user: @user,
      entity: @entity,
      role: "user",
      content: "New message",
      created_at: 2.minutes.ago
    )
    
    context = Amos::ConversationContext.new(@session_id, @user, @entity, fresh_start_at: fresh_start_time)
    
    # Should only have the new message
    messages = context.recent_messages(10)
    assert_equal 1, messages.length
    assert_equal "New message", messages[0][:content]
  end
  
  # ─────────────────────────────────────────────────────────────────────────────
  # Workflow Management
  # ─────────────────────────────────────────────────────────────────────────────
  
  test "manages active workflows" do
    context = Amos::ConversationContext.new(@session_id, @user, @entity)
    
    assert_not context.has_active_workflow?
    
    context.set_active_workflow("job123", { type: "landing_page", status: "running" })
    
    assert context.has_active_workflow?
    assert_equal "job123", context.active_workflow[:job_id]
    
    context.clear_workflow("job123")
    
    assert_not context.has_active_workflow?
  end
end
