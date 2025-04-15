class ApplyLandingPageChangeJob < ApplicationJob
  include JobErrorHandling
  queue_as :default

  def perform(landing_page_id, instruction, entity_id, user_id, **options)
    # Extract options
    conversation_history = options[:conversation_history] || []
    message_id = options[:message_id]
    correlation_id = options[:correlation_id] || SecureRandom.uuid
    section_index = options[:section_index]
    
    # Set up correlation ID for tracking
    @correlation_id = correlation_id
    Rails.logger.info("[#{@correlation_id}] ApplyLandingPageChangeJob started with params: #{landing_page_id}, '#{instruction.truncate(30, omission: '...')}', #{entity_id}, #{user_id}")
    Rails.logger.info("[#{@correlation_id}] Targeting section index: #{section_index || 'general edit'}")

    # Load necessary data
    landing_page = LandingPage.find_by(id: landing_page_id)
    unless landing_page
      Rails.logger.error("[#{@correlation_id}] Landing page not found with ID: #{landing_page_id}")
      raise "Landing page not found"
    end
    
    user = User.find_by(id: user_id)
    
    # Configure AI agent
    agent = AiAgents::LandingPageEditAgent.new(
      landing_page: landing_page,
      entity_id: entity_id,
      user_id: user_id,
      instruction: instruction,
      conversation_history: conversation_history,
      section_index: section_index
    )

    # Execute the agent to modify the landing page
    Rails.logger.info("[#{@correlation_id}] Executing AI agent to modify landing page")
    result = agent.execute

    if result[:success]
      Rails.logger.info("[#{@correlation_id}] Successfully applied changes to landing page: #{landing_page.id}")
      
      # Log the AI response
      Rails.logger.info("[#{@correlation_id}] AI response: #{result[:ai_response]}")
      
      # Store the AI response as a message
      if user.present?
        landing_page.landing_page_chat_messages.create!(
          content: result[:ai_message] || "I've applied your changes to the landing page.",
          role: 'assistant',
          user: user
        )
      end
      
      # Update the landing page if changes were returned
      if result[:updated_landing_page].present?
        # Create a version before applying changes
        Rails.logger.info("[#{@correlation_id}] Creating version before applying changes")
        LandingPageVersion.create_from_landing_page(
          landing_page, 
          ai_applied: false, 
          description: "Version before AI changes: '#{instruction.truncate(50, omission: '...')}'"
        )
        
        # Handle the new_section key first if it exists
        if result[:updated_landing_page][:new_section].present? && !result[:updated_landing_page][:content].present?
          content = landing_page.content.deep_dup || []
          content << result[:updated_landing_page][:new_section]
          result[:updated_landing_page][:content] = content
          result[:updated_landing_page].delete(:new_section) # Remove the new_section key after processing
          Rails.logger.info("[#{@correlation_id}] Added new section to landing page content")
        end
        
        # Filter out any attributes that don't correspond to columns in the LandingPage model
        # Plus the content attribute which is stored as JSON
        allowed_attributes = landing_page.attributes.keys.map(&:to_sym) + [:content]
        filtered_updates = result[:updated_landing_page].select { |key, _| allowed_attributes.include?(key) }
        
        Rails.logger.info("[#{@correlation_id}] Applying filtered updates: #{filtered_updates.keys}")
        landing_page.update(filtered_updates)
        Rails.logger.info("[#{@correlation_id}] Updated landing page with new content")
        
        # Create a version after applying changes
        Rails.logger.info("[#{@correlation_id}] Creating version after applying changes")
        LandingPageVersion.create_from_landing_page(
          landing_page, 
          ai_applied: true, 
          description: "AI changes applied: '#{instruction.truncate(50, omission: '...')}'"
        )
      end
    else
      Rails.logger.error("[#{@correlation_id}] Failed to apply changes: #{result[:error]}")
      
      # Store error message
      if user.present?
        landing_page.landing_page_chat_messages.create!(
          content: "Sorry, I encountered an error while trying to apply your changes: #{result[:error]}",
          role: 'assistant',
          user: user
        )
      end
      
      raise result[:error]
    end

    Rails.logger.info("[#{@correlation_id}] ApplyLandingPageChangeJob completed")
  rescue StandardError => e
    Rails.logger.error("[#{@correlation_id}] Error in ApplyLandingPageChangeJob: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    
    # Store error message
    if defined?(landing_page) && landing_page.present? && defined?(user) && user.present?
      landing_page.landing_page_chat_messages.create!(
        content: "Sorry, an unexpected error occurred: #{e.message}",
        role: 'assistant',
        user: user
      )
    end
    
    raise
  end
end 