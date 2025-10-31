class GenerateLandingPageClarificationJob < ApplicationJob
  queue_as :default

  def perform(landing_page_id, description, entity_id, business_profile_id = nil)
    landing_page = LandingPage.find(landing_page_id)
    entity = Entity.find(entity_id)
    business_profile = business_profile_id ? BusinessProfile.find(business_profile_id) : nil

    # Build context for AI
    context = {
      description: description,
      business_profile: business_profile,
      entity: entity
    }

    # Generate clarification questions using AI
    questions = generate_clarification_questions(context)

    # Store questions in the landing page
    landing_page.update!(clarification_questions: questions)

    Rails.logger.info "Generated #{questions.length} clarification questions for landing page #{landing_page_id}"

  rescue => e
    Rails.logger.error "Error generating clarification questions for landing page #{landing_page_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Store empty questions array so the UI knows generation failed
    landing_page&.update(clarification_questions: [])
  end

  private

  def generate_clarification_questions(context)
    system_prompt = "You are an expert landing page consultant who asks clarifying questions to create better landing pages."
    user_prompt = build_clarification_prompt(context)

    # Use Claude to generate questions
    response = AiServiceHelper.get_service.send_message(system_prompt, user_prompt)

    # Parse the response to extract questions
    parse_questions_response(response)
  end

  def build_clarification_prompt(context)
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

    "You are an expert landing page consultant. A user wants to create a landing page and has provided this description:

\"#{context[:description]}\"

#{business_context}

Based on this information, determine if you need to ask clarifying questions to create an effective landing page. If the description is comprehensive and clear, return an empty array. If you need more information, ask 2-5 focused questions that will help you create a better landing page.

Return your response as a JSON array of question objects, where each question has:
- id: a unique identifier
- question: the question text
- type: 'text' for text input, 'choice' for multiple choice, 'boolean' for yes/no
- options: array of options (only for choice type)
- required: true/false

Examples:
- If asking about the main goal: {\"id\": \"goal\", \"question\": \"What is the primary goal of this landing page?\", \"type\": \"choice\", \"options\": [\"Generate leads\", \"Sell a product\", \"Event registration\", \"Newsletter signup\"], \"required\": true}
- If asking about target audience: {\"id\": \"audience\", \"question\": \"Who is your target audience for this landing page?\", \"type\": \"text\", \"required\": true}
- If asking about urgency: {\"id\": \"urgency\", \"question\": \"Do you want to create urgency or scarcity in your messaging?\", \"type\": \"boolean\", \"required\": false}

Only ask questions that are not already answered in the description or business profile. Keep it concise and focused.

Return only the JSON array, no other text."
  end

  def parse_questions_response(response)
    begin
      # Extract JSON from response
      json_match = response.match(/\[.*\]/m)
      if json_match
        JSON.parse(json_match[0])
      else
        []
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Error parsing clarification questions response: #{e.message}"
      []
    end
  end
end
