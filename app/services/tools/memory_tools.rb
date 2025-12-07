# Memory Tools for Scout
#
# These tools allow Scout to interact with the unified memory system:
# - save_to_memory: Save important outputs for the user
# - recall_context: Jump to a past conversation context
# - list_saved: Show user's saved items
# - search_memory: Search past conversations
#
module Tools
  class MemoryTools
    def self.definitions
      [
        remember_this_definition,
        save_to_memory_definition,
        recall_context_definition,
        list_saved_definition,
        search_memory_definition
      ]
    end

    def self.remember_this_definition
      {
        name: "remember_this",
        description: "Store something the user explicitly asks you to remember. Use when user says 'remember that...', 'don't forget...', 'keep in mind...', 'note that...', 'always...', 'never...'. Analyzes the content and stores it in the most appropriate place (preferences, business facts, workflow patterns, etc.). This is HIGH PRIORITY - users explicitly asking you to remember something is important!",
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
            }
          },
          required: ["content"]
        }
      }
    end

    def self.save_to_memory_definition
      {
        name: "save_to_memory",
        description: "Save an important output, response, or conversation point for the user. Creates a bookmark they can revisit later or share. Use when user says 'save this', 'remember this', 'I want to come back to this', or when you produce something valuable they'll want to reference.",
        input_schema: {
          type: "object",
          properties: {
            title: {
              type: "string",
              description: "A short, descriptive title for the saved item (e.g., 'Email Campaign Strategy', 'Q4 Budget Analysis')"
            },
            description: {
              type: "string",
              description: "Brief description of what's being saved and why it's valuable"
            },
            shareable: {
              type: "boolean",
              description: "Whether to create a shareable link. Default false."
            }
          },
          required: ["title"]
        }
      }
    end

    def self.recall_context_definition
      {
        name: "recall_context",
        description: "Jump back to a previous conversation context or topic. Use when user says 'go back to when we discussed X', 'what did we talk about regarding Y', 'remember that conversation about Z'. Restores relevant context to continue from that point.",
        input_schema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "What context to find - can be a topic, keyword, or description like 'the landing page we designed' or 'last week's marketing discussion'"
            },
            bookmark_id: {
              type: "integer",
              description: "Specific bookmark ID to jump to (if user selected from list)"
            }
          },
          required: []
        }
      }
    end

    def self.list_saved_definition
      {
        name: "list_saved",
        description: "Show the user's saved conversation bookmarks and outputs. Use when user asks 'show my saved items', 'what have I saved', 'my bookmarks'.",
        input_schema: {
          type: "object",
          properties: {
            limit: {
              type: "integer",
              description: "Number of items to show (default 10)"
            }
          },
          required: []
        }
      }
    end

    def self.search_memory_definition
      {
        name: "search_memory",
        description: "Search through past conversation history for specific topics or information. Use when user asks about past discussions but doesn't need to fully restore context - just needs to find specific information.",
        input_schema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "What to search for in past conversations"
            },
            time_range: {
              type: "string",
              enum: ["today", "this_week", "this_month", "all"],
              description: "Time range to search within (default: all)"
            }
          },
          required: ["query"]
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
      when "save_to_memory"
        execute_save_to_memory(params)
      when "recall_context"
        execute_recall_context(params)
      when "list_saved"
        execute_list_saved(params)
      when "search_memory"
        execute_search_memory(params)
      else
        { success: false, error: "Unknown memory tool: #{tool_name}" }
      end
    end

    def execute_remember_this(params)
      content = params["content"]
      context = params["context"]

      unless @user.present? && @entity.present?
        return { success: false, error: "Authentication required" }
      end

      unless content.present?
        return { success: false, error: "Nothing to remember" }
      end

      # Use the memory analyzer to figure out where to store this
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

    def execute_save_to_memory(params)
      title = params["title"]
      description = params["description"]
      shareable = params["shareable"] || false

      # SECURITY: Validate user and entity are present
      unless @user.present? && @entity.present?
        return { success: false, error: "Authentication required" }
      end

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
          message: "✅ Saved \"#{title}\" to your memory",
          bookmark_id: bookmark.id
        }

        if shareable && bookmark.share_url
          result[:share_url] = bookmark.share_url
          result[:message] += "\n📤 Share link: #{bookmark.share_url}"
        end

        result
      else
        { success: false, error: "Failed to save bookmark" }
      end
    end

    def execute_recall_context(params)
      if params["bookmark_id"].present?
        # Jump to specific bookmark
        context = @memory.reset_to_bookmark(params["bookmark_id"])
        if context
          { 
            success: true, 
            message: "📍 Context restored from bookmark",
            context: context 
          }
        else
          { success: false, error: "Bookmark not found" }
        end
      elsif params["query"].present?
        # Search for context
        results = @memory.jump_to_context(params["query"])
        if results.present?
          {
            success: true,
            message: "📍 Found relevant context for \"#{params['query']}\"",
            results: results
          }
        else
          { 
            success: false, 
            message: "Couldn't find past context matching \"#{params['query']}\". Try different keywords or check your saved items." 
          }
        end
      else
        { success: false, error: "Please specify what context to recall" }
      end
    end

    def execute_list_saved(params)
      limit = params["limit"] || 10
      bookmarks = @memory.list_bookmarks(limit: limit)

      if bookmarks.empty?
        {
          success: true,
          message: "You don't have any saved items yet. Say \"save this\" after any response you want to keep!",
          bookmarks: []
        }
      else
        formatted = bookmarks.map.with_index do |b, idx|
          share_info = b[:shareable] ? " 📤" : ""
          "#{idx + 1}. **#{b[:title]}**#{share_info}\n   #{b[:description] || 'No description'} • #{format_time_ago(b[:created_at])}"
        end

        {
          success: true,
          message: "📚 **Your Saved Items** (#{bookmarks.count})\n\n#{formatted.join("\n\n")}\n\n*Say \"go back to [title]\" to restore that context.*",
          bookmarks: bookmarks
        }
      end
    end

    def execute_search_memory(params)
      query = params["query"]
      time_range = params["time_range"] || "all"

      # Search L2 first (recent, fast)
      results = @memory.search_l2(keywords: query.split(/\s+/), limit: 5)

      # Also search memory segments
      segments = MemorySegment.where(user_id: @user.id, entity_id: @entity.id)
                              .where(active: true)
                              .where("summary ILIKE ? OR key_topics ILIKE ?", "%#{query}%", "%#{query}%")
                              .order(period_end: :desc)
                              .limit(3)

      if results.empty? && segments.empty?
        # Try L4 (RAG search)
        l4_results = @memory.search_long_term_memory(query, limit: 5)
        
        if l4_results.empty?
          return {
            success: true,
            message: "No past discussions found matching \"#{query}\".",
            results: []
          }
        else
          results = l4_results
        end
      end

      # Format results
      formatted_messages = results.first(3).map do |r|
        "• #{r[:content].truncate(150)} (#{format_time_ago(r[:timestamp])})"
      end

      formatted_segments = segments.map do |s|
        "• [#{s.period_label}] #{s.summary.truncate(150)}"
      end

      message_parts = ["🔍 **Found in your conversation history:**"]
      
      if formatted_messages.any?
        message_parts << "\n**Recent messages:**\n#{formatted_messages.join("\n")}"
      end
      
      if formatted_segments.any?
        message_parts << "\n**From memory summaries:**\n#{formatted_segments.join("\n")}"
      end

      {
        success: true,
        message: message_parts.join("\n"),
        results: results,
        segments: segments.map(&:to_summary_hash)
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
