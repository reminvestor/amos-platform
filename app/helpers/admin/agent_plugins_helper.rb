module Admin
  module AgentPluginsHelper
    def test_prompt_for_agent(agent_plugin)
      case agent_plugin.slug
      when 'email_sequence_architect'
        "Create a 5-email welcome sequence for new trial users of a SaaS product"
      when 'social_media_content_generator'
        "Turn this product launch announcement into social media posts for Twitter, LinkedIn, and Facebook: 'We're excited to announce our new AI-powered analytics dashboard!'"
      when 'seasonal_campaign_planner'
        "What campaigns should I run in the next 60 days for my coffee shop?"
      when 'review_response_agent'
        "Respond to this 3-star Google review: 'Food was good but service was slow. Waited 20 minutes for our order.'"
      when 'sales_email_generator'
        "Generate a sales email for a potential customer interested in our marketing automation platform"
      when 'content_quality_analyzer'
        "Analyze this blog post for readability and SEO: 'Marketing automation is important for businesses...'"
      when 'campaign_optimizer'
        "Analyze our recent email campaign performance and suggest improvements"
      when 'ai_landing_page_creator'
        "Create a landing page for a new productivity app targeting remote workers"
      else
        # Default based on role
        case agent_plugin.role
        when 'executor'
          "Execute a task using #{agent_plugin.name}"
        when 'planner'
          "Plan a strategy for #{agent_plugin.name.downcase}"
        when 'analyst'
          "Analyze data using #{agent_plugin.name}"
        when 'verifier'
          "Verify the quality of this content: 'Sample content here...'"
        else
          "Test #{agent_plugin.name}"
        end
      end
    end

    def test_context_for_agent(agent_plugin)
      case agent_plugin.slug
      when 'email_sequence_architect'
        {
          target_audience: "SaaS trial users",
          business_type: "B2B software",
          conversion_goal: "Convert to paid subscription"
        }
      when 'social_media_content_generator'
        {
          platforms: ["twitter", "linkedin", "facebook"],
          tone: "professional yet friendly",
          post_count: 10
        }
      when 'seasonal_campaign_planner'
        {
          business_type: "coffee shop",
          location: "Seattle, WA",
          timeframe_days: 60
        }
      when 'review_response_agent'
        {
          platform: "google",
          star_rating: 3,
          business_type: "restaurant"
        }
      when 'sales_email_generator'
        {
          lead_name: "Sarah Johnson",
          company_name: "TechCorp Inc",
          pain_points: ["manual processes", "lack of analytics"]
        }
      when 'content_quality_analyzer'
        {
          content_type: "blog_post",
          target_seo_score: 80
        }
      when 'campaign_optimizer'
        {
          campaign_type: "email",
          time_range: "last 30 days"
        }
      when 'ai_landing_page_creator'
        {
          product_name: "FocusTime",
          target_audience: "remote workers",
          key_benefits: ["time tracking", "focus sessions", "productivity insights"]
        }
      else
        # Default context
        {
          test_mode: true,
          agent_slug: agent_plugin.slug
        }
      end
    end
  end
end
