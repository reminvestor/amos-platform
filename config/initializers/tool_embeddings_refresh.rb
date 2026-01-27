# frozen_string_literal: true

# Smart tool embeddings cache refresh
#
# Only clears the ClassToolEmbeddingsService cache when new tools are detected.
# This avoids unnecessary embedding regeneration on every deploy while ensuring
# new tools are immediately discoverable.

Rails.application.config.after_initialize do
  # Only run in production/staging (not in console, rake tasks, or test)
  next unless Rails.env.production?
  next if Rails.const_defined?(:Console) || defined?(Rake)
  
  begin
    # Count current class tools
    tool_files = Dir[Rails.root.join("app/services/tools/*_tool.rb")]
    current_count = tool_files.reject { |f| File.basename(f) == "base_tool.rb" }.count
    
    # Get cached tool count
    cached_count_key = "class_tool_count_v1"
    cached_count = Rails.cache.read(cached_count_key)
    
    if cached_count.nil? || cached_count != current_count
      Rails.logger.info "🔄 Tool count changed (#{cached_count || 'unknown'} → #{current_count}) - refreshing embeddings cache"
      
      # Clear embeddings cache
      Rails.cache.delete("class_tool_embeddings_v1")
      
      # Store new count
      Rails.cache.write(cached_count_key, current_count, expires_in: 30.days)
      
      Rails.logger.info "✅ Tool embeddings cache cleared - will regenerate on first discovery"
    else
      Rails.logger.debug "📚 Tool count unchanged (#{current_count}) - keeping embeddings cache"
    end
  rescue => e
    Rails.logger.warn "⚠️ Tool embeddings check failed: #{e.message}"
  end
end
