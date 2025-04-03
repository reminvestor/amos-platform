require 'openai'

class ConversationHandlerService
  attr_reader :crawler_job, :client
  
  # Stages of the conversation
  STAGE_ANALYZING = 'analyzing'
  STAGE_URL_FINDING = 'url_finding'
  STAGE_READY_FOR_GENERATION = 'ready_for_generation'
  
  def initialize(crawler_job)
    @crawler_job = crawler_job
    
    # Initialize OpenAI client
    @client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
  end
  
  def handle_message(user_message)
    # Add the user's message to the conversation
    crawler_job.add_message('user', user_message)
    
    # Determine the current stage
    current_stage = determine_stage
    
    # Update conversation stage if needed
    crawler_job.update(conversation_stage: current_stage) unless crawler_job.conversation_stage == current_stage
    
    # Check if we're stuck in URL finding stage (multiple errors)
    if current_stage == STAGE_URL_FINDING && url_finding_may_be_stuck?
      # Auto-skip URL finding if it appears to be stuck
      crawler_job.add_log("Auto-skipping URL finding stage due to repeated errors", "warning")
      
      # Fall back to domains from conversation or example.com
      domains = extract_domains_from_conversation
      if domains.any?
        crawler_job.update(target_urls: domains.join(','))
        domains.each { |domain| crawler_job.add_log("Auto-using domain as fallback: #{domain}", "warning") }
      else
        placeholder = "https://example.com"
        crawler_job.update(target_urls: placeholder)
        crawler_job.add_log("Auto-using generic placeholder URL: #{placeholder}", "warning")
      end
      
      # Move to next stage
      crawler_job.update(conversation_stage: STAGE_READY_FOR_GENERATION)
      
      # Send message to user
      auto_skip_message = "I notice we're having trouble finding specific URLs. I'll continue with placeholders based on our conversation. You can always adjust the code later if needed.\n\nLet's move on to generating your crawler. Are you ready to proceed?"
      crawler_job.add_message('assistant', auto_skip_message)
      return auto_skip_message
    end
    
    # Handle based on the stage
    case current_stage
    when STAGE_ANALYZING
      handle_analysis(user_message)
    when STAGE_URL_FINDING
      handle_url_finding(user_message) 
    when STAGE_READY_FOR_GENERATION
      handle_ready_for_generation(user_message)
    else
      general_response(user_message)
    end
  end
  
  # Generate initial clarifying questions based on the description
  def generate_initial_questions(description)
    # Create a specialized prompt for initial questions
    system_prompt = <<~PROMPT
      You are an AI assistant helping users create web crawlers to find contact information (first name, last name, email).
      
      The user has provided a brief description of what they want. Your job is to ask specific, clarifying questions to gather all the information needed to create an effective crawler.
      
      System capabilities:
      1. The crawler will be built in Python using requests and BeautifulSoup4
      2. Can extract data from publicly available web pages (no login-protected content)
      3. Can follow links and navigate pagination within the same domain
      4. Can handle simple JavaScript-rendered content with appropriate delays
      5. Can filter and validate emails to ensure they match expected formats
      
      Based on their description, ask about:
      1. Specific website(s) they want to target (ask for exact URLs if possible)
      2. What sections or pages of the website contain the contact information
      3. How to identify the right people (job titles, departments, etc.)
      4. If there are specific formats or patterns for the contact information
      5. How many contacts they're hoping to collect (for pagination/limits)
      
      Ask 2-3 focused questions that would help you understand exactly what they need from their crawler.
      Be conversational but direct, and focus on the specific information needed for crawler creation.
    PROMPT
    
    # Prepare a specific prompt using the description
    user_prompt = <<~PROMPT
      Based on this brief description: "#{description}"
      
      Ask me 2-3 clarifying questions about exactly what kind of web crawler I need. Focus on understanding which websites to target and what specific contact information I'm looking for.
    PROMPT
    
    # Call OpenAI API
    response = client.chat(
      parameters: {
        model: "gpt-4o",
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: user_prompt }
        ],
        temperature: 0.7
      }
    )
    
    # Get assistant response
    questions = response.dig('choices', 0, 'message', 'content')
    
    # Add the questions to the conversation
    crawler_job.add_message('assistant', questions)
    
    # Return the questions in case we need them elsewhere
    questions
  end
  
  private
  
  def determine_stage
    # If we've already found URLs, we're ready for generation
    return STAGE_READY_FOR_GENERATION if crawler_job.target_urls.present?
    
    # If we're already in URL finding stage, stay there
    return STAGE_URL_FINDING if crawler_job.conversation_stage == STAGE_URL_FINDING
    
    # Get the most recent messages to analyze
    messages = crawler_job.crawler_conversations.order(timestamp: :desc).limit(5)
    
    # If we're at the beginning or in the initial analyzing phase
    if messages.size <= 2 || crawler_job.conversation_stage == STAGE_ANALYZING
      return STAGE_ANALYZING
    end
    
    # Check if the last assistant message indicates we're ready to find URLs
    last_assistant_msg = messages.find { |m| m.role == 'assistant' }&.content.to_s.downcase
    
    if last_assistant_msg.include?('what specific website') || 
       last_assistant_msg.include?('which website') ||
       last_assistant_msg.include?('target site') ||
       last_assistant_msg.include?('target website')
      return STAGE_URL_FINDING
    end
    
    # Default to analyzing
    STAGE_ANALYZING
  end
  
  def handle_analysis(user_message)
    # Create prompt for analysis with more detailed system capabilities
    system_prompt = <<~PROMPT
      You are an AI assistant helping users create web crawlers to find contact information (first name, last name, email).
      
      Your job is to understand what the user wants to accomplish and guide them through providing the necessary details.
      Ask clarifying questions to get complete information.
      
      System capabilities:
      1. The crawler will be built in Python using the requests library and BeautifulSoup4
      2. We can extract data from HTML pages, including those with simple JavaScript
      3. We can follow links, handle pagination, and navigate through site sections
      4. We can parse and extract structured data from tables, lists, and directories
      5. We can filter results based on keywords, job titles, locations, etc.
      6. We can export first name, last name, and email addresses to the user's database
      7. We can handle rate limiting and use appropriate delays to avoid being blocked
      8. We will respect robots.txt and site terms of service
      
      Important things to ask about:
      1. What specific websites or web pages they want to crawl (get exact URLs when possible)
      2. What kind of contacts they're looking for (e.g., real estate agents, doctors, etc.)
      3. Any specific sections of the websites to focus on, like staff directories
      4. Any specific criteria for filtering contacts (location, job title, etc.)
      5. How many contacts they expect to find and if there are pagination concerns
      
      Once you have clear information about the target websites and what to extract, you can 
      indicate that we're ready to search for specific URLs by saying something like:
      "Great! Let me now search for the specific URLs we'll need to crawl on [website name]."
      
      Keep your responses clear, helpful, and focused on getting the information needed to create an effective crawler.
    PROMPT
    
    # Get conversation history for context
    messages = build_message_history(system_prompt)
    
    # Call OpenAI API
    response = client.chat(
      parameters: {
        model: "gpt-4o",
        messages: messages,
        temperature: 0.7
      }
    )
    
    # Get and save assistant response
    assistant_response = response.dig('choices', 0, 'message', 'content')
    crawler_job.add_message('assistant', assistant_response)
    
    # Check if we should transition to URL finding
    if assistant_response.downcase.include?('specific urls') || 
       assistant_response.downcase.include?('search for') ||
       assistant_response.downcase.match?(/ready to (find|look for|discover)/)
      # If the response indicates it's time to find URLs, update the stage
      crawler_job.update(conversation_stage: STAGE_URL_FINDING)
    end
    
    # Return the response for the controller
    assistant_response
  end
  
  def handle_url_finding(user_message)
    # Check for manual bypass keywords
    bypass_keywords = ['skip', 'bypass', 'continue', 'next', 'manual', 'move on', 'stuck']
    
    # If user is trying to bypass this stage
    if bypass_keywords.any? { |keyword| user_message.downcase.include?(keyword) }
      # Create a friendly response explaining what's happening
      bypass_response = "I understand you'd like to move forward. Let's proceed to the next step.\n\n"
      
      # Check if user provided URLs manually
      urls = user_message.scan(/(https?:\/\/[^\s\)\]\"\']+)/).flatten.uniq
      
      if urls.any?
        bypass_response += "I've captured these URLs from your message:\n"
        urls.each { |url| bypass_response += "• #{url}\n" }
        crawler_job.update(target_urls: urls.join(','))
        urls.each { |url| crawler_job.add_log("Manually added URL: #{url}", "info") }
      else
        # If no URLs provided, use a placeholder URL and explain
        bypass_response += "No specific URLs were found in your message. I'll use placeholder URLs based on our conversation, but you may need to edit the crawler code later to target the right pages."
        
        # Extract domain names from the conversation history to use as placeholders
        domains = extract_domains_from_conversation
        if domains.any?
          crawler_job.update(target_urls: domains.join(','))
          domains.each { |domain| crawler_job.add_log("Using domain as placeholder: #{domain}", "warning") }
        else
          # Last resort placeholder
          placeholder = "https://example.com"
          crawler_job.update(target_urls: placeholder)
          crawler_job.add_log("Using generic placeholder URL: #{placeholder}", "warning")
        end
      end
      
      # Move to next stage
      crawler_job.update(conversation_stage: STAGE_READY_FOR_GENERATION)
      
      # Make sure we add the message to the conversation
      begin
        crawler_job.add_message('assistant', bypass_response)
      rescue => e
        crawler_job.add_log("Error adding bypass response to conversation: #{e.message}", "error")
        # Create a simplified response if there was an error
        bypass_response = "I'll continue with the crawler generation process. Moving to the next step."
        crawler_job.add_message('assistant', bypass_response)
      end
      
      return bypass_response
    end
    
    # Create prompt for URL finding with web search and more specific guidance
    system_prompt = <<~PROMPT
      You are an AI assistant helping users find the most relevant URLs for web crawling to collect contact information.
      
      Based on the conversation history, you need to identify and validate specific URLs that would contain the contact information the user is looking for.
      
      When searching for URLs, focus on:
      1. Staff/team/about pages that list employees with contact information
      2. Directory pages that contain listings of professionals
      3. Contact pages that might have departmental or individual emails
      4. Result pages from internal search functions (note URL patterns for parameters)
      5. Pages with lists that can be paginated (look for pagination patterns in URLs)
      
      Use the web search tool to:
      1. Find exact, current URLs for the websites mentioned by the user
      2. Verify the URLs are accessible and contain the kind of contact information needed
      3. Identify multiple relevant pages within the site (not just the homepage)
      4. Check for any robots.txt restrictions that might affect crawling
      5. Identify URL patterns for pages that follow a consistent structure
      
      Your goal is to provide 3-8 SPECIFIC, CRAWLABLE URLs that will serve as starting points for the web crawler.
      
      Format your final response as:
      1. A brief explanation of the URLs you found and how they relate to the user's needs
      2. A bulleted list of the exact, complete URLs (including https://)
      3. Brief notes on what kind of contact information each URL contains
      
      Important: The crawler needs fully-formed, direct URLs that point to pages containing contact information.
      
      If you're having trouble finding specific URLs, simply explain this to the user and ask them 
      to provide the URLs directly, or suggest they type "skip" to move forward with the process.
    PROMPT
    
    # Get conversation history for context
    messages = build_message_history(system_prompt)
    
    begin
      # Set a Timeout to ensure the API call doesn't hang indefinitely
      Timeout.timeout(30) do
        # Call OpenAI API with web search enabled
        response = client.chat(
          parameters: {
            model: "gpt-4o",
            messages: messages,
            tools: [{ type: "web_search_preview" }],
            temperature: 0.7
          }
        )
        
        # Extract assistant's response and tool calls
        message_content = response.dig('choices', 0, 'message', 'content')
        
        # Extract URLs from the response using regex - look for http/https links
        urls = message_content.scan(/(https?:\/\/[^\s\)\]\"\']+)/).flatten.uniq
        
        # If URLs were found, store them
        if urls.any?
          crawler_job.update(target_urls: urls.join(','))
          crawler_job.update(conversation_stage: STAGE_READY_FOR_GENERATION)
          crawler_job.add_log("Found #{urls.count} target URLs", "info")
          # Also log the actual URLs for reference
          urls.each do |url|
            crawler_job.add_log("Target URL: #{url}", "info")
          end
        else
          # If no URLs found, add a special note asking for manual input
          not_found_message = "It seems I couldn't identify specific URLs from the search results. You can:\n\n" +
            "1. Provide the specific URLs you want to crawl\n" +
            "2. Type 'skip' to continue without specific URLs\n" +
            "3. Give me more details about the exact website(s) you want to target"
          
          if !message_content.include?("couldn't") && !message_content.include?("unable") && !message_content.include?("skip")
            message_content += "\n\n" + not_found_message
          end
        end
        
        # Save and return the assistant response
        crawler_job.add_message('assistant', message_content)
        message_content
      end
    rescue Timeout::Error => e
      # Handle timeout specifically
      timeout_message = "I'm having trouble finding the URLs within the time limit. Let's proceed with what we have.\n\n" +
        "You can:\n" +
        "1. Provide specific URLs directly\n" +
        "2. Type 'skip' to continue with placeholder URLs based on our conversation\n" +
        "3. Try again with more specific website details"
      
      crawler_job.add_log("Timeout in URL finding: Search took too long", "error")
      crawler_job.add_message('assistant', timeout_message)
      timeout_message
    rescue => e
      # Handle other API errors
      error_message = "I encountered an issue while searching for URLs: #{e.message.to_s.truncate(100)}\n\n" +
        "You can help by:\n" +
        "1. Providing the specific URLs you want to crawl directly\n" +
        "2. Typing 'skip' to continue without specific URLs\n" +
        "3. Trying again with more specific website names"
      
      crawler_job.add_log("Error in URL finding: #{e.message.to_s.truncate(200)}", "error")
      crawler_job.add_message('assistant', error_message)
      error_message
    end
  end
  
  # Helper method to extract domain names from conversation
  def extract_domains_from_conversation
    domains = []
    begin
      conversations = crawler_job.crawler_conversations.order(timestamp: :desc).limit(15)
      
      conversations.each do |convo|
        next unless convo.content.is_a?(String)
        # Look for website mentions with common TLDs
        convo.content.scan(/\b([\w-]+\.(com|org|net|edu|gov|io|co))\b/i).each do |match|
          domains << "https://www.#{match[0]}"
        end
      end
    rescue => e
      crawler_job.add_log("Error extracting domains: #{e.message}", "error")
    end
    
    domains.uniq
  end
  
  def handle_ready_for_generation(user_message)
    # Create prompt for final confirmation with more details about what will happen
    system_prompt = <<~PROMPT
      You are an AI assistant helping users create web crawlers to find contact information.
      
      The user has provided enough information, and we have identified the target URLs.
      
      Your job now is to:
      1. Summarize what the crawler will do based on the conversation
      2. Confirm with the user that we're ready to generate the crawler
      
      In your summary, include:
      - Which websites/URLs will be crawled
      - What type of contact information will be collected
      - Any specific filtering criteria that will be applied
      - Approximately how many contacts the crawler might find
      
      After summarizing, ask if they're ready to proceed with generation, or if they have any final requirements to add.
      
      If they confirm or say yes, respond with enthusiasm and let them know the generation is starting.
      Include the exact phrase "READY_TO_GENERATE" somewhere in your response so our system knows to begin.
      
      Also explain what will happen next:
      1. We'll generate a custom Python crawler (this takes 1-2 minutes)
      2. We'll automatically test the crawler in a safe environment
      3. We'll fix any issues that arise (up to 3 attempts)
      4. We'll provide the ready-to-use crawler when finished
    PROMPT
    
    # Get conversation history for context
    messages = build_message_history(system_prompt)
    
    # Check if the user message indicates readiness to generate
    ready_signals = ['yes', 'generate', 'ready', 'proceed', 'let\'s go', 'start', 'create', 'make', 'sounds good', 'go ahead', 'do it']
    if ready_signals.any? { |signal| user_message.downcase.include?(signal) }
      # Prepare a response that includes the trigger phrase
      assistant_response = "Great! I'll start generating your custom web crawler now. READY_TO_GENERATE\n\n" +
        "Here's what will happen:\n\n" +
        "1. First, I'll generate a Python crawler script specifically designed to extract contacts from the URLs we identified (1-2 minutes)\n" +
        "2. Then, I'll automatically test the crawler to make sure it works properly\n" +
        "3. If any issues are found, I'll fix them automatically (up to 3 improvement attempts)\n" +
        "4. Once everything is working correctly, the crawler will be ready for you to run\n\n" +
        "You'll see the progress in the status panel on the right side of the screen. I'll let you know when everything is ready!"
      
      # Add to conversation
      crawler_job.add_message('assistant', assistant_response)
      
      # Queue the crawler generation job
      GenerateCrawlerCodeJob.perform_later(crawler_job.id)
      crawler_job.update(status: 'generating')
      
      return assistant_response
    end
    
    # If not ready yet, have a normal conversation
    response = client.chat(
      parameters: {
        model: "gpt-4o",
        messages: messages,
        temperature: 0.7
      }
    )
    
    # Get and save assistant response
    assistant_response = response.dig('choices', 0, 'message', 'content')
    crawler_job.add_message('assistant', assistant_response)
    
    # If the response includes the trigger phrase, queue the job
    if assistant_response.include?('READY_TO_GENERATE')
      GenerateCrawlerCodeJob.perform_later(crawler_job.id)
      crawler_job.update(status: 'generating')
    end
    
    assistant_response
  end
  
  def general_response(user_message)
    # For any other stage, just have a conversation
    system_prompt = <<~PROMPT
      You are an AI assistant helping users create web crawlers to find contact information.
      
      Respond to the user's message in a helpful, friendly manner.
      Focus on answering their questions about the crawler, the process, or providing assistance.
    PROMPT
    
    # Get conversation history for context
    messages = build_message_history(system_prompt)
    
    # Call OpenAI API
    response = client.chat(
      parameters: {
        model: "gpt-4o",
        messages: messages,
        temperature: 0.7
      }
    )
    
    # Get and save assistant response
    assistant_response = response.dig('choices', 0, 'message', 'content')
    crawler_job.add_message('assistant', assistant_response)
    
    # Return the response for the controller
    assistant_response
  end
  
  def build_message_history(system_prompt)
    messages = [{ role: 'system', content: system_prompt }]
    
    # Add conversation history, limited to the last 10 messages
    conversation_history = crawler_job.crawler_conversations.order(timestamp: :asc).last(10)
    
    conversation_history.each do |message|
      messages << { role: message.role, content: message.content }
    end
    
    messages
  end
  
  # Check if we might be stuck in URL finding stage
  def url_finding_may_be_stuck?
    # Only check if we're in URL finding stage
    return false unless crawler_job.conversation_stage == STAGE_URL_FINDING
    
    # Get recent logs to check for errors
    recent_logs = crawler_job.crawler_job_logs.where(log_level: 'error').order(created_at: :desc).limit(3)
    
    # Check if there are at least 2 recent error logs from URL finding
    url_finding_errors = recent_logs.count { |log| log.message.include?('URL finding') }
    
    # Check if there have been multiple back-and-forth messages in URL finding stage
    conversation_count = crawler_job.crawler_conversations.where("created_at > ?", 2.minutes.ago).count
    
    # We're stuck if we have multiple errors or lots of back-and-forth with no progress
    url_finding_errors >= 2 || (url_finding_errors >= 1 && conversation_count >= 6)
  end
end 