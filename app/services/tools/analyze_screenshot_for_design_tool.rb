module Tools
  class AnalyzeScreenshotForDesignTool < BaseTool
    def self.metadata
      {
        name: "analyze_screenshot_for_design",
        description: "Analyze a screenshot/design image to extract detailed design specifications for landing page creation. Offers standard or high-fidelity analysis modes.",
        category: "design",
        input_schema: {
          type: "object",
          properties: {
            image_url: {
              type: "string",
              description: "URL or path to the screenshot/design image"
            },
            asset_id: {
              type: "integer",
              description: "ImageAsset ID if image is already uploaded"
            },
            analysis_mode: {
              type: "string",
              enum: ["standard", "high_fidelity"],
              description: "Analysis depth: 'standard' (faster, 1 API call) or 'high_fidelity' (detailed, 5 API calls, costs ~5x more)"
            },
            focus_areas: {
              type: "array",
              description: "Specific areas to focus on: layout, colors, typography, spacing, content",
              items: { type: "string" }
            }
          },
          required: ["analysis_mode"]
        }
      }
    end

    def execute(args, context = {})
      analysis_mode = args[:analysis_mode] || "standard"
      focus_areas = args[:focus_areas] || ["layout", "colors", "typography"]
      
      # Get the image
      image_data, content_type = get_image_data(args)
      
      unless image_data
        return error_response("Could not load image. Please provide either image_url or asset_id.")
      end

      stream_progress("🎨 Starting #{analysis_mode} design analysis...", percentage: 10)

      begin
        result = if analysis_mode == "high_fidelity"
          perform_high_fidelity_analysis(image_data, content_type, focus_areas)
        else
          perform_standard_analysis(image_data, content_type, focus_areas)
        end

        stream_progress("✅ Design analysis complete!", percentage: 100)

        success_response(result.merge(
          analysis_mode: analysis_mode,
          message: "Screenshot analyzed successfully in #{analysis_mode} mode"
        ))
      rescue => e
        Rails.logger.error "Screenshot analysis failed: #{e.message}"
        error_response("Failed to analyze screenshot: #{e.message}")
      end
    end

    private

    def get_image_data(args)
      # Try to get from ImageAsset first
      if args[:asset_id].present?
        asset = ImageAsset.find_by(id: args[:asset_id], entity: @entity)
        if asset
          file_path = ActiveStorage::Blob.service.path_for(asset.file.blob.key)
          image_data = File.read(file_path)
          content_type = asset.file.content_type
          return [Base64.strict_encode64(image_data), content_type]
        end
      end

      # Try to get from URL
      if args[:image_url].present?
        # Handle data URLs or file URLs
        if args[:image_url].start_with?("data:image")
          data_match = args[:image_url].match(/^data:([^;]+);base64,(.+)/)
          if data_match
            return [data_match[2], data_match[1]]
          end
        else
          # Download from URL
          require 'open-uri'
          image_content = URI.open(args[:image_url]).read
          return [Base64.strict_encode64(image_content), "image/jpeg"]
        end
      end

      nil
    end

    def perform_standard_analysis(image_data, content_type, focus_areas)
      stream_progress("📸 Analyzing screenshot (standard mode - 1 API call)...", percentage: 30)
      
      ai_service = BedrockService.new(user: @user, entity: @entity)
      
      prompt = <<~PROMPT
        Analyze this landing page design screenshot in detail. Extract the following information as structured JSON:

        Focus on these areas: #{focus_areas.join(', ')}

        Return a JSON object with this exact structure:
        {
          "layout": {
            "type": "hero-cta|full-width|split|multi-section",
            "sections": [
              {"name": "hero", "position": "top", "height": "viewport|tall|medium|compact"},
              {"name": "features", "position": "middle", "layout": "grid-3|grid-2|list"},
              {"name": "cta", "position": "bottom"}
            ]
          },
          "colors": {
            "primary": "#hex",
            "secondary": "#hex",
            "accent": "#hex",
            "background": "#hex",
            "text": "#hex",
            "palette_description": "warm, cool, vibrant, muted, professional, playful"
          },
          "typography": {
            "heading_style": "bold sans-serif|elegant serif|modern|playful",
            "heading_size": "extra-large|large|medium",
            "body_style": "clean sans-serif|readable serif",
            "body_size": "16px|18px|20px",
            "font_weight": "light|regular|medium|bold",
            "letter_spacing": "tight|normal|wide"
          },
          "spacing": {
            "overall_density": "compact|balanced|spacious",
            "section_padding": "tight|medium|generous",
            "element_gaps": "minimal|standard|large"
          },
          "visual_style": {
            "aesthetic": "modern|classic|minimal|bold|elegant|playful|corporate",
            "imagery_style": "photos|illustrations|icons|mixed|none",
            "button_style": "rounded|sharp|pill|ghost",
            "card_style": "flat|shadow|border|elevated"
          },
          "content_structure": {
            "headline_position": "center|left",
            "cta_prominence": "very-prominent|prominent|subtle",
            "form_placement": "hero|sidebar|footer|popup",
            "social_proof_location": "hero|features|testimonials-section"
          }
        }

        IMPORTANT: 
        - Extract EXACT hex codes if visible in the design
        - Be specific about layout structure
        - Note any unique design elements or patterns
        - Identify the overall design aesthetic clearly

        Return ONLY the JSON object, no markdown formatting.
      PROMPT

      response = ai_service.send_message_with_image(prompt, image_data, content_type)
      
      # Parse JSON response
      design_spec = JSON.parse(response.strip.gsub(/```json\n?/, '').gsub(/```\n?/, ''))
      
      stream_progress("✨ Standard analysis complete", percentage: 80)
      
      {
        design_specification: design_spec,
        analysis_quality: "standard",
        api_calls_used: 1,
        raw_analysis: response
      }
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse vision response as JSON: #{e.message}"
      # Return the raw response if JSON parsing fails
      {
        design_specification: extract_design_details_from_text(response),
        analysis_quality: "standard",
        api_calls_used: 1,
        raw_analysis: response,
        note: "Analysis completed but returned as text instead of structured JSON"
      }
    end

    def perform_high_fidelity_analysis(image_data, content_type, focus_areas)
      stream_progress("🎨 Starting HIGH FIDELITY analysis (5 detailed passes)...", percentage: 20)
      
      ai_service = BedrockService.new(user: @user, entity: @entity)
      
      results = {}
      
      # Pass 1: Overall Layout & Structure
      stream_progress("📐 Pass 1/5: Analyzing layout structure...", percentage: 30)
      results[:layout] = analyze_layout(ai_service, image_data, content_type)
      
      # Pass 2: Color Palette Extraction
      stream_progress("🎨 Pass 2/5: Extracting exact colors...", percentage: 45)
      results[:colors] = analyze_colors(ai_service, image_data, content_type)
      
      # Pass 3: Typography Details
      stream_progress("🔤 Pass 3/5: Analyzing typography...", percentage: 60)
      results[:typography] = analyze_typography(ai_service, image_data, content_type)
      
      # Pass 4: Spacing & Dimensions
      stream_progress("📏 Pass 4/5: Measuring spacing and dimensions...", percentage: 75)
      results[:spacing] = analyze_spacing(ai_service, image_data, content_type)
      
      # Pass 5: Content Extraction (OCR)
      stream_progress("📝 Pass 5/5: Extracting text content...", percentage: 90)
      results[:extracted_content] = extract_content(ai_service, image_data, content_type)
      
      {
        design_specification: results,
        analysis_quality: "high_fidelity",
        api_calls_used: 5,
        note: "High fidelity analysis complete - maximum design accuracy"
      }
    end

    # High Fidelity Analysis Methods - Each focused prompt
    
    def analyze_layout(ai_service, image_data, content_type)
      prompt = <<~PROMPT
        Analyze ONLY the layout structure of this landing page. Return JSON:
        {
          "layout_type": "hero-cta|full-width|split-screen|multi-section",
          "sections": [
            {
              "name": "hero|features|benefits|testimonials|cta|footer",
              "position": "top|upper|middle|lower|bottom",
              "height_estimate": "viewport|tall|medium|compact",
              "width": "full-width|contained|narrow",
              "background": "solid|gradient|image|pattern"
            }
          ],
          "grid_system": "single-column|two-column|three-column|asymmetric",
          "content_alignment": "center|left|right|mixed",
          "navigation": "top|sticky|side|none"
        }
        Return ONLY valid JSON.
      PROMPT
      
      response = ai_service.send_message_with_image(prompt, image_data, content_type)
      JSON.parse(clean_json_response(response))
    rescue => e
      { error: "Layout analysis failed: #{e.message}", raw: response }
    end

    def analyze_colors(ai_service, image_data, content_type)
      prompt = <<~PROMPT
        Extract EXACT color values from this design. Look carefully and provide specific hex codes. Return JSON:
        {
          "primary_colors": ["#hex1", "#hex2"],
          "secondary_colors": ["#hex3", "#hex4"],
          "accent_colors": ["#hex5"],
          "background_colors": ["#hex6", "#hex7"],
          "text_colors": ["#hex8", "#hex9"],
          "button_colors": {
            "background": "#hex",
            "text": "#hex",
            "hover": "#hex"
          },
          "color_temperature": "warm|cool|neutral",
          "color_saturation": "vibrant|muted|mixed",
          "contrast_level": "high|medium|low"
        }
        
        CRITICAL: Look at buttons, headers, backgrounds and extract EXACT hex colors if visible.
        Return ONLY valid JSON.
      PROMPT
      
      response = ai_service.send_message_with_image(prompt, image_data, content_type)
      JSON.parse(clean_json_response(response))
    rescue => e
      { error: "Color analysis failed: #{e.message}", raw: response }
    end

    def analyze_typography(ai_service, image_data, content_type)
      prompt = <<~PROMPT
        Analyze typography in this design with maximum detail. Return JSON:
        {
          "headings": {
            "font_family_style": "sans-serif|serif|display|handwritten",
            "weight": "light|regular|medium|semibold|bold|extrabold",
            "size_h1": "48px|56px|64px|72px|estimate",
            "size_h2": "32px|40px|48px|estimate",
            "line_height": "tight|normal|relaxed",
            "letter_spacing": "tight|normal|wide",
            "text_transform": "none|uppercase|capitalize",
            "style_notes": "modern, bold, elegant, etc."
          },
          "body_text": {
            "font_family_style": "sans-serif|serif",
            "weight": "light|regular|medium",
            "size": "14px|16px|18px|20px|estimate",
            "line_height": "1.5|1.6|1.7|1.8",
            "color_contrast": "high|medium|low"
          },
          "buttons_cta": {
            "font_weight": "medium|semibold|bold",
            "text_transform": "none|uppercase",
            "size": "14px|16px|18px"
          },
          "overall_typography_style": "modern|classic|elegant|playful|corporate"
        }
        Return ONLY valid JSON.
      PROMPT
      
      response = ai_service.send_message_with_image(prompt, image_data, content_type)
      JSON.parse(clean_json_response(response))
    rescue => e
      { error: "Typography analysis failed: #{e.message}", raw: response }
    end

    def analyze_spacing(ai_service, image_data, content_type)
      prompt = <<~PROMPT
        Measure spacing and dimensions in this design. Return JSON:
        {
          "page_width": "full-width|1200px|1400px|1600px|estimate",
          "content_max_width": "800px|1000px|1200px|estimate",
          "section_padding": {
            "vertical": "60px|80px|100px|120px|estimate",
            "horizontal": "20px|40px|60px|estimate"
          },
          "element_spacing": {
            "heading_to_text": "16px|24px|32px|estimate",
            "text_paragraphs": "12px|16px|20px|estimate",
            "section_gaps": "40px|60px|80px|estimate",
            "card_gaps": "20px|30px|40px|estimate"
          },
          "button_sizing": {
            "padding_vertical": "12px|16px|20px|estimate",
            "padding_horizontal": "24px|32px|40px|estimate",
            "border_radius": "4px|8px|12px|24px|full"
          },
          "overall_density": "compact|balanced|spacious"
        }
        Return ONLY valid JSON.
      PROMPT
      
      response = ai_service.send_message_with_image(prompt, image_data, content_type)
      JSON.parse(clean_json_response(response))
    rescue => e
      { error: "Spacing analysis failed: #{e.message}", raw: response }
    end

    def extract_content(ai_service, image_data, content_type)
      prompt = <<~PROMPT
        Extract ALL visible text content from this landing page design. Return JSON:
        {
          "headline": "main headline text",
          "subheadline": "subheadline or tagline",
          "hero_copy": "any description text in hero section",
          "feature_headlines": ["feature 1 title", "feature 2 title"],
          "feature_descriptions": ["feature 1 desc", "feature 2 desc"],
          "benefit_points": ["benefit 1", "benefit 2"],
          "cta_buttons": ["primary CTA text", "secondary CTA text"],
          "form_labels": ["Name", "Email", etc],
          "testimonial_text": "any testimonial quotes",
          "footer_text": "footer content",
          "other_notable_text": ["any other important text"]
        }
        
        IMPORTANT: Extract text exactly as shown. This will be used to recreate the page.
        Return ONLY valid JSON.
      PROMPT
      
      response = ai_service.send_message_with_image(prompt, image_data, content_type)
      JSON.parse(clean_json_response(response))
    rescue => e
      { error: "Content extraction failed: #{e.message}", raw: response }
    end

    # Helper methods
    
    def clean_json_response(response)
      # Remove markdown code blocks and clean up response
      response.strip
              .gsub(/```json\n?/, '')
              .gsub(/```\n?/, '')
              .gsub(/^[^{]*/, '') # Remove anything before first {
              .gsub(/[^}]*$/, '') # Remove anything after last }
    end

    def extract_design_details_from_text(text)
      # Fallback: extract design details from unstructured text
      {
        layout: { note: "See raw analysis" },
        colors: { note: "See raw analysis" },
        typography: { note: "See raw analysis" },
        visual_style: { note: "See raw analysis" }
      }
    end

    def stream_progress(message, percentage: nil)
      return unless @progress_callback
      
      @progress_callback.call({
        type: 'tool_progress',
        tool: 'analyze_screenshot_for_design',
        message: message,
        percentage: percentage
      })
    end
  end
end

