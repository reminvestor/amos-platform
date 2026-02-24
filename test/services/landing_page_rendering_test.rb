# frozen_string_literal: true

require "test_helper"

class LandingPageRenderingTest < ActiveSupport::TestCase
  # Test the LandingPageRendering concern methods in isolation
  # using a simple test harness class
  class RenderingHarness
    include LandingPageRendering
    public :ensure_html_structure, :close_unclosed_tags_inline,
           :strip_malformed_scripts, :sanitize_form_attributes,
           :strip_editing_attributes
  end

  setup do
    @renderer = RenderingHarness.new
  end

  # ═══════════════════════════════════════════════════════════════
  # close_unclosed_tags_inline — the core fix for raw JS leaks
  # ═══════════════════════════════════════════════════════════════

  test "close_unclosed_tags_inline closes orphaned script before next HTML tag" do
    html = '<script>var x = 1;<div class="content">Hello</div>'
    result = @renderer.close_unclosed_tags_inline(html, "script")

    assert_includes result, "</script>"
    assert result.index("</script>") < result.index('<div class="content">')
  end

  test "close_unclosed_tags_inline does not swallow content after orphaned script" do
    html = <<~HTML
      <section id="hero"><h1>Welcome</h1></section>
      <script>console.log("started
      <section id="benefits"><h2>Benefits</h2><p>Great stuff</p></section>
      <footer>Footer content</footer>
    HTML

    result = @renderer.close_unclosed_tags_inline(html, "script")

    assert_includes result, "</script>"
    assert_includes result, '<section id="benefits">'
    assert_includes result, "Benefits"
    assert_includes result, "Footer content"
  end

  test "close_unclosed_tags_inline handles multiple unclosed scripts" do
    html = '<script>a()<script>b()<div>Content</div>'
    result = @renderer.close_unclosed_tags_inline(html, "script")

    open_count = result.scan(/<script[^>]*>/i).count
    close_count = result.scan(%r{</script>}i).count
    assert_equal open_count, close_count, "All script tags should be balanced"
    assert_includes result, "Content"
  end

  test "close_unclosed_tags_inline leaves balanced tags untouched" do
    html = '<script>var x = 1;</script><div>Content</div>'
    result = @renderer.close_unclosed_tags_inline(html, "script")
    assert_equal html, result
  end

  test "close_unclosed_tags_inline appends closing tag when no next HTML element" do
    html = "<script>var x = 1;"
    result = @renderer.close_unclosed_tags_inline(html, "script")
    assert_includes result, "</script>"
  end

  test "close_unclosed_tags_inline works for style tags too" do
    html = '<style>.hero { color: red;<div>Content</div>'
    result = @renderer.close_unclosed_tags_inline(html, "style")

    assert_includes result, "</style>"
    assert result.index("</style>") < result.index("<div>")
    assert_includes result, "Content"
  end

  # ═══════════════════════════════════════════════════════════════
  # ensure_html_structure — full structural repair
  # ═══════════════════════════════════════════════════════════════

  test "ensure_html_structure adds missing body and html closing tags" do
    html = '<!DOCTYPE html><html><body><div>Hello</div>'
    result = @renderer.ensure_html_structure(html)

    assert_includes result, "</body>"
    assert_includes result, "</html>"
  end

  test "ensure_html_structure does not duplicate existing closing tags" do
    html = '<!DOCTYPE html><html><body><div>Hello</div></body></html>'
    result = @renderer.ensure_html_structure(html)

    assert_equal 1, result.scan("</body>").count
    assert_equal 1, result.scan("</html>").count
  end

  test "ensure_html_structure closes unclosed form tags" do
    html = '<form><input name="email"><div>Content</div></body></html>'
    result = @renderer.ensure_html_structure(html)
    assert_includes result, "</form>"
  end

  test "ensure_html_structure handles truncated AI output with orphaned script" do
    # Simulates truncated AI output: script started but never closed, followed by valid HTML
    html = <<~HTML
      <!DOCTYPE html>
      <html><body>
      <section id="hero"><h1>Welcome</h1></section>
      <script>
      // This script was truncated by token limit
      function init() {
        var form = document.querySelector('form');
      <section id="features"><h2>Features</h2></section>
      <section id="cta"><h2>Get Started</h2></section>
    HTML

    result = @renderer.ensure_html_structure(html)

    # Script should be closed before features section
    assert_includes result, "</script>"
    # Features and CTA sections must survive
    assert_includes result, '<section id="features">'
    assert_includes result, '<section id="cta">'
    assert_includes result, "</body>"
    assert_includes result, "</html>"
  end

  # ═══════════════════════════════════════════════════════════════
  # strip_malformed_scripts — removes broken JS
  # ═══════════════════════════════════════════════════════════════

  test "strip_malformed_scripts removes scripts with unbalanced braces" do
    html = '<script>function foo() { if (true) { console.log("hi"); }</script>'
    result = @renderer.strip_malformed_scripts(html)
    assert_includes result, "Removed malformed script"
    refute_includes result, "console.log"
  end

  test "strip_malformed_scripts keeps valid scripts intact" do
    html = '<script>var x = 1; console.log("hi");</script>'
    result = @renderer.strip_malformed_scripts(html)
    assert_includes result, 'console.log("hi")'
  end

  test "strip_malformed_scripts removes scripts with unclosed functions" do
    html = '<script>function handleSubmit(form) { var data = new FormData(form);</script>'
    result = @renderer.strip_malformed_scripts(html)
    assert_includes result, "Removed malformed script"
  end

  test "strip_malformed_scripts handles multiple scripts independently" do
    html = <<~HTML
      <script>var x = 1;</script>
      <script>function broken() { if (true) {</script>
      <script>var y = 2;</script>
    HTML

    result = @renderer.strip_malformed_scripts(html)
    assert_includes result, "var x = 1;"
    assert_includes result, "var y = 2;"
    assert_includes result, "Removed malformed script"
  end

  # ═══════════════════════════════════════════════════════════════
  # sanitize_form_attributes — prevent native form submission
  # ═══════════════════════════════════════════════════════════════

  test "sanitize_form_attributes removes action and method" do
    html = '<form action="https://example.com/submit" method="POST"><input name="email"></form>'
    result = @renderer.sanitize_form_attributes(html)

    refute_includes result, 'action='
    refute_includes result, 'method='
    assert_includes result, '<form'
    assert_includes result, '<input name="email">'
  end

  test "sanitize_form_attributes removes onsubmit handlers" do
    html = '<form onsubmit="return false;"><input></form>'
    result = @renderer.sanitize_form_attributes(html)
    refute_includes result, 'onsubmit='
  end

  # ═══════════════════════════════════════════════════════════════
  # strip_editing_attributes — clean preview/public output
  # ═══════════════════════════════════════════════════════════════

  test "strip_editing_attributes removes contenteditable" do
    html = '<div contenteditable="true">Editable text</div>'
    result = @renderer.strip_editing_attributes(html)
    refute_includes result, 'contenteditable'
    assert_includes result, "Editable text"
  end

  test "strip_editing_attributes adds animated class to animate-on-scroll elements" do
    html = '<div class="animate-on-scroll fade-in">Content</div>'
    result = @renderer.strip_editing_attributes(html)
    assert_includes result, "animated"
  end

  # ═══════════════════════════════════════════════════════════════
  # Integration: full pipeline handles worst-case AI output
  # ═══════════════════════════════════════════════════════════════

  test "full pipeline handles AI output with raw JS leak, missing sections, truncation" do
    # This is the actual production bug scenario: AI generates HTML with an
    # unclosed script tag, raw JS leaks into page, and sections after it are lost
    bad_ai_output = <<~HTML
      <!DOCTYPE html>
      <html><head><title>Test</title></head>
      <body>
      <section id="hero"><h1>Welcome to CloudSync</h1></section>
      <script>
      document.addEventListener('DOMContentLoaded', function() {
        const form = document.querySelector('form');
        form.addEventListener('submit', function(e) {
          e.preventDefault();
      <section id="benefits">
        <h2>Benefits</h2>
        <p>Benefit 1</p>
        <p>Benefit 2</p>
      </section>
      <footer>
        <p>Footer content</p>
      </footer>
    HTML

    result = @renderer.ensure_html_structure(bad_ai_output)
    result = @renderer.strip_malformed_scripts(result)

    # The critical assertions: content after the broken script must survive
    assert_includes result, '<section id="benefits">'
    assert_includes result, "Benefit 1"
    assert_includes result, "Footer content"
    assert_includes result, "</body>"
    assert_includes result, "</html>"
  end
end
