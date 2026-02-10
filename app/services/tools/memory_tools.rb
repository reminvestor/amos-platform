# Memory Tools for Scout
#
# Simplified memory interface (inspired by OpenClaw's 2-tool pattern):
#   - remember_this: Store anything the user asks you to remember
#   - search_memory: Search past conversations, bookmarks, and stored memories
#
# Previous tools (bookmark_this, recall_context, list_saved) have been folded
# into search_memory with an `action` parameter. The model now has fewer tools
# to choose from, reducing decision fatigue.
#
module Tools
  class MemoryTools
    def self.definitions
      [
        remember_this_definition,
        search_memory_definition
      ]
    end

    def self.remember_this_definition
      {
        name: "remember_this",
        description: "Store something the user explicitly asks you to remember. Use when user says 'remember that...', 'don't forget...', 'keep in mind...', 'note that...', 'always...', 'never...'. Also use to bookmark/save a specific output for later retrieval (set action='bookmark'). This is HIGH PRIORITY - users explicitly asking you to remember something is important!",
        input_schema: {
          type: "object",
          properties: {
            content: {
              type: "string",
              description: "What the user wants you to remember - include the full context"
            },
            context: {
              type: "string",
              description: "Additional context about when/why this should be remembered"
            },
            action: {
              type: "string",
              enum: ["remember", "bookmark"],
              description: "Action type: 'remember' (default) stores a fact/preference/pattern. 'bookmark' saves the most recent response for later retrieval."
            },
            title: {
              type: "string",
              description: "Title for the bookmark (required when action='bookmark')"
            }
          },
          required: ["content"]
        }
      }
    end

    def self.search_memory_definition
      {
        name: "search_memory",
        description: "Search through past conversation history, stored memories, and bookmarks. Use when user asks about past discussions, wants to recall something, or wants to see saved items. Covers: searching past conversations, recalling context, listing bookmarks.",
        input_schema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "What to search for in past conversations and memories. Leave empty to list saved bookmarks."
            },
            scope: {
              type: "string",
              enum: ["all", "conversations", "bookmarks", "memories"],
              description: "Where to search: 'all' (default) searches everything, 'conversations' for past messages, 'bookmarks' for saved items, 'memories' for stored facts/preferences."
            },
            time_range: {
              type: "string",
              enum: ["today", "this_week", "this_month", "all"],
              description: "Time range to search within (default: all)"
            },
            bookmark_id: {
              type: "integer",
              description: "Jump to a specific bookmark by ID (for restoring saved context)"
            }
          },
          required: []
        }
      }
    end

    # ═══════════════════════════════════════════════════════════════
    # TOOL EXECUTION
    # ═══════════════════════════════════════════════════════════════

    def initialize(context)
      @user = context[:user]
      @entity = context[:entity]
      @memory = Scout::UnifiedMemory.new(user: @user, entity: @entity)
    end

    def execute(tool_name, params)
      case tool_name
      when "remember_this"
        execute_remember_this(params)
      when "search_memory"
        execute_search_memory(params)
      # Backward compatibility: old tool names route to new implementations
      when "bookmark_this"
        execute_remember_this(params.merge("action" => "bookmark", "content" => params["title"] || "Bookmarked output"))
      when "recall_context"
        execute_search_memory(params.merge("scope" => "bookmarks"))
      when "list_saved"
        execute_search_memory(params.merge("scope" => "bookmarks", "query" => ""))
      else
        { success: false, error: "Unknown memory tool: #{tool_name}" }
      end
    end

    def execute_remember_this(params)
      content = params["content"]
      context = params["context"]
      action = params["action"] || "remember"

      unless @user.present? && @entity.present?
        return { success: false, error: "Authentication required" }
      end

      unless content.present?
        return { success: false, error: "Nothing to remember" }
      end

      # Bookmark action: save the most recent response for later retrieval
      if action == "bookmark"
        return execute_bookmark(params)
      end

      # Remember action: analyze and store in the appropriate model
      analyzer = Scout::MemoryAnalyzer.new(user: @user, entity: @entity)
      result = analyzer.analyze_and_store(
        content: content,
        context: context,
        source: 'explicit'
      )

      if result[:success]
        category_labels = {
          user_preference: "preference",
          business_fact: "business fact",
          business_decision: "business decision",
          workflow_pattern: "workflow pattern",
          contact_info: "contact info",
          important_date: "important date",
          goal: "goal",
          important_memory: "important note"
        }

        category_label = category_labels[result[:category]] || "memory"

        {
          success: true,
          message: result[:message],
          category: category_label,
          stored_as: result[:storage]
        }
      else
        { success: false, error: result[:error] || "Failed to store memory" }
      end
    end

    private

    def execute_bookmark(params)
      title = params["title"] || params["content"]&.truncate(60) || "Saved output"
      description = params["context"] || params["description"]
      shareable = params["shareable"] || false

      # Get the most recent assistant message (what we're saving)
      # SECURITY: Scoped by user_id AND entity_id
      recent_message = ScoutMessage.where(user_id: @user.id, entity_id: @entity.id)
                                   .where(role: 'assistant')
                                   .order(created_at: :desc)
                                   .first

      unless recent_message
        return { success: false, error: "No recent output to save" }
      end

      bookmark = @memory.save_bookmark(
        message_id: recent_message.id,
        title: title,
        description: description,
        shareable: shareable
      )

      if bookmark
        result = {
          success: true,
          message: "Saved \"#{title}\" to your bookmarks",
          bookmark_id: bookmark.id
        }

        if shareable && bookmark.respond_to?(:share_url) && bookmark.share_url
          result[:share_url] = bookmark.share_url
          result[:message] += "\nShare link: #{bookmark.share_url}"
        end

        result
      else
        { success: false, error: "Failed to save bookmark" }
      end
    end

    def execute_search_memory(params)
      query = params["query"].to_s.strip
      scope = params["scope"] || "all"
      time_range = params["time_range"] || "all"
      bookmark_id = params["bookmark_id"]

      # Jump to a specific bookmark
      if bookmark_id.present?
        context = @memory.reset_to_bookmark(bookmark_id)
        if context
          return { success: true, message: "Context restored from bookmark", context: context }
        else
          return { success: false, error: "Bookmark not found" }
        end
      end

      # List bookmarks if query is empty and scope is bookmarks
      if query.blank? && scope == "bookmarks"
        return list_bookmarks
      end

      # Search with empty query across all scopes -> return recent bookmarks + summary
      if query.blank?
        return list_bookmarks
      end

      # Search across the requested scope
      results = []
      message_parts = []

      # Search conversations (L2 + L3 + L4)
      if %w[all conversations].include?(scope)
        conv_results = search_conversations(query, time_range)
        results.concat(conv_results[:results]) if conv_results[:results].any?
        message_parts << conv_results[:formatted] if conv_results[:formatted].present?
      end

      # Search stored memories (UserMemory, ScoutLearning, BusinessInsight)
      if %w[all memories].include?(scope)
        mem_results = search_stored_memories(query)
        results.concat(mem_results[:results]) if mem_results[:results].any?
        message_parts << mem_results[:formatted] if mem_results[:formatted].present?
      end

      # Search bookmarks
      if %w[all bookmarks].include?(scope)
        bm_results = search_bookmarks(query)
        results.concat(bm_results[:results]) if bm_results[:results].any?
        message_parts << bm_results[:formatted] if bm_results[:formatted].present?
      end

      if message_parts.empty?
        return {
          success: true,
          message: "No results found matching \"#{query}\".",
          results: []
        }
      end

      {
        success: true,
        message: "Found in your memory:\n\n#{message_parts.join("\n\n")}",
        results: results
      }
    end

    # ═══════════════════════════════════════════════════════════════
    # SEARCH HELPERS
    # ═══════════════════════════════════════════════════════════════

    def search_conversations(query, time_range)
      # Search L2 (recent messages via keyword)
      results = @memory.search_l2(keywords: query.split(/\s+/), limit: 5)

      # Also search memory segments (L3)
      segments = []
      if defined?(MemorySegment)
        segments = MemorySegment.where(user_id: @user.id, entity_id: @entity.id)
                                .where(active: true)
                                .where("summary ILIKE ? OR key_topics ILIKE ?", "%#{query}%", "%#{query}%")
                                .order(period_end: :desc)
                                .limit(3)
                                .to_a
      end

      # Try L4 (RAG) if nothing found
      if results.empty? && segments.empty?
        l4_results = @memory.search_long_term_memory(query, limit: 5)
        results = l4_results if l4_results.any?
      end

      formatted_parts = []
      if results.any?
        formatted_parts << "**Recent messages:**\n" + results.first(3).map { |r|
          "- #{r[:content].to_s.truncate(150)} (#{format_time_ago(r[:timestamp])})"
        }.join("\n")
      end

      if segments.any?
        formatted_parts << "**Conversation summaries:**\n" + segments.map { |s|
          "- [#{s.respond_to?(:period_label) ? s.period_label : s.segment_type}] #{s.summary.to_s.truncate(150)}"
        }.join("\n")
      end

      {
        results: results + segments.map { |s| { type: :segment, summary: s.summary, period: s.segment_type } },
        formatted: formatted_parts.any? ? formatted_parts.join("\n") : nil
      }
    end

    def search_stored_memories(query)
      results = []
      formatted_parts = []

      # Search UserMemory
      if defined?(UserMemory)
        user_mems = UserMemory.where(user: @user, entity: @entity)
                              .active
                              .where("content ILIKE ?", "%#{query}%")
                              .order(confidence: :desc)
                              .limit(5)
                              .to_a

        if user_mems.any?
          results.concat(user_mems.map { |m| { type: :user_memory, content: m.content, memory_type: m.memory_type } })
          formatted_parts << "**Stored memories:**\n" + user_mems.map { |m|
            "- [#{m.memory_type}] #{m.content.truncate(150)}"
          }.join("\n")
        end
      end

      # Search ScoutLearning
      if defined?(ScoutLearning)
        learnings = ScoutLearning.where(entity: @entity)
                                 .active
                                 .where("learning ILIKE ?", "%#{query}%")
                                 .order(confidence: :desc)
                                 .limit(3)
                                 .to_a

        if learnings.any?
          results.concat(learnings.map { |l| { type: :learning, content: l.learning } })
          formatted_parts << "**Learned patterns:**\n" + learnings.map { |l|
            "- #{l.learning.truncate(150)}"
          }.join("\n")
        end
      end

      {
        results: results,
        formatted: formatted_parts.any? ? formatted_parts.join("\n") : nil
      }
    end

    def search_bookmarks(query)
      return { results: [], formatted: nil } unless defined?(MemoryBookmark)

      bookmarks = MemoryBookmark.where(user_id: @user.id, entity_id: @entity.id)
                                .where("title ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%")
                                .order(created_at: :desc)
                                .limit(5)
                                .to_a

      return { results: [], formatted: nil } if bookmarks.empty?

      {
        results: bookmarks.map { |b| { type: :bookmark, id: b.id, title: b.title } },
        formatted: "**Bookmarks:**\n" + bookmarks.map { |b|
          "- #{b.title} (#{format_time_ago(b.created_at)})"
        }.join("\n")
      }
    end

    def list_bookmarks
      bookmarks = @memory.list_bookmarks(limit: 10)

      if bookmarks.empty?
        return {
          success: true,
          message: "You don't have any saved items yet. Say \"save this\" or \"remember that\" to start!",
          bookmarks: []
        }
      end

      formatted = bookmarks.map.with_index do |b, idx|
        share_info = b[:shareable] ? " (shareable)" : ""
        "#{idx + 1}. **#{b[:title]}**#{share_info}\n   #{b[:description] || 'No description'} - #{format_time_ago(b[:created_at])}"
      end

      {
        success: true,
        message: "Your saved items (#{bookmarks.count}):\n\n#{formatted.join("\n\n")}\n\nSay \"go back to [title]\" to restore that context.",
        bookmarks: bookmarks
      }
    end

    def format_time_ago(timestamp)
      return "unknown" unless timestamp

      time = timestamp.is_a?(String) ? Time.parse(timestamp) : timestamp
      seconds = (Time.current - time).to_i

      case seconds
      when 0..59 then "just now"
      when 60..3599 then "#{seconds / 60}m ago"
      when 3600..86399 then "#{seconds / 3600}h ago"
      when 86400..604799 then "#{seconds / 86400}d ago"
      else time.strftime('%b %d')
      end
    rescue
      "unknown"
    end
  end
end
