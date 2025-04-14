class GenerateLandingPageContentJob < ApplicationJob
  queue_as :ai_generation
  
  def perform(landing_page_id, description, page_type, business_profile_json = nil, campaign_id = nil)
    landing_page = LandingPage.find_by(id: landing_page_id)
    return unless landing_page
    
    # Get associated data for context
    business_profile = business_profile_json ? JSON.parse(business_profile_json) : nil
    campaign = campaign_id ? Campaign.find_by(id: campaign_id) : landing_page.campaign
    
    # Build detailed prompt based on the type of landing page and description
    prompt = build_prompt(landing_page, description, page_type, business_profile, campaign)
    
    # Call OpenAI API
    response = call_openai_api(prompt)
    
    # Process the response and update the landing page
    if response && response["choices"] && response["choices"].first
      content = process_openai_response(response["choices"].first["message"]["content"])
      
      # Update the landing page with generated content
      landing_page.update(
        headline: content[:headline],
        subheadline: content[:subheadline],
        content: content[:sections],
        cta_text: content[:cta_text],
        cta_url: content[:cta_url] || "#contact-form",
        meta_description: content[:meta_description],
        meta_keywords: content[:meta_keywords],
        ai_settings: {
          generated_at: Time.current,
          prompt: prompt,
          page_type: page_type,
          seo: {
            description: content[:meta_description],
            keywords: content[:meta_keywords]
          }
        }
      )
      
      # Generate image prompt for the hero section
      generate_image_prompt(landing_page, content[:image_prompt]) if content[:image_prompt].present?
    end
  end
  
  private
  
  def build_prompt(landing_page, description, page_type, business_profile, campaign)
    # Build a context-rich prompt for the OpenAI model
    prompt = "Create a compelling landing page for #{landing_page.title}.\n\n"
    
    # Add user description
    prompt += "DESCRIPTION FROM USER: #{description}\n\n"
    
    # Add page type
    prompt += "PAGE TYPE: #{page_type.titleize}\n"
    
    # Add business context if available
    if business_profile
      prompt += "\nBUSINESS CONTEXT:\n"
      prompt += "Business Name: #{business_profile['name']}\n"
      prompt += "Industry: #{business_profile['industry']}\n"
      prompt += "Description: #{business_profile['description']}\n"
    end
    
    # Add campaign context if available
    if campaign
      prompt += "\nCAMPAIGN CONTEXT:\n"
      prompt += "Campaign Name: #{campaign.name}\n"
      prompt += "Campaign Description: #{campaign.description}\n"
      prompt += "Email Template Subject: #{campaign.email_template&.subject}\n" if campaign.email_template
    end
    
    # Add requirements based on page type
    case page_type
    when 'lead_generation'
      prompt += "\nREQUIREMENTS:\n"
      prompt += "- Create a lead generation landing page that convinces visitors to sign up or provide their contact information\n"
      prompt += "- Create a compelling headline and subheadline that highlights the main value proposition\n"
      prompt += "- Include 3-4 benefit sections that clearly explain why someone should sign up\n"
      prompt += "- Suggest a strong call-to-action text for the sign-up button\n"
    when 'product_promotion'
      prompt += "\nREQUIREMENTS:\n"
      prompt += "- Create a product promotion landing page that showcases the product's features and benefits\n"
      prompt += "- Create a compelling headline and subheadline that highlights the product's value\n"
      prompt += "- Include 3-4 feature/benefit sections that clearly explain why someone should buy/try the product\n"
      prompt += "- Suggest pricing information and a strong call-to-action\n"
    when 'event_registration'
      prompt += "\nREQUIREMENTS:\n"
      prompt += "- Create an event registration landing page that encourages sign-ups for the event\n"
      prompt += "- Include event details like date, time, location (use placeholder text if unknown)\n"
      prompt += "- Highlight 3-4 reasons to attend or key speakers/activities\n"
      prompt += "- Create a compelling headline and clear registration call-to-action\n"
    end
    
    # Format requirements
    prompt += "\nRETURN FORMAT:\n"
    prompt += "Please return your response in valid JSON format with the following structure:\n"
    prompt += "{\n"
    prompt += '  "headline": "Main headline for the page",\n'
    prompt += '  "subheadline": "Supporting subheadline text",\n'
    prompt += '  "sections": [\n'
    prompt += '    {\n'
    prompt += '      "title": "Section title",\n'
    prompt += '      "content": "Section content with HTML formatting",\n'
    prompt += '      "type": "text_block|feature|testimonial|pricing|faq"\n'
    prompt += '    }\n'
    prompt += '  ],\n'
    prompt += '  "cta_text": "Sign Up Now",\n'
    prompt += '  "cta_url": "#form",\n'
    prompt += '  "meta_description": "SEO meta description for the page",\n'
    prompt += '  "meta_keywords": "keyword1, keyword2, keyword3",\n'
    prompt += '  "image_prompt": "A detailed description for generating the hero image"\n'
    prompt += "}\n"
    
    prompt
  end
  
  def call_openai_api(prompt)
    require 'net/http'
    require 'uri'
    require 'json'
    
    uri = URI.parse("https://api.openai.com/v1/chat/completions")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
    
    request.body = JSON.dump({
      "model" => "gpt-4o",
      "messages" => [
        {
          "role" => "system", 
          "content" => "You are an expert landing page creator with deep knowledge of conversion optimization and marketing psychology. Your task is to create compelling, effective landing page content based on the user's requirements."
        },
        {
          "role" => "user",
          "content" => prompt
        }
      ]
    })
    
    req_options = {
      use_ssl: uri.scheme == "https"
    }
    
    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end
    
    return nil unless response.code == "200"
    JSON.parse(response.body)
  rescue => e
    Rails.logger.error("Error calling OpenAI API: #{e.message}")
    nil
  end
  
  def process_openai_response(response_text)
    # Find and extract JSON from the response text
    json_match = response_text.match(/\{.*\}/m)
    return default_content unless json_match
    
    begin
      content = JSON.parse(json_match[0], symbolize_names: true)
      
      # Ensure we have all expected fields, or set defaults
      {
        headline: content[:headline] || "Welcome to our Landing Page",
        subheadline: content[:subheadline] || "Learn more about our amazing offering",
        sections: content[:sections] || [],
        cta_text: content[:cta_text] || "Sign Up Now",
        cta_url: content[:cta_url] || "#contact-form",
        meta_description: content[:meta_description] || "Landing page for our product or service",
        meta_keywords: content[:meta_keywords] || "landing page, marketing",
        image_prompt: content[:image_prompt] || "A professional image for a marketing landing page"
      }
    rescue JSON::ParserError => e
      Rails.logger.error("Error parsing OpenAI response: #{e.message}")
      default_content
    end
  end
  
  def default_content
    {
      headline: "Welcome to our Landing Page",
      subheadline: "Learn more about our amazing offering",
      sections: [
        {
          title: "Our Value Proposition",
          content: "<p>We help you achieve your goals with our innovative solutions.</p>",
          type: "text_block"
        }
      ],
      cta_text: "Sign Up Now",
      cta_url: "#contact-form",
      meta_description: "Landing page for our product or service",
      meta_keywords: "landing page, marketing",
      image_prompt: "A professional marketing landing page hero image"
    }
  end
  
  def generate_image_prompt(landing_page, image_prompt)
    # Store the image prompt
    current_prompts = landing_page.image_prompts || {}
    current_prompts['hero'] = image_prompt
    landing_page.update(image_prompts: current_prompts)
    
    # Queue the image generation job
    GenerateLandingPageImageJob.perform_later(landing_page.id, image_prompt, 'hero')
  end
end 