# frozen_string_literal: true

require "test_helper"

class Amos::ResponseHtmlProcessorTest < ActiveSupport::TestCase
  test "returns original content when no HTML present" do
    content = "Here are your customers: John, Jane, and Bob."
    result = Amos::ResponseHtmlProcessor.process(content)

    assert_equal content, result[:content]
    assert_nil result[:canvas_suggestion]
  end

  test "returns original content for simple markdown" do
    content = "**Bold text** and *italic* with bullet points:\n- Item 1\n- Item 2"
    result = Amos::ResponseHtmlProcessor.process(content)

    assert_equal content, result[:content]
    assert_nil result[:canvas_suggestion]
  end

  test "extracts significant HTML table to canvas" do
    content = <<~CONTENT
      Here's your customer list:
      <div class="container">
        <h2>Customers</h2>
        <table class="table">
          <thead><tr><th>Name</th><th>Email</th></tr></thead>
          <tbody>
            <tr><td>John Doe</td><td>john@example.com</td></tr>
            <tr><td>Jane Smith</td><td>jane@example.com</td></tr>
            <tr><td>Bob Wilson</td><td>bob@example.com</td></tr>
          </tbody>
        </table>
      </div>
    CONTENT

    result = Amos::ResponseHtmlProcessor.process(content)

    assert result[:canvas_suggestion].present?, "Should extract HTML to canvas"
    assert_equal 'freeform_canvas', result[:canvas_suggestion][:canvas]
    assert result[:canvas_suggestion][:canvas_data][:html].include?('<table')
    assert result[:content].include?('canvas'), "Clean message should mention canvas"
    assert_not result[:content].include?('<table'), "Clean message should not contain HTML"
  end

  test "extracts HTML list to canvas" do
    content = <<~CONTENT
      Found these results:
      <ul class="list-group">
        <li class="list-group-item">Item one with lots of content here to make it significant</li>
        <li class="list-group-item">Item two with more detailed information included</li>
        <li class="list-group-item">Item three with additional context and details</li>
        <li class="list-group-item">Item four finishing up the list of items</li>
      </ul>
    CONTENT

    result = Amos::ResponseHtmlProcessor.process(content)

    assert result[:canvas_suggestion].present?
    assert result[:canvas_suggestion][:canvas_data][:html].include?('<ul')
  end

  test "extracts complex div structure to canvas" do
    content = <<~CONTENT
      I've created a visual timeline:
      <div class="container py-4">
        <div class="card mb-3">
          <div class="card-header bg-primary text-white">
            <h5>Timeline Header</h5>
          </div>
          <div class="card-body">
            <p>Content for the first section with enough text to be significant.</p>
            <p>More content here to ensure we meet the minimum length threshold.</p>
          </div>
        </div>
        <div class="card mb-3">
          <div class="card-header bg-secondary text-white">
            <h5>Second Section</h5>
          </div>
          <div class="card-body">
            <p>Additional content for the second section of the timeline.</p>
          </div>
        </div>
      </div>
    CONTENT

    result = Amos::ResponseHtmlProcessor.process(content)

    assert result[:canvas_suggestion].present?
    assert result[:canvas_suggestion][:canvas_data][:title].present?
  end

  test "ignores short HTML snippets" do
    content = "The result is <strong>42</strong> and the status is <em>complete</em>."
    result = Amos::ResponseHtmlProcessor.process(content)

    assert_nil result[:canvas_suggestion]
    assert_equal content, result[:content]
  end

  test "extracts title from heading" do
    content = <<~CONTENT
      <div class="container">
        <h2>Customer Analysis Report</h2>
        <table class="table">
          <tr><td>Data row 1</td></tr>
          <tr><td>Data row 2</td></tr>
          <tr><td>Data row 3</td></tr>
          <tr><td>Data row 4</td></tr>
          <tr><td>Data row 5</td></tr>
        </table>
      </div>
    CONTENT

    result = Amos::ResponseHtmlProcessor.process(content)

    assert result[:canvas_suggestion].present?
    assert_equal "Customer Analysis Report", result[:canvas_suggestion][:canvas_data][:title]
  end

  test "wraps HTML in container if not already wrapped" do
    content = <<~CONTENT
      <table class="table">
        <thead><tr><th>A</th><th>B</th></tr></thead>
        <tbody>
          <tr><td>1</td><td>2</td></tr>
          <tr><td>3</td><td>4</td></tr>
          <tr><td>5</td><td>6</td></tr>
        </tbody>
      </table>
    CONTENT

    result = Amos::ResponseHtmlProcessor.process(content)

    if result[:canvas_suggestion]
      html = result[:canvas_suggestion][:canvas_data][:html]
      assert html.include?('container'), "Should wrap in container"
    end
  end

  test "handles nil content gracefully" do
    result = Amos::ResponseHtmlProcessor.process(nil)
    assert_equal({ content: nil, canvas_suggestion: nil }, result)
  end

  test "handles empty content gracefully" do
    result = Amos::ResponseHtmlProcessor.process("")
    assert_equal({ content: "", canvas_suggestion: nil }, result)
  end
end
