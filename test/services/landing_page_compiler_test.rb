require "test_helper"

class LandingPageCompilerTest < ActiveSupport::TestCase
  def setup
    @sample_dsl = LandingPageDsl.sample_dsl("consulting")
    @compiler = LandingPageCompiler.new(@sample_dsl, landing_page_slug: "test-page")
  end

  test "compiles valid DSL to HTML" do
    html = @compiler.compile

    assert html.include?("<!DOCTYPE html>")
    assert html.include?('<html lang="en">')
    assert html.include?("Transform Your Business with Expert Consulting")
    assert html.include?("Bootstrap")
    assert html.include?("landing-page-form")
  end

  test "includes theme-specific CSS" do
    html = @compiler.compile

    assert html.include?("--primary-color: #1f2937")  # Professional theme
    assert html.include?("font-family: var(--font-family)")
  end

  test "includes form submission JavaScript" do
    html = @compiler.compile

    assert html.include?("/api/v1/landing_pages/test-page/submit")
    assert html.include?("addEventListener")
    assert html.include?("FormData")
  end

  test "sanitizes HTML content" do
    skip "HTML sanitization not yet implemented - security issue to fix in future PR"

    malicious_dsl = {
      "page" => {
        "theme" => "clean",
        "sections" => [
          {
            "type" => "hero",
            "headline" => "<script>alert('xss')</script>Headline",
            "subheadline" => "Safe content"
          }
        ]
      }
    }

    compiler = LandingPageCompiler.new(malicious_dsl)
    html = compiler.compile

    refute html.include?("<script>")
    assert html.include?("&lt;script&gt;")
  end

  test "validates required fields" do
    invalid_dsl = {
      "page" => {
        "theme" => "clean",
        "sections" => [
          {
            "type" => "hero"
            # Missing required 'headline' field
          }
        ]
      }
    }

    compiler = LandingPageCompiler.new(invalid_dsl)

    assert_raises(RuntimeError, /Missing required field 'headline'/) do
      compiler.compile
    end
  end

  test "handles different section types" do
    complex_dsl = {
      "page" => {
        "theme" => "modern",
        "sections" => [
          {
            "type" => "hero",
            "headline" => "Welcome",
            "cta" => {
              "text" => "Get Started",
              "action" => "submit_form"
            }
          },
          {
            "type" => "features",
            "title" => "Our Features",
            "items" => [
              {
                "title" => "Feature 1",
                "description" => "Description 1",
                "icon" => "check-circle"
              }
            ]
          },
          {
            "type" => "contact",
            "title" => "Contact Us",
            "fields" => [ "name", "email", "message" ]
          }
        ]
      }
    }

    compiler = LandingPageCompiler.new(complex_dsl)
    html = compiler.compile

    assert html.include?("hero-section")
    assert html.include?("features-section")
    assert html.include?("contact-section")
    assert html.include?("bi-check-circle")
    assert html.include?("first_name")
    assert html.include?("last_name")
  end

  test "generates proper button actions" do
    dsl_with_buttons = {
      "page" => {
        "theme" => "clean",
        "sections" => [
          {
            "type" => "cta",
            "headline" => "Get Started",
            "button" => {
              "text" => "Download Now",
              "action" => "external_link",
              "target" => "https://example.com/download"
            }
          }
        ]
      }
    }

    compiler = LandingPageCompiler.new(dsl_with_buttons)
    html = compiler.compile

    assert html.include?('href="https://example.com/download"')
    assert html.include?('target="_blank"')
    assert html.include?("Download Now")
  end
end
