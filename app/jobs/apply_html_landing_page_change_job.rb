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
        type: "job_completed",
        job_type: "landing_page_update",
        landing_page_id: landing_page_id,
        message: "Landing page updated successfully!",
        success: true,
        timestamp: Time.current.iso8601,
        status: "completed",
        data: {
          id: landing_page.id,
          title: landing_page.title,
          updated_at: landing_page.updated_at.iso8601
        }
      }, expires_in: 30.minutes)

      Rails.logger.info "✅ job_completed status stored in cache"
      
      # Find the user's current session to broadcast canvas reload
      # Get the most recent session for this user
      # Use subquery approach to avoid PostgreSQL DISTINCT/ORDER BY conflict
      recent_messages = ScoutMessage.where(user_id: user_id)
                                   .order(created_at: :desc)
                                   .limit(50)
                                   
      recent_sessions = recent_messages.pluck(:session_id).uniq.take(5)
                                   
      Rails.logger.info "🔍 Found recent sessions for user #{user_id}: #{recent_sessions.inspect}"
      
      # Broadcast canvas reload to all recent sessions
      recent_sessions.each do |session_id|
        begin
          ScoutChannel.broadcast_to(session_id, {
            type: 'load_canvas',
            canvas_name: 'landing_page_editor',
            canvas_data: { landing_page_id: landing_page.id },
            force_refresh: true,
            message: "Landing page has been updated successfully!"
          })
          Rails.logger.info "📡 Broadcast canvas reload to session: #{session_id}"
        rescue => e
          Rails.logger.warn "⚠️  Failed to broadcast to session #{session_id}: #{e.message}"
        end
      end
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
          type: "job_failed",
          job_type: "landing_page_update",
          landing_page_id: landing_page_id,
          message: "Failed to update landing page: #{e.message}",
          success: false,
          timestamp: Time.current.iso8601,
          status: "failed",
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
    # Use Claude Sonnet 4.5 for good quality edits (balanced cost)
    response = AiServiceHelper.get_service.send_message(system_prompt, user_prompt, model: "claude-sonnet-4-6", max_tokens: 6000, temperature: 0.4)

    # Extract either full HTML or a partial snippet
    extracted = extract_full_or_partial_html(response)

    if extracted[:type] == :full
      ensure_doctype(extracted[:content])
    else
      # Merge partial changes into the existing page instead of replacing everything
      merge_partial_into_document(context[:current_html].to_s, extracted[:content], context[:instruction])
    end
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

Please modify the HTML content according to the user's instruction. CRITICAL RULES:
1. Do NOT remove existing content unless the instruction explicitly asks you to remove it
2. Prefer targeted edits to the relevant section; keep all unrelated sections intact
3. Maintain Bootstrap 5 compatibility and responsiveness
4. Keep the HTML valid and well-formed
5. Apply the changes precisely as requested

Output:
- Return ONLY raw HTML. Do NOT include explanations, lists of changes, or commentary.
- If you produced a full page, return the COMPLETE HTML document (<!DOCTYPE html> ... </html>)
- If you only produced a small snippet or section, return just the SNIPPET without wrapping it in <!DOCTYPE html>, <html>, or <body>

If the current HTML is empty or invalid, create a new professional landing page that incorporates the user's request."
  end

  # Decide if the model returned a full document or just a snippet
  def extract_full_or_partial_html(response)
    # Remove common wrappers and commentary
    cleaned = response.to_s
      .gsub(/```html\n?/i, "")
      .gsub(/```/m, "")
      .gsub(/^\s*I['’]ll.*$/i, "")
      .gsub(/^\s*I have.*$/i, "")
      .gsub(/\[Rest of the HTML.*?\]/i, "")
      .strip

    # If full document markers exist, extract from the first < to the last >
    if cleaned.match?(/<!DOCTYPE/i) || cleaned.match?(/<html[\s>]/i)
      start = cleaned.index("<")
      end_idx = cleaned.rindex(">")
      html = start ? cleaned[start..end_idx] : cleaned
      return { type: :full, content: html }
    end

    # Try to isolate the HTML-like portion by slicing from the first tag
    if (idx = cleaned.index("<"))
      candidate = cleaned[idx..(cleaned.rindex(">") || -1)]
      # If it contains at least one element tag, treat as partial HTML
      if candidate.match?(/<\w+[\s>]/)
        return { type: :partial, content: candidate }
      end
    end

    # Fallback: return cleaned as partial (will be appended to body)
    { type: :partial, content: cleaned }
  end

  def ensure_doctype(html)
    return html if html.to_s.strip.start_with?("<!DOCTYPE")
    "<!DOCTYPE html>\n" + html.to_s
  end

  # Heuristic merge when we receive only a partial snippet
  def merge_partial_into_document(current_html, partial_html, instruction)
    require "nokogiri"
    return ensure_doctype(partial_html) if current_html.to_s.strip.empty?

    doc = Nokogiri::HTML(current_html)
    frag = Nokogiri::HTML::DocumentFragment.parse(partial_html)

    # Try to replace by id if the snippet contains a top-level element with id
    target_with_id = frag.children.find { |n| n.element? && n["id"].present? }
    if target_with_id
      existing = doc.at_css("##{target_with_id['id']}")
      if existing
        existing.replace(target_with_id)
        return doc.to_html
      end
    end

    # Try to replace by a recognizable section/container selector
    selectors = [
      "[data-section]",
      ".section",
      "section",
      ".container",
      "main"
    ]
    target = target_with_id || selectors.lazy.map { |sel| frag.at_css(sel) }.find(&:present?)
    if target && target["class"]
      # Find a similar container by the first class name
      first_class = target["class"].split.first
      if first_class
        existing = doc.at_css(".#{first_class}")
        if existing
          existing.replace(target)
          return doc.to_html
        end
      end
    end

    # Fallback: append to the end of <body> with clear markers
    body = doc.at("body") || doc.root
    body.add_child(Nokogiri::XML::Text.new("\n<!-- AI update start: #{instruction.to_s[0..80]} -->\n", doc))
    wrapper = Nokogiri::XML::Node.new("section", doc)
    wrapper["class"] = "container my-5"
    wrapper.inner_html = partial_html
    body.add_child(wrapper)
    body.add_child(Nokogiri::XML::Text.new("\n<!-- AI update end -->\n", doc))
    doc.to_html
  end
end
