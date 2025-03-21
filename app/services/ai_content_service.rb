require 'openai'

class AiContentService
  attr_reader :client
  
  DEFAULT_MODEL = "gpt-4o"
  
  def initialize
    @client = OpenAI::Client.new(
      access_token: ENV['OPENAI_API_KEY'],
      request_timeout: 240
    )
  end
  
  # Generate email content based on parameters
  def generate_email_content(params)
    prompt = build_prompt(params)
    
    response = client.chat(
      parameters: {
        model: DEFAULT_MODEL,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: prompt }
        ],
        temperature: 0.7
      }
    )
    
    parse_response(response)
  end
  
  # Generate improved content based on analytics
  def improve_content(original_content, stats, audience)
    prompt = build_improvement_prompt(original_content, stats, audience)
    
    response = client.chat(
      parameters: {
        model: DEFAULT_MODEL,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: prompt }
        ],
        temperature: 0.7
      }
    )
    
    parse_response(response)
  end
  
  # Extract insights from campaign analytics
  def analyze_campaign_results(campaign)
    stats = {
      open_rate: campaign.open_rate,
      click_rate: campaign.click_rate,
      sent_count: campaign.sent_count,
      total_contacts: campaign.contact_count
    }
    
    prompt = "Analyze these email campaign results and provide actionable insights:\n\n" +
             "Campaign: #{campaign.name}\n" +
             "Sent to: #{stats[:total_contacts]} recipients\n" +
             "Open rate: #{stats[:open_rate]}%\n" +
             "Click rate: #{stats[:click_rate]}%\n\n" +
             "Provide 3-5 specific recommendations for improving this campaign."
    
    response = client.chat(
      parameters: {
        model: DEFAULT_MODEL,
        messages: [
          { role: "system", content: "You are an expert marketing analyst providing actionable insights based on email campaign data." },
          { role: "user", content: prompt }
        ],
        temperature: 0.5
      }
    )
    
    parse_response(response)
  end
  
  private
  
  def system_prompt
    "You are an expert email marketing copywriter. Your task is to write compelling, " +
    "personalized email content that drives engagement. Write in a conversational, " +
    "friendly tone that connects with readers. Focus on providing value and clear calls to action. " +
    "Avoid spammy language and all-caps text. Always format your response as clean HTML."
  end
  
  def build_prompt(params)
    audience = params[:audience] || "general subscribers"
    purpose = params[:purpose] || "newsletter"
    tone = params[:tone] || "professional"
    product = params[:product] || ""
    length = params[:length] || "medium"
    specific_points = params[:specific_points] || []
    
    prompt = "Write a compelling #{purpose} email for #{audience}."
    prompt += " The tone should be #{tone}."
    
    if product.present?
      prompt += " The email should focus on our product: #{product}."
    end
    
    if specific_points.any?
      prompt += " Include these specific points:\n"
      specific_points.each do |point|
        prompt += "- #{point}\n"
      end
    end
    
    case length
    when "short"
      prompt += " Keep it brief, around 100-150 words."
    when "medium"
      prompt += " Write a medium-length email, around 200-250 words."
    when "long"
      prompt += " Create a comprehensive email, around 300-400 words."
    end
    
    prompt += "\n\nInclude a subject line, greeting, body, and signature. Format as clean HTML."
    prompt
  end
  
  def build_improvement_prompt(original_content, stats, audience)
    "The following email has these performance metrics:\n" +
    "- Open rate: #{stats[:open_rate]}%\n" +
    "- Click rate: #{stats[:click_rate]}%\n\n" +
    "The target audience is: #{audience}\n\n" +
    "Original email content:\n#{original_content}\n\n" +
    "Please rewrite this email to improve engagement and conversion. " +
    "Keep the same general purpose but make it more compelling and effective. " +
    "Format as clean HTML and explain your key improvements at the end."
  end
  
  def parse_response(response)
    if response.dig("choices", 0, "message", "content")
      response.dig("choices", 0, "message", "content").strip
    else
      "Error generating content. Please try again."
    end
  end
end 