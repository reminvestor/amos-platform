module AiAgents
  class ContentAgent < BaseAgent
    def execute
      log_execution_start
      Rails.logger.info("ContentAgent: Starting content generation")

      # Get prompts for this agent
      prompts = context[:agent_prompts]&.dig("content") || []

      if prompts.empty?
        Rails.logger.error("ContentAgent: No prompts found for content generation")
        return context
      end

      Rails.logger.info("ContentAgent: Found #{prompts.size} content section prompts to process")

      results = []

      # Process each content prompt (could be for different sections)
      prompts.each_with_index do |task_data, idx|
        prompt = task_data[:prompt]
        section_index = task_data[:task_data][:section_index]
        output_key = task_data[:task_data][:output_keys].first
        section_type = task_data[:task_data][:section_type] || "text"

        Rails.logger.info("ContentAgent: Processing section #{idx+1}/#{prompts.size} - index #{section_index}, type #{section_type}")
        Rails.logger.debug("ContentAgent: Using prompt: #{prompt.truncate(200)}")

        # Generate the content for this section
        start_time = Time.current
        Rails.logger.info("ContentAgent: Calling OpenAI for section #{section_index}")
        response = call_openai_api(prompt)
        generation_time = Time.current - start_time
        Rails.logger.info("ContentAgent: OpenAI response received in #{generation_time.round(2)}s for section #{section_index}")

        begin
          # Find and parse JSON in the response
          json_match = response.match(/\{.*\}/m)

          if json_match.nil?
            Rails.logger.error("ContentAgent: No JSON data found in response for section #{section_index}")
            Rails.logger.debug("ContentAgent: Raw response: #{response.truncate(300)}")

            # Create a fallback minimal content structure
            result = {
              "title" => "Section #{section_index}",
              "content" => "Content for section #{section_index} could not be generated properly.",
              "type" => section_type
            }
          else
            # Parse the JSON
            Rails.logger.info("ContentAgent: JSON data found in response for section #{section_index}")
            result = JSON.parse(json_match[0])
          end

          # Validate required fields
          if result["title"].blank?
            Rails.logger.warn("ContentAgent: Missing title in section #{section_index}, using fallback")
            result["title"] = task_data[:task_data][:section_title] || "Section #{section_index}"
          end

          if result["content"].blank?
            Rails.logger.warn("ContentAgent: Missing content in section #{section_index}, using fallback")
            result["content"] = "This section needs to be updated with meaningful content."
          end

          if result["type"].blank?
            Rails.logger.warn("ContentAgent: Missing type in section #{section_index}, using fallback #{section_type}")
            result["type"] = section_type
          end

          # Log the generated content details
          Rails.logger.info("ContentAgent: Generated content for section #{section_index}: '#{result["title"]}'")
          Rails.logger.debug("ContentAgent: Content preview: #{result["content"].to_s.truncate(100)}")

          # Create a standardized format for the section data
          section_data = {
            section_index: section_index,
            output_key: output_key,
            title: result["title"],
            content: result["content"],
            type: result["type"]
          }

          # Add to results array
          results << section_data

          # Update context with this specific section content
          update_context({
            output_key => section_data
          })

          Rails.logger.info("ContentAgent: Successfully processed section #{section_index} as '#{output_key}'")
        rescue JSON::ParserError => e
          Rails.logger.error("ContentAgent: Error parsing JSON response for section #{section_index}: #{e.message}")
          Rails.logger.debug("ContentAgent: Problematic response: #{response.truncate(300)}")

          # Add a placeholder for the failed section
          fallback_section = {
            section_index: section_index,
            output_key: output_key,
            title: "Section #{section_index}",
            content: "This section could not be generated due to a technical error.",
            type: section_type
          }

          results << fallback_section
          update_context({
            output_key => fallback_section
          })

          Rails.logger.info("ContentAgent: Added fallback content for section #{section_index}")
        end
      end

      # Ensure sections are sorted correctly
      results.sort_by! { |s| s[:section_index] }

      # Update context with all section content in one place
      Rails.logger.info("ContentAgent: Updating context with #{results.length} generated sections")
      update_context({
        generated_sections: results
      })

      # Log a summary of generated sections
      Rails.logger.info("ContentAgent: Section generation summary:")
      results.each do |section|
        Rails.logger.info("  - Section #{section[:section_index]}: #{section[:title]} (#{section[:type]})")
      end

      Rails.logger.info("ContentAgent: Completed content generation for #{results.length} sections")
      log_execution_complete
      context
    end
  end
end
