class ApplyHtmlLandingPageChangeJob < ApplicationJob
  queue_as :default

  def perform(landing_page_id, instruction, entity_id, user_id, business_profile_id = nil)
    Rails.logger.info "🚀 ApplyHtmlLandingPageChangeJob started - LP: #{landing_page_id}, User: #{user_id}"
    
    landing_page = LandingPage.find(landing_page_id)
    entity = Entity.find(entity_id)
    user = User.find(user_id)
    business_profile = business_profile_id ? BusinessProfile.find(business_profile_id) : nil
    
    Rails.logger.info "📊 Job context - User: #{user.id} (#{user.email}), Entity: #{entity.id}, LP: #{landing_page.id}"
    Rails.logger.info "🔍 JobNotificationChannel available: #{defined?(JobNotificationChannel)}"
    
    # Job started status now stored by service before enqueue
    # Just log that job is running
    Rails.logger.info "🚀 Job is running - status already stored by service"
    
    # Build context for AI
    context = {
      instruction: instruction,
      current_html: landing_page.html_content,
      landing_page: landing_page,
      business_profile: business_profile,
      entity: entity,
      user: user
    }
    
    # Apply the change using AI
    updated_html = apply_html_change(context)
    
    # Update the landing page with the new HTML
    landing_page.update!(
      html_content: updated_html
    )
    
    # Store job completed status in cache for SSE streaming (with error protection)
    begin
      Rails.logger.info "📡 Storing job_completed status for user #{user.id}, landing page #{landing_page_id}"
      job_status_key = "job_status_#{user.id}_#{landing_page_id}"
      
      Rails.cache.write(job_status_key, {
        type: 'job_completed',
        job_type: 'landing_page_update',
        landing_page_id: landing_page_id,
        message: 'Landing page updated successfully!',
        success: true,
        timestamp: Time.current.iso8601,
        status: 'completed',
        data: {
          id: landing_page.id,
          title: landing_page.title,
          updated_at: landing_page.updated_at.iso8601
        }
      }, expires_in: 30.minutes)
      
      Rails.logger.info "✅ job_completed status stored in cache"
    rescue => cache_error
      Rails.logger.error "⚠️  Failed to store job completion status in cache: #{cache_error.message}"
      Rails.logger.error "But the job completed successfully - landing page was updated"
    end
    
    Rails.logger.info "Successfully applied HTML change to landing page #{landing_page_id}"
    
  rescue => e
    Rails.logger.error "Error applying HTML change to landing page #{landing_page_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    # Store job failed status in cache for SSE streaming (with error protection)
    if user
      begin
        job_status_key = "job_status_#{user.id}_#{landing_page_id}"
        Rails.cache.write(job_status_key, {
          type: 'job_failed',
          job_type: 'landing_page_update',
          landing_page_id: landing_page_id,
          message: "Failed to update landing page: #{e.message}",
          success: false,
          timestamp: Time.current.iso8601,
          status: 'failed',
          error: e.message
        }, expires_in: 30.minutes)
      rescue => cache_error
        Rails.logger.error "⚠️  Failed to store job failure status in cache: #{cache_error.message}"
      end
    end
    
    # Store error message in html_content so user knows something went wrong
    landing_page&.update(html_content: "<!-- Error applying change: #{e.message} -->\n#{landing_page.html_content}")
  end
  
  private
  
  def apply_html_change(context)
    system_prompt = "You are an expert web developer and landing page designer who modifies HTML landing pages based on user instructions."
    user_prompt = build_html_change_prompt(context)
    
    # Use Claude to modify the HTML
    response = ClaudeService.new.send_message(system_prompt, user_prompt)
    
    # Extract HTML from response
    extract_html_from_response(response)
  end
  
  def build_html_change_prompt(context)
    business_context = ""
    if context[:business_profile]
      bp = context[:business_profile]
      business_context = "
Business Context:
- Company: #{bp.name}
- Industry: #{bp.industry}
- Description: #{bp.description}
- Target Audience: #{bp.target_audience}
- Brand Voice: #{bp.tone_of_voice}
"
    end
    
    landing_page_context = ""
    if context[:landing_page]
      lp = context[:landing_page]
      landing_page_context = "
Landing Page Context:
- Title: #{lp.title}
- Description: #{lp.description}
- Status: #{lp.status}
- Slug: #{lp.slug}
"
    end
    
    current_html = context[:current_html] || ""
    
    "You are an expert web developer and landing page designer. You need to modify an existing HTML landing page based on a user's instruction.

#{business_context}
#{landing_page_context}

User's Instruction:
\"#{context[:instruction]}\"

Current HTML Content:
#{current_html}

Please modify the HTML content according to the user's instruction. Make sure to:
1. Keep the existing structure and styling where appropriate
2. Maintain Bootstrap 5 compatibility
3. Ensure the changes are professional and effective
4. Keep the HTML valid and well-formed
5. Maintain responsiveness
6. Apply the changes precisely as requested

Return ONLY the complete modified HTML code, starting with <!DOCTYPE html> and ending with </html>. Do not include any explanatory text before or after the HTML.

If the current HTML is empty or invalid, create a new professional landing page that incorporates the user's request."
  end
  
  def extract_html_from_response(response)
    # Remove any markdown code blocks if present
    html = response.gsub(/```html\n?/, '').gsub(/```\n?/, '')
    
    # Ensure we start with DOCTYPE if not present
    unless html.strip.start_with?('<!DOCTYPE')
      html = "<!DOCTYPE html>\n" + html
    end
    
    html.strip
  end
end 