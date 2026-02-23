# frozen_string_literal: true

module Tools
  class GenerateLandingPageTool < BaseTool
    def self.metadata
      {
        name: "generate_ai_landing_page",
        description: <<~DESC.strip,
          AI landing page generator. Creates a complete HTML page with professional design,
          AI-generated images, responsive layout, and lead capture forms.

          Called internally by platform_create(type: "landing_page").
        DESC
        category: "landing_page",
        input_schema: {
          type: "object",
          properties: {
            title:              { type: "string", description: "Title for the landing page" },
            description:        { type: "string", description: "Description / content focus for the page" },
            business_name:      { type: "string", description: "Business or company name" },
            key_details:        { type: "object", description: "Key details (pricing, target_audience, sections, section_content, etc.)" },
            business_info:      { type: "object", description: "Business info (offer, price, value_proposition, key_benefits, etc.)" },
            design_preferences: { type: "object", description: "Design preferences (style, cta, color_scheme, typography, etc.)" },
            design_style:       { type: "string", description: "Design style and aesthetic preferences" },
            form_fields:        { type: "array",  description: "Custom form fields for lead capture" },
            generate_images:    { type: "boolean", description: "Auto-generate AI images (default: true)" },
            image_quality:      { type: "string", enum: %w[standard pro hd high], description: "Image quality level" },
            image_style:        { type: "string", description: "Style for generated images" },
            headline:           { type: "string", description: "Explicit hero headline" },
            cta_text:           { type: "string", description: "CTA button text" },
            key_benefits:       { type: "array",  description: "Key benefits to highlight" },
            color_scheme:       { type: "string", description: "Color scheme to use" },
            uploaded_images:    { type: "array",  description: "User-uploaded image URLs to include" },
            screenshot_analysis:  { type: "object", description: "Structured design spec from screenshot analysis" },
            design_reference_url: { type: "string", description: "URL of design reference image" },
            reference_materials:  { type: "string", description: "Analysis of a reference URL the user provided" },
          },
          required: []
        }
      }
    end

    def execute(args)
      log_execution(args)

      title = get_arg(args, :title) || get_arg(args, :program_name) || get_arg(args, :business_name) || "Landing Page"
      description = get_arg(args, :description) || get_arg(args, :content_focus) || get_arg(args, :program_name) || "AI-Generated Landing Page"

      stream_progress("Starting landing page generation...", percentage: 0)

      begin
        ctx = gather_context(args, title, description)

        stream_progress("Creating landing page record...", percentage: 20)
        landing_page = LandingPage.create!(
          user: user, entity: entity, title: title,
          slug: generate_unique_slug(title), status: "draft",
          metadata: { ai_generated: true, description: description,
                      page_type: ctx[:page_type], generated_at: Time.current }
        )

        if get_arg(args, :generate_images, true)
          quality = get_arg(args, :image_quality, "standard")&.downcase
          style = get_arg(args, :image_style, "professional photography")
          stream_progress("Generating AI images...", percentage: 25)
          generated = generate_landing_page_images(
            title: title, description: description, context: ctx,
            style: style, quality: quality, landing_page: landing_page
          )
          ctx[:image_urls] = (ctx[:image_urls] || []) + generated
        end

        stream_progress("Generating page content with AI...", percentage: 30)
        html_content = generate_html(title, ctx)

        stream_progress("Compiling final landing page...", percentage: 90)
        landing_page.update!(html_content: html_content)

        stream_progress("Done! Loading your new landing page...", percentage: 100)
        success_response(
          id: landing_page.id, landing_page_id: landing_page.id,
          title: landing_page.title, slug: landing_page.slug,
          subdomain: landing_page.subdomain, subdomain_url: landing_page.subdomain_url,
          status: "draft",
          message: "Your landing page '#{landing_page.title}' is ready! Opening the editor now.",
          preview_url: "/landing_pages/#{landing_page.slug}/preview",
          public_url: landing_page.subdomain_url || "/landing/#{landing_page.slug}",
          canvas_type: "landing_page_editor",
          canvas_data: { landing_page_id: landing_page.id }
        )
      rescue => e
        Rails.logger.error "[GenerateLandingPage] Failed: #{e.message}"
        error_response("Failed to create landing page: #{e.message}")
      end
    end

    private

    # ─── Context Gathering ──────────────────────────────────────

    def gather_context(args, title, description)
      business_profile = BusinessContext.for(user, entity).to_h rescue {}
      key_details      = get_arg(args, :key_details) || {}
      business_info    = get_arg(args, :business_info) || {}
      design_prefs     = get_arg(args, :design_preferences) || {}

      {
        # Tier 1: user's immediate intent
        user_message:        @context&.dig(:user_message).to_s,
        description:         description,
        content_focus:       get_arg(args, :content_focus),
        headline:            get_arg(args, :headline),
        cta_text:            get_arg(args, :cta_text) || design_prefs.dig(:cta) || design_prefs.dig("cta") || "Get Started",
        key_benefits:        get_arg(args, :key_benefits).presence || business_info[:key_benefits] || business_info["key_benefits"] || [],
        unique_selling_points: get_arg(args, :unique_selling_points) || [],
        social_proof:        get_arg(args, :social_proof),
        offer_details:       get_arg(args, :offer_details) || business_info[:offer] || business_info["offer"],
        form_fields:         get_arg(args, :form_fields) || [],
        uploaded_images:     get_arg(args, :uploaded_images) || [],
        image_urls:          get_arg(args, :image_urls) || [],

        # Tier 1: design references
        screenshot_analysis:  get_arg(args, :screenshot_analysis),
        design_reference_url: get_arg(args, :design_reference_url),
        reference_materials:  get_arg(args, :reference_materials) || get_arg(args, :reference_analysis),

        # Tier 1: explicit section plan (from design wizard)
        section_content:     key_details[:section_content] || key_details["section_content"] || [],
        planned_sections:    key_details[:sections] || key_details["sections"] || [],

        # Tier 2: business context
        business_name:       get_arg(args, :business_name) || business_profile[:company_name] || title,
        value_proposition:   business_info[:value_proposition] || business_info["value_proposition"] ||
                             key_details[:value_proposition] || key_details["value_proposition"] ||
                             business_profile[:value_proposition] || business_profile[:description] || title,
        target_audience:     business_info[:target_audience] || business_info["target_audience"] ||
                             key_details[:target_audience] || key_details["target_audience"] ||
                             business_profile[:target_audience] || "businesses",
        industry:            business_profile[:industry],
        tagline:             business_profile[:tagline],
        tone_of_voice:       get_arg(args, :tone_of_voice) || design_prefs[:tone_of_voice] ||
                             design_prefs["tone_of_voice"] || business_profile[:tone_of_voice],
        brand_colors:        get_arg(args, :brand_colors) || get_arg(args, :colors) || business_profile[:brand_colors] || [],
        brand_fonts:         business_profile[:brand_fonts],

        # Tier 2: design style
        design_style:        get_arg(args, :design_style) || design_prefs[:style] || design_prefs["style"] || "modern and professional",
        color_scheme:        get_arg(args, :color_scheme) || design_prefs[:color_scheme] || design_prefs["color_scheme"],
        layout_preference:   get_arg(args, :layout_preference) || design_prefs[:layout] || design_prefs["layout"],
        typography:          design_prefs[:typography] || design_prefs["typography"],
        aesthetic_style:     get_arg(args, :aesthetic_style) || design_prefs[:aesthetic] || design_prefs["aesthetic"],

        # Structured data (passed through for prompt building)
        key_details:         key_details,
        business_info:       business_info,
        page_type:           get_arg(args, :page_type, "lead_generation"),
        business_profile:    business_profile,
      }
    end

    # ─── HTML Generation ────────────────────────────────────────

    def generate_html(title, ctx)
      prompt = build_prompt(title, ctx)

      ai_service = BedrockService.new(user: user, entity: entity)
      response = ai_service.complete(
        messages: [{ role: "user", content: prompt }],
        max_tokens: 8192, temperature: 0.7, model: "claude-sonnet-4-6"
      )

      html = strip_markdown_wrapper(response)

      unless html.include?("<!DOCTYPE html>") || html.include?("<html")
        raise "AI did not return valid HTML (#{html.length} chars)"
      end

      inject_form_handling_script(html)
    end

    def build_prompt(title, ctx)
      sections = []

      # ── Block 1: User's Request ──
      sections << <<~BLOCK
        === WHAT THE USER WANTS ===
        #{ctx[:user_message].presence || ctx[:description]}
        #{ctx[:content_focus].present? ? "\nContent focus: #{ctx[:content_focus]}" : ""}
        #{ctx[:headline].present? ? "\nEXACT headline to use: \"#{ctx[:headline]}\"" : ""}
        #{ctx[:offer_details].present? ? "\nOffer: #{ctx[:offer_details]}" : ""}
      BLOCK

      # ── Block 2: Design Reference (highest visual priority) ──
      if ctx[:screenshot_analysis].present?
        spec = ctx[:screenshot_analysis][:design_specification] || ctx[:screenshot_analysis]["design_specification"]
        formatted = spec.is_a?(Hash) ? JSON.pretty_generate(spec) : spec.to_s
        sections << <<~BLOCK
          === DESIGN REFERENCE (follow this design closely) ===
          The user provided a screenshot as design inspiration.
          #{formatted}
          Follow this design specification for layout, colors, typography, and spacing.
        BLOCK
      elsif ctx[:design_reference_url].present?
        sections << <<~BLOCK
          === DESIGN REFERENCE ===
          The user uploaded a screenshot as design inspiration: #{ctx[:design_reference_url]}
          Match the layout structure, color palette, typography, and spacing from this reference.
        BLOCK
      elsif ctx[:reference_materials].present?
        sections << <<~BLOCK
          === DESIGN REFERENCE (from URL analysis) ===
          #{ctx[:reference_materials]}
          Incorporate the design patterns and visual elements described above.
        BLOCK
      end

      # ── Block 2b: Explicit Section Plan (from design wizard) ──
      if ctx[:section_content].any?
        formatted_sections = ctx[:section_content].map { |s| format_planned_section(s) }.join("\n")
        sections << <<~BLOCK
          === APPROVED SECTION PLAN (use this content exactly) ===
          The user reviewed and approved these sections. Use the exact text provided.
          #{formatted_sections}
        BLOCK
      elsif ctx[:planned_sections].any?
        sections << "=== PLANNED SECTIONS ===\nInclude in order: #{ctx[:planned_sections].join(', ')}"
      end

      # ── Block 3: Business Context ──
      biz_lines = []
      biz_lines << "Company: #{ctx[:business_name]}"
      biz_lines << "Industry: #{ctx[:industry]}" if ctx[:industry].present?
      biz_lines << "Value Proposition: #{ctx[:value_proposition]}" if ctx[:value_proposition] != title
      biz_lines << "Target Audience: #{ctx[:target_audience]}"
      biz_lines << "Tagline: \"#{ctx[:tagline]}\"" if ctx[:tagline].present?
      biz_lines << "Brand Voice: #{ctx[:tone_of_voice]}" if ctx[:tone_of_voice].present?
      biz_lines << "Brand Colors: #{Array(ctx[:brand_colors]).join(', ')}" if Array(ctx[:brand_colors]).any?
      biz_lines << "Brand Fonts: #{ctx[:brand_fonts]}" if ctx[:brand_fonts].present?
      biz_lines << "Design Style: #{ctx[:design_style]}"
      biz_lines << "Color Scheme: #{ctx[:color_scheme]}" if ctx[:color_scheme].present?
      biz_lines << "Layout: #{ctx[:layout_preference]}" if ctx[:layout_preference].present?
      biz_lines << "Aesthetic: #{ctx[:aesthetic_style]}" if ctx[:aesthetic_style].present?
      biz_lines << "Typography: #{ctx[:typography]}" if ctx[:typography].present?
      if ctx[:key_benefits].any?
        biz_lines << "Key Benefits:\n#{ctx[:key_benefits].first(6).map { |b| "  - #{b}" }.join("\n")}"
      end
      if ctx[:unique_selling_points].any?
        biz_lines << "Unique Selling Points:\n#{ctx[:unique_selling_points].first(5).map { |u| "  - #{u}" }.join("\n")}"
      end
      biz_lines << "Social Proof: #{ctx[:social_proof]}" if ctx[:social_proof].present?

      sections << "=== BUSINESS CONTEXT ===\n#{biz_lines.join("\n")}"

      # ── Block 4: Images ──
      all_images = (ctx[:uploaded_images] || []) + (ctx[:image_urls] || [])
      if all_images.any?
        image_lines = all_images.first(4).each_with_index.map do |url, i|
          role = i == 0 ? "HERO IMAGE (use in hero section)" : "FEATURE IMAGE #{i}"
          "#{role}: #{url}"
        end
        sections << <<~BLOCK
          === IMAGES (use these EXACT URLs — do NOT invent placeholder URLs) ===
          #{image_lines.join("\n")}
        BLOCK
      end

      # ── Block 5: Technical Rules ──
      form_pattern = <<~FORM.strip
        <form class="contact-form">
          <div class="mb-3"><input type="text" name="name" class="form-control" placeholder="Your Name" required></div>
          <div class="mb-3"><input type="email" name="email" class="form-control" placeholder="Your Email" required></div>
          <div class="mb-3"><input type="tel" name="phone" class="form-control" placeholder="Your Phone"></div>
          <button type="submit" class="btn btn-primary w-100">#{ctx[:cta_text]}</button>
        </form>
      FORM

      form_fields = ctx[:form_fields].any? ? ctx[:form_fields].join(", ") : "name, email, phone"

      sections << <<~BLOCK
        === TECHNICAL RULES ===
        Generate a complete HTML page (<!DOCTYPE html> to </html>).

        Framework: Bootstrap 5 (CDN), Font Awesome for icons.
        Must be mobile-responsive with professional styling.
        CTA button text: "#{ctx[:cta_text]}"

        SECTIONS: Build exactly the sections the user asked for. If they asked for pricing,
        build a pricing section. If they asked for testimonials, build testimonials. Do NOT
        substitute generic sections for what the user specifically requested.

        FORMS: If the page includes a contact/signup form, use this exact pattern:
        #{form_pattern}
        Form fields: #{form_fields}
        Form rules: no inline JS, no action attribute, no method="get", simple Bootstrap classes.

        CONTENT: Use the actual business data provided above — never use placeholder text
        like "Lorem ipsum" or "[Company Name]". Write compelling, specific copy.
        Never use the raw description as the hero headline — write a benefit-driven headline.

        TEXT READABILITY: Dark backgrounds = light text. Light backgrounds = dark text.

        JAVASCRIPT: If including scripts, use single quotes for strings containing HTML attributes.

        Return ONLY the complete HTML. Must end with </body></html>.
      BLOCK

      sections.join("\n\n")
    end

    # ─── Form Submission JS Injection ───────────────────────────
    # This is the one genuinely complex piece: wires up any <form>
    # on the page to POST to the landing page submissions API,
    # which creates a Contact record in the system.

    def inject_form_handling_script(html)
      form_script = <<~JAVASCRIPT
        <script>
        document.addEventListener('DOMContentLoaded', function() {
          var forms = document.querySelectorAll('form');

          var isPreviewMode = window.location.pathname.includes('/preview') ||
                              window.location.pathname.includes('/landing_pages/') ||
                              (window.parent !== window && window.parent.location.pathname.includes('/landing_pages/'));

          forms.forEach(function(form, index) {
            var action = form.getAttribute('action');
            if (action && action.startsWith('http')) return;

            form.removeAttribute('action');
            form.removeAttribute('method');
            form.setAttribute('data-handled', 'true');

            form.addEventListener('submit', function(e) {
              e.preventDefault();
              e.stopPropagation();

              var formData = new FormData(form);
              var submitButton = form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
              var originalText = submitButton ? submitButton.textContent || submitButton.value : '';

              if (submitButton) {
                submitButton.disabled = true;
                if (submitButton.tagName === 'BUTTON') { submitButton.textContent = 'Sending...'; }
                else { submitButton.value = 'Sending...'; }
              }

              var submissionUrl = '/api/v1/landing_page_submissions';
              var slug = null;
              var publicMatch = window.location.pathname.match(/\\/landing\\/([^\\/]+)/);
              var previewMatch = window.location.pathname.match(/\\/landing_pages\\/([^\\/]+)\\/preview/);
              var editorMatch = window.location.pathname.match(/\\/landing_pages\\/([^\\/]+)$/);

              if (publicMatch) { slug = publicMatch[1]; }
              else if (previewMatch) { slug = previewMatch[1]; }
              else if (editorMatch && editorMatch[1] !== 'new') { slug = editorMatch[1]; }

              if (slug) { submissionUrl = '/api/v1/landing_pages/' + slug + '/submit'; }
              if (isPreviewMode) { submissionUrl += (submissionUrl.includes('?') ? '&' : '?') + 'preview=true'; }

              fetch(submissionUrl, {
                method: 'POST',
                body: formData,
                headers: { 'X-Requested-With': 'XMLHttpRequest' }
              })
              .then(function(response) { return response.json(); })
              .then(function(data) {
                if (data.success) {
                  form.innerHTML = '<div class="alert alert-success" style="padding:20px;background:#d4edda;border:1px solid #c3e6cb;border-radius:8px;color:#155724;"><h4 style="margin:0 0 10px">Thank you!</h4><p style="margin:0">' + data.message + '</p></div>';
                } else {
                  showFormError(form, data.message || 'There was an error submitting your form.');
                  resetButton(submitButton, originalText);
                }
              })
              .catch(function() {
                showFormError(form, 'There was an error submitting your form. Please try again.');
                resetButton(submitButton, originalText);
              });
            });
          });

          function resetButton(btn, text) {
            if (!btn) return;
            btn.disabled = false;
            if (btn.tagName === 'BUTTON') { btn.textContent = text; }
            else { btn.value = text; }
          }

          function showFormError(form, message) {
            var errorDiv = form.querySelector('.form-error');
            if (!errorDiv) {
              errorDiv = document.createElement('div');
              errorDiv.className = 'alert alert-danger form-error';
              errorDiv.style.cssText = 'padding:15px;background:#f8d7da;border:1px solid #f5c6cb;border-radius:8px;color:#721c24;margin-bottom:15px;';
              form.insertBefore(errorDiv, form.firstChild);
            }
            errorDiv.textContent = message;
          }
        });
        </script>
      JAVASCRIPT

      if html.include?("</body>")
        html.sub("</body>", "#{form_script}\n</body>")
      elsif html.include?("</html>")
        html.sub("</html>", "#{form_script}\n</body>\n</html>")
      else
        "#{html}\n#{form_script}\n</body>\n</html>"
      end
    end

    # ─── Image Generation ───────────────────────────────────────

    def generate_landing_page_images(title:, description:, context:, style:, landing_page:, quality: "standard")
      return [] unless ENV["GEMINI_API_KEY"].present?

      provider = quality.to_s.match?(/pro|hd|high/i) ? :gemini_pro : :gemini
      service = ImageGenerationService.new(provider: provider)
      host = Rails.application.routes.default_url_options[:host] ||
             ENV["APP_HOST"] ||
             (Rails.env.production? ? "app.amoslabs.com" : "localhost:3000")

      business_name = context[:business_name] || title
      industry = context[:industry]
      key_benefits = context[:key_benefits] || []
      generated_urls = []

      hero_prompt = "Professional #{style} for a business landing page hero section. " \
                    "#{industry.present? ? "#{industry} industry theme. " : ""}" \
                    "Visual concept representing: #{description.truncate(200)}. " \
                    "Modern, clean, high-quality. Wide composition with space for text overlay. No text in image."

      hero_asset = service.generate_and_store!(
        user: user, entity: entity, title: "#{title} - Hero Image",
        description: hero_prompt, size: "1536x1024",
        tags: ["ai-generated", "landing-page", "hero", "landing-page-#{landing_page.id}", provider.to_s]
      )
      if hero_asset&.file&.attached?
        generated_urls << Rails.application.routes.url_helpers.rails_blob_url(hero_asset.file, host: host)
      end

      feature_concepts = if key_benefits.any?
        key_benefits.first(3).map { |b| "Professional #{style} icon/illustration representing: #{b}. Clean, modern. No text." }
      else
        ["Professional teamwork and collaboration",
         "Innovation and growth concept",
         "Customer success and satisfaction"].map { |c| "Professional #{style} representing #{c}. Modern design. No text." }
      end

      feature_concepts.each_with_index do |prompt, i|
        asset = service.generate_and_store!(
          user: user, entity: entity, title: "#{title} - Feature #{i + 1}",
          description: prompt, size: "1024x1024",
          tags: ["ai-generated", "landing-page", "feature", "landing-page-#{landing_page.id}", provider.to_s]
        )
        if asset&.file&.attached?
          generated_urls << Rails.application.routes.url_helpers.rails_blob_url(asset.file, host: host)
        end
      end

      landing_page.update!(metadata: landing_page.metadata.merge(
        "generated_images" => generated_urls, "image_generation_style" => style
      ))
      generated_urls
    rescue => e
      Rails.logger.error "[GenerateLandingPage] Image generation failed: #{e.message}"
      []
    end

    # ─── Utilities ──────────────────────────────────────────────

    def generate_unique_slug(title)
      base_slug = title.parameterize
      slug = base_slug
      counter = 1
      while LandingPage.exists?(slug: slug, entity: entity)
        slug = "#{base_slug}-#{counter}"
        counter += 1
      end
      slug
    end

    def strip_markdown_wrapper(text)
      cleaned = text.to_s.strip
      cleaned = cleaned.sub(/\A```html\s*\n?/i, "").sub(/\A```\s*\n?/, "")
      cleaned.sub(/\n?```\s*\z/, "").strip
    end

    def format_planned_section(section)
      name = section[:name] || section["name"]
      content = section[:content] || section["content"] || {}
      content = content.with_indifferent_access if content.is_a?(Hash)

      lines = ["Section: #{name.to_s.titleize}"]
      if content.is_a?(Hash)
        lines << "  Headline: \"#{content[:headline]}\"" if content[:headline].present?
        lines << "  Subheadline: \"#{content[:subheadline]}\"" if content[:subheadline].present?
        lines << "  CTA: \"#{content[:cta_text]}\"" if content[:cta_text].present?
        lines << "  Section Title: \"#{content[:section_title]}\"" if content[:section_title].present?
        if content[:items].is_a?(Array)
          content[:items].each_with_index do |item, i|
            item = item.with_indifferent_access if item.is_a?(Hash)
            lines << "  Item #{i + 1}: #{item[:title]} — #{item[:description]}"
          end
        end
        if content[:testimonials].is_a?(Array)
          content[:testimonials].each do |t|
            t = t.with_indifferent_access if t.is_a?(Hash)
            lines << "  Testimonial: \"#{t[:quote]}\" — #{t[:author]}#{t[:company].present? ? ", #{t[:company]}" : ""}"
          end
        end
        if content[:plans].is_a?(Array)
          content[:plans].each do |p|
            p = p.with_indifferent_access if p.is_a?(Hash)
            lines << "  Plan: #{p[:name]} — #{p[:price]}#{p[:best_value] ? " (highlight)" : ""}"
          end
        end
      end
      lines.join("\n")
    end
  end
end
