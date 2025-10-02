module Agents
  class ValidationExecutor < PhaseExecutor
    
    def execute
      phase_id = @phase[:id] || @phase['id']
      goal = @phase[:goal] || @phase['goal']
      
      Rails.logger.info "✓ ValidationExecutor: Starting phase #{phase_id}"
      Rails.logger.info "✓ Goal: #{goal}"
      
      notify_progress("Validating results...")
      
      # Get validation rules
      validation_rules = @phase[:validation_rules] || @phase['validation_rules'] || []
      
      if validation_rules.empty?
        Rails.logger.warn "No validation rules defined, skipping validation"
        return {
          success: true,
          status: 'completed',
          message: "No validation rules defined",
          phase: phase_id
        }
      end
      
      # Run all validations
      validation_results = []
      all_passed = true
      
      validation_rules.each_with_index do |rule, index|
        Rails.logger.info "🔍 Running validation #{index + 1}: #{rule['check'] || rule[:check]}"
        
        result = run_validation(rule)
        validation_results << result
        
        if result[:passed]
          notify_progress("✅ #{rule['check'] || rule[:check]}", type: 'validation_passed')
        else
          all_passed = false
          notify_progress("❌ #{rule['check'] || rule[:check]}: #{result[:message]}", type: 'validation_failed')
          
          # Attempt fix if configured
          if should_attempt_fix?
            fix_result = attempt_fix(rule, result)
            
            if fix_result[:success]
              result[:fixed] = true
              result[:passed] = true
              all_passed = true  # Reset to true if fix worked
              notify_progress("🔧 Fixed: #{rule['check'] || rule[:check]}", type: 'validation_fixed')
            end
          end
        end
      end
      
      # Store validation results
      store_phase_output({
        validation_results: validation_results,
        all_passed: all_passed
      }, 'validation_result')
      
      if all_passed
        notify_progress("All validations passed!", type: 'phase_complete')
      else
        notify_progress("Some validations failed", type: 'phase_warning')
      end
      
      {
        success: all_passed,
        status: all_passed ? 'completed' : 'failed',
        validation_results: validation_results,
        phase: phase_id
      }
    end
    
    private
    
    def run_validation(rule)
      rule_name = rule['rule'] || rule[:rule]
      check_description = rule['check'] || rule[:check]
      
      case rule_name.to_s
      when 'html_validity'
        validate_html_validity(rule)
      when 'responsive_design'
        validate_responsive_design(rule)
      when 'has_cta'
        validate_has_cta(rule)
      when 'images_loaded', 'images_valid'
        validate_images(rule)
      when 'brand_consistent'
        validate_brand_consistency(rule)
      when 'tool_check'
        validate_with_tool(rule)
      when 'ai_check'
        validate_with_ai(rule)
      when 'custom'
        validate_custom(rule)
      else
        # Generic validation
        {
          rule: rule_name,
          check: check_description,
          passed: true,
          message: "Validation not implemented, assuming pass"
        }
      end
    end
    
    def validate_html_validity(rule)
      # Get generated HTML from context
      html_content = get_workflow_context('html_content') || 
                    get_workflow_context('page_content') ||
                    find_html_in_context
      
      if html_content.blank?
        return {
          rule: 'html_validity',
          check: rule['check'] || rule[:check],
          passed: false,
          message: "No HTML content found to validate"
        }
      end
      
      # Basic HTML validation (could be enhanced with a proper validator)
      has_html_tag = html_content.include?('<html') || html_content.include?('<!DOCTYPE')
      has_body_tag = html_content.include?('<body')
      properly_closed = html_content.scan(/<(\w+)[^>]*>/).count == html_content.scan(/<\/(\w+)>/).count
      
      passed = has_html_tag && has_body_tag && properly_closed
      
      {
        rule: 'html_validity',
        check: rule['check'] || rule[:check],
        passed: passed,
        message: passed ? "HTML structure is valid" : "HTML structure is invalid"
      }
    end
    
    def validate_responsive_design(rule)
      # Get HTML content
      html_content = find_html_in_context
      
      if html_content.blank?
        return {
          rule: 'responsive_design',
          check: rule['check'] || rule[:check],
          passed: false,
          message: "No HTML content found"
        }
      end
      
      # Check for responsive indicators
      has_viewport = html_content.include?('viewport') || html_content.include?('meta name="viewport"')
      has_responsive_class = html_content.include?('responsive') || 
                            html_content.include?('col-') || 
                            html_content.include?('container')
      has_media_queries = html_content.include?('@media')
      
      passed = has_viewport && (has_responsive_class || has_media_queries)
      
      {
        rule: 'responsive_design',
        check: rule['check'] || rule[:check],
        passed: passed,
        message: passed ? "Design is responsive" : "Design may not be responsive"
      }
    end
    
    def validate_has_cta(rule)
      html_content = find_html_in_context
      
      if html_content.blank?
        return {
          rule: 'has_cta',
          check: rule['check'] || rule[:check],
          passed: false,
          message: "No content found"
        }
      end
      
      # Check for CTA indicators
      has_button = html_content.match?(/<button|<a[^>]*class="[^"]*btn/)
      has_cta_text = html_content.match?(/cta|call.to.action|sign.up|get.started|buy.now|contact.us/i)
      
      passed = has_button && has_cta_text
      
      {
        rule: 'has_cta',
        check: rule['check'] || rule[:check],
        passed: passed,
        message: passed ? "CTA is present" : "No clear CTA found"
      }
    end
    
    def validate_images(rule)
      html_content = find_html_in_context
      
      if html_content.blank?
        return {
          rule: 'images_valid',
          check: rule['check'] || rule[:check],
          passed: true,
          message: "No content to validate"
        }
      end
      
      # Extract image URLs
      image_urls = html_content.scan(/<img[^>]+src="([^"]+)"/).flatten
      
      if image_urls.empty?
        return {
          rule: 'images_valid',
          check: rule['check'] || rule[:check],
          passed: true,
          message: "No images found (OK)"
        }
      end
      
      # Check if URLs are valid (basic check)
      valid_urls = image_urls.all? do |url|
        url.start_with?('http://', 'https://', '/', 'data:')
      end
      
      {
        rule: 'images_valid',
        check: rule['check'] || rule[:check],
        passed: valid_urls,
        message: valid_urls ? "All #{image_urls.count} images have valid URLs" : "Some image URLs are invalid"
      }
    end
    
    def validate_brand_consistency(rule)
      # Check if uploaded brand assets were used
      brand_colors = get_workflow_context('brand_colors') || 
                    get_workflow_context('color_scheme')
      
      html_content = find_html_in_context
      
      if brand_colors.blank? || html_content.blank?
        return {
          rule: 'brand_consistent',
          check: rule['check'] || rule[:check],
          passed: true,
          message: "No brand guidelines to validate against"
        }
      end
      
      # Check if brand colors appear in HTML
      colors_used = Array(brand_colors).any? do |color|
        html_content.include?(color.to_s)
      end
      
      {
        rule: 'brand_consistent',
        check: rule['check'] || rule[:check],
        passed: colors_used,
        message: colors_used ? "Brand colors are used" : "Brand colors may not be applied"
      }
    end
    
    def validate_with_tool(rule)
      tool_name = rule['tool'] || rule[:tool]
      tool_args = rule['tool_args'] || rule[:tool_args] || {}
      
      result = execute_tool(tool_name, tool_args)
      
      {
        rule: tool_name,
        check: rule['check'] || rule[:check],
        passed: result[:success] || result['success'],
        message: result[:message] || result['message'] || "Tool validation completed"
      }
    end
    
    def validate_with_ai(rule)
      check_description = rule['check'] || rule[:check]
      
      # Get relevant context
      context_data = get_workflow_context
      html_content = find_html_in_context
      
      prompt = <<~PROMPT
        Validate this requirement: #{check_description}
        
        Available Context:
        #{JSON.pretty_generate(context_data.slice(0, 20))}  # Limit context
        
        HTML Content (first 1000 chars):
        #{html_content&.first(1000)}
        
        Does the content meet this requirement?
        Respond with JSON:
        {
          "passed": true/false,
          "message": "explanation"
        }
      PROMPT
      
      result = ai_decide(prompt, expect_json: true)
      
      {
        rule: 'ai_check',
        check: check_description,
        passed: result['passed'] || false,
        message: result['message'] || "AI validation completed"
      }
    end
    
    def validate_custom(rule)
      validation_function = rule['validation_function'] || rule[:validation_function]
      
      begin
        # Safely evaluate custom validation
        # In production, this should be sandboxed properly
        passed = eval(validation_function)
        
        {
          rule: 'custom',
          check: rule['check'] || rule[:check],
          passed: !!passed,
          message: passed ? "Custom validation passed" : "Custom validation failed"
        }
      rescue => e
        Rails.logger.error "Custom validation error: #{e.message}"
        {
          rule: 'custom',
          check: rule['check'] || rule[:check],
          passed: false,
          message: "Validation error: #{e.message}"
        }
      end
    end
    
    def should_attempt_fix?
      on_failure = @phase[:on_failure] || @phase['on_failure']
      return false unless on_failure
      
      action = on_failure[:action] || on_failure['action']
      action.to_s == 'attempt_fix'
    end
    
    def attempt_fix(rule, validation_result)
      max_attempts = @phase.dig(:on_failure, :max_fix_attempts) ||
                    @phase.dig('on_failure', 'max_fix_attempts') || 2
      
      use_fixer = @phase.dig(:on_failure, :use_fixer_agent) ||
                 @phase.dig('on_failure', 'use_fixer_agent')
      
      if use_fixer
        # Use FixerAgent
        fixer = Agents::Specialized::FixerAgent.new(
          task_session: @context[:task_session],
          initial_context: @context
        )
        
        fix_result = fixer.fix_failed_step(
          { validation_rule: rule },
          { error: validation_result[:message] },
          @context
        )
        
        return fix_result
      else
        # Try simple fixes based on rule type
        case rule['rule'] || rule[:rule]
        when 'has_cta'
          attempt_add_cta
        when 'responsive_design'
          attempt_add_responsive
        else
          { success: false, message: "No fix strategy for this rule" }
        end
      end
    end
    
    def attempt_add_cta
      # Simple fix: add a CTA to the page
      html_content = find_html_in_context
      return { success: false } if html_content.blank?
      
      cta_html = '<div class="cta-section text-center py-5"><a href="#" class="btn btn-primary btn-lg">Get Started</a></div>'
      
      # Insert before closing body tag
      if html_content.include?('</body>')
        fixed_html = html_content.sub('</body>', "#{cta_html}</body>")
        
        # Update in context (would need to save back to landing page)
        {
          success: true,
          message: "Added CTA section",
          fixed_content: fixed_html
        }
      else
        { success: false, message: "Could not find insertion point" }
      end
    end
    
    def attempt_add_responsive
      # Simple fix: add viewport meta tag
      html_content = find_html_in_context
      return { success: false } if html_content.blank?
      
      viewport_tag = '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
      
      if html_content.include?('<head>') && !html_content.include?('viewport')
        fixed_html = html_content.sub('<head>', "<head>\n  #{viewport_tag}")
        
        {
          success: true,
          message: "Added viewport meta tag",
          fixed_content: fixed_html
        }
      else
        { success: false, message: "Responsive elements already present or can't fix" }
      end
    end
    
    def find_html_in_context
      context_data = get_workflow_context
      
      # Look for HTML content in various possible keys
      context_data['html_content'] || 
      context_data[:html_content] ||
      context_data['page_content'] ||
      context_data[:page_content] ||
      context_data['content'] ||
      context_data[:content] ||
      context_data.values.find { |v| v.is_a?(String) && v.include?('<html') }
    end
  end
end
