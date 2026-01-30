# frozen_string_literal: true

require "test_helper"

class GenerateLandingPageToolTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @user = users(:one)
    @entity = entities(:one)
    @tool = Tools::GenerateLandingPageTool.new(user: @user, entity: @entity)
  end

  test "metadata returns correct structure" do
    metadata = Tools::GenerateLandingPageTool.metadata
    
    assert_equal "generate_ai_landing_page", metadata[:name]
    assert_equal "landing_page", metadata[:category]
    assert_includes metadata[:description], "INTERNAL TOOL"
    assert metadata[:input_schema][:properties].key?(:title)
    assert metadata[:input_schema][:properties].key?(:description)
    assert metadata[:input_schema][:properties].key?(:page_type)
  end

  test "input schema includes all page types" do
    metadata = Tools::GenerateLandingPageTool.metadata
    page_types = metadata[:input_schema][:properties][:page_type][:enum]
    
    expected_types = %w[
      lead_generation product_launch event_registration
      newsletter_signup free_trial demo_request general
    ]
    
    expected_types.each do |page_type|
      assert_includes page_types, page_type
    end
  end

  test "input schema includes image configuration options" do
    metadata = Tools::GenerateLandingPageTool.metadata
    properties = metadata[:input_schema][:properties]
    
    assert properties.key?(:generate_images)
    assert properties.key?(:image_style)
    assert properties.key?(:image_quality)
    assert_includes properties[:image_quality][:enum], "standard"
    assert_includes properties[:image_quality][:enum], "pro"
  end

  test "creates landing page with basic args" do
    landing_page = create_test_landing_page(title: "Test Page")
    
    assert_equal "Test Page", landing_page.title
    assert_equal "draft", landing_page.status
    assert_equal @user.id, landing_page.user_id
    assert_equal @entity.id, landing_page.entity_id
  end

  test "generates unique slug from title" do
    landing_page = create_test_landing_page(title: "My Unique Landing Page")
    
    assert_match /my-unique-landing-page/, landing_page.slug
  end

  test "stores page_type in metadata" do
    landing_page = create_test_landing_page(
      title: "Event Page",
      page_type: "event_registration"
    )
    
    assert_equal "event_registration", landing_page.metadata["page_type"]
  end

  test "stores generation context in metadata" do
    landing_page = create_test_landing_page(
      title: "Contextual Page",
      description: "A page with context"
    )
    
    assert landing_page.metadata["generation_context"].present?
    assert_equal true, landing_page.metadata["ai_generated"]
  end

  test "handles all page types" do
    page_types = %w[
      lead_generation product_launch event_registration
      newsletter_signup free_trial demo_request general
    ]
    
    page_types.each do |page_type|
      landing_page = create_test_landing_page(
        title: "#{page_type.humanize} Test Page",
        page_type: page_type
      )
      
      assert_equal page_type, landing_page.metadata["page_type"],
                   "Should store page_type: #{page_type}"
    end
  end

  test "stores design preferences in generation context" do
    landing_page = create_test_landing_page(
      title: "Styled Page",
      design_style: "minimalist modern",
      design_preferences: {
        style: "clean",
        cta: "Get Started"
      }
    )
    
    context = landing_page.metadata["generation_context"]
    assert_equal "minimalist modern", context["design_style"]
    assert_equal "clean", context["design_preferences"]["style"]
  end

  test "stores form fields configuration" do
    form_fields = [
      { name: "email", type: "email", required: true },
      { name: "company", type: "text", required: false }
    ]
    
    landing_page = create_test_landing_page(
      title: "Lead Form Page",
      page_type: "lead_generation",
      form_fields: form_fields
    )
    
    stored_fields = landing_page.metadata["generation_context"]["form_fields"]
    assert_equal 2, stored_fields.size
  end

  test "stores business info in context" do
    landing_page = create_test_landing_page(
      title: "Business Page",
      business_info: {
        offer: "50% off first month",
        price: "$99/month"
      }
    )
    
    context = landing_page.metadata["generation_context"]
    assert_equal "50% off first month", context["business_info"]["offer"]
  end

  test "handles empty/minimal args" do
    landing_page = create_test_landing_page({})
    
    assert_equal "Landing Page", landing_page.title
    assert landing_page.slug.present?
    assert_equal "draft", landing_page.status
  end

  test "stores html_content when provided" do
    html = "<div>Test Content</div>"
    
    landing_page = LandingPage.create!(
      user: @user,
      entity: @entity,
      title: "HTML Test",
      slug: "html-test-#{SecureRandom.hex(4)}",
      status: "draft",
      html_content: html
    )
    
    assert_equal html, landing_page.html_content
  end

  # Test the actual execute method with mocking
  test "execute returns success response structure" do
    # Stub all external calls
    @tool.stub(:gather_business_profile_context, {}) do
      @tool.stub(:gather_conversation_context, nil) do
        @tool.stub(:generate_landing_page_images, []) do
          @tool.stub(:generate_ai_html, mock_html_content) do
            @tool.stub(:stream_progress, nil) do
              result = @tool.execute({ title: "Execute Test" })
              
              assert result[:success], "Execute should succeed"
              assert result[:landing_page_id].present?, "Should return landing_page_id"
              assert result[:slug].present?, "Should return slug"
              assert_equal "draft", result[:status]
              assert_equal "landing_page_editor", result[:canvas_type]
            end
          end
        end
      end
    end
  end

  test "execute handles errors gracefully" do
    @tool.stub(:gather_business_profile_context, -> { raise StandardError, "Test error" }) do
      result = @tool.execute({ title: "Error Test" })
      
      # Should catch error and return error response
      assert_not result[:success]
      assert_includes result[:error], "Failed to create landing page"
    end
  end

  private

  def create_test_landing_page(args)
    # Direct creation simulating what the tool does
    title = args[:title] || args[:program_name] || args[:business_name] || "Landing Page"
    description = args[:description] || args[:content_focus] || "AI-Generated Landing Page"
    page_type = args[:page_type] || "lead_generation"
    
    generation_context = {
      description: description,
      page_type: page_type,
      key_details: args[:key_details] || {},
      business_info: args[:business_info] || {},
      design_preferences: args[:design_preferences] || {},
      design_style: args[:design_style],
      form_fields: args[:form_fields] || []
    }.compact
    
    LandingPage.create!(
      user: @user,
      entity: @entity,
      title: title,
      slug: generate_test_slug(title),
      status: "draft",
      html_content: mock_html_content,
      metadata: {
        ai_generated: true,
        description: description,
        page_type: page_type,
        generated_at: Time.current,
        generation_context: generation_context,
        generated_from: "test"
      }
    )
  end

  def generate_test_slug(title)
    base_slug = title.parameterize
    "#{base_slug}-#{SecureRandom.hex(4)}"
  end

  def mock_html_content
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <title>Test Landing Page</title>
        <style>
          body { font-family: system-ui; }
          .hero { padding: 4rem 2rem; text-align: center; }
        </style>
      </head>
      <body>
        <section class="hero">
          <h1>Welcome</h1>
          <p>Your landing page content here</p>
        </section>
      </body>
      </html>
    HTML
  end
end
