# frozen_string_literal: true

module Amos
  # SessionFocus - Explicit tracking of what Amos is currently working on
  #
  # Instead of inferring focus from regex parsing of conversation content,
  # this service allows Amos to explicitly set and clear focus.
  #
  # Usage:
  #   focus = Amos::SessionFocus.new(session_id: session_id, user: user, entity: entity)
  #   
  #   # Set focus when starting work on something
  #   focus.set_focus(
  #     type: :landing_page,
  #     id: 123,
  #     name: "Fitness App Landing Page",
  #     context: { plan_id: 456, sections: ["hero", "features"] }
  #   )
  #   
  #   # Check current focus
  #   current = focus.get_focus
  #   # => { type: :landing_page, id: 123, name: "...", context: {...}, set_at: Time }
  #   
  #   # Clear focus when done or topic changes
  #   focus.clear_focus
  #   
  #   # Format for prompt injection
  #   focus.format_for_prompt
  #   # => "📌 CURRENT FOCUS: Landing Page #123 - Fitness App Landing Page"
  #
  class SessionFocus
    FOCUS_TTL = 30.minutes.to_i  # Focus expires after 30 mins of inactivity
    REDIS_PREFIX = "amos:focus"
    
    # Valid focus types
    FOCUS_TYPES = %i[
      landing_page
      website
      app
      canvas
      design_plan
      workflow
      email
      document
      contact
      campaign
      module
      integration
    ].freeze

    attr_reader :session_id, :user, :entity

    def initialize(session_id:, user: nil, entity: nil)
      @session_id = session_id
      @user = user
      @entity = entity
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CORE FOCUS OPERATIONS
    # ═══════════════════════════════════════════════════════════════════════════

    # Set the current focus
    # @param type [Symbol] One of FOCUS_TYPES
    # @param id [Integer] The ID of the focused item
    # @param name [String] Human-readable name
    # @param context [Hash] Additional context (plan_id, sections, etc.)
    def set_focus(type:, id:, name: nil, context: {})
      type_sym = type.to_sym
      unless FOCUS_TYPES.include?(type_sym)
        Rails.logger.warn "[SessionFocus] Invalid focus type: #{type}"
        return false
      end

      focus_data = {
        type: type_sym,
        id: id,
        name: name || "#{type_sym.to_s.titleize} ##{id}",
        context: context,
        set_at: Time.current.iso8601,
        user_id: @user&.id,
        entity_id: @entity&.id
      }

      $redis.setex(focus_key, FOCUS_TTL, focus_data.to_json)
      Rails.logger.info "📌 [SessionFocus] Set focus: #{type_sym} ##{id} - #{name}"
      
      true
    rescue => e
      Rails.logger.error "[SessionFocus] Failed to set focus: #{e.message}"
      false
    end

    # Get the current focus
    # @return [Hash, nil] Current focus data or nil if not set
    def get_focus
      data = $redis.get(focus_key)
      return nil unless data.present?

      parsed = JSON.parse(data, symbolize_names: true)
      
      # Ensure type is a symbol for consistent comparison
      parsed[:type] = parsed[:type].to_sym if parsed[:type].is_a?(String)
      
      # Refresh TTL on access (keep focus alive while being used)
      $redis.expire(focus_key, FOCUS_TTL)
      
      parsed
    rescue JSON::ParserError
      nil
    rescue => e
      Rails.logger.error "[SessionFocus] Failed to get focus: #{e.message}"
      nil
    end

    # Clear the current focus
    # @param reason [String] Optional reason for clearing (for logging)
    def clear_focus(reason: nil)
      existing = get_focus
      $redis.del(focus_key)
      
      if existing
        reason_msg = reason ? " (#{reason})" : ""
        Rails.logger.info "📌 [SessionFocus] Cleared focus: #{existing[:type]} ##{existing[:id]}#{reason_msg}"
      end
      
      true
    rescue => e
      Rails.logger.error "[SessionFocus] Failed to clear focus: #{e.message}"
      false
    end

    # Check if there's an active focus
    def focused?
      get_focus.present?
    end

    # Check if focused on a specific type
    def focused_on?(type)
      focus = get_focus
      focus && focus[:type] == type.to_sym
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PROMPT FORMATTING
    # ═══════════════════════════════════════════════════════════════════════════

    # Format current focus for injection into system prompt
    # @return [String] Formatted focus context or empty string
    def format_for_prompt
      focus = get_focus
      return "" unless focus

      type_label = focus[:type].to_s.titleize.gsub('_', ' ')
      
      parts = ["📌 CURRENT FOCUS: #{type_label} ##{focus[:id]}"]
      parts << "Name: #{focus[:name]}" if focus[:name].present?
      
      # Add relevant context
      if focus[:context].present?
        context = focus[:context]
        
        if context[:plan_id]
          parts << "Design Plan: ##{context[:plan_id]}"
        end
        
        if context[:sections].present?
          parts << "Sections: #{context[:sections].join(', ')}"
        end
        
        if context[:status]
          parts << "Status: #{context[:status]}"
        end
      end
      
      # Add how long we've been focused
      if focus[:set_at]
        set_time = Time.parse(focus[:set_at])
        duration = (Time.current - set_time).to_i
        if duration > 60
          mins = duration / 60
          parts << "Working on this for: #{mins} minute#{'s' if mins > 1}"
        end
      end

      <<~FOCUS
        ═══════════════════════════════════════════════════════════════
        #{parts.join("\n")}
        ═══════════════════════════════════════════════════════════════
      FOCUS
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CONVENIENCE METHODS
    # ═══════════════════════════════════════════════════════════════════════════

    # Set focus on a landing page
    def focus_on_landing_page(landing_page, plan: nil)
      context = {}
      context[:plan_id] = plan.id if plan.respond_to?(:id)
      context[:status] = landing_page.status if landing_page.respond_to?(:status)
      
      set_focus(
        type: :landing_page,
        id: landing_page.id,
        name: landing_page.respond_to?(:title) ? landing_page.title : nil,
        context: context
      )
    end

    # Set focus on a design plan
    def focus_on_design_plan(plan)
      sections = plan.sections.map { |s| s['name'] || s[:name] } rescue []
      
      set_focus(
        type: :design_plan,
        id: plan.id,
        name: plan.respond_to?(:name) ? plan.name : nil,
        context: {
          design_type: plan.respond_to?(:design_type) ? plan.design_type : nil,
          sections: sections,
          status: plan.respond_to?(:status) ? plan.status : nil
        }
      )
    end

    # Set focus on a document
    def focus_on_document(document)
      set_focus(
        type: :document,
        id: document.id,
        name: document.respond_to?(:filename) ? document.filename : nil,
        context: {
          content_type: document.respond_to?(:content_type) ? document.content_type : nil
        }
      )
    end

    # Update context without changing focus target
    def update_context(new_context)
      focus = get_focus
      return false unless focus

      merged_context = (focus[:context] || {}).merge(new_context)
      set_focus(
        type: focus[:type],
        id: focus[:id],
        name: focus[:name],
        context: merged_context
      )
    end

    private

    def focus_key
      "#{REDIS_PREFIX}:#{@session_id}"
    end
  end
end
