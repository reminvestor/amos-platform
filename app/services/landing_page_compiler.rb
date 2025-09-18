require 'erb'
require 'cgi'
require 'active_support/core_ext/object/blank'

class LandingPageCompiler
  # Component templates for safe HTML generation
  COMPONENTS = {
    'hero' => {
      template: <<~HTML,
        <section class="hero-section <%= theme_class('hero') %>" <% if section['background'] %>style="<%= background_style(section['background']) %>"<% end %>>
          <div class="container">
            <div class="row align-items-center">
              <div class="col-lg-<%= section['image'] ? '6' : '12' %> text-<%= section['image'] ? 'start' : 'center' %>">
                <h1 class="hero-headline display-4 fw-bold mb-3">
                  <%= sanitize_html(section['headline']) %>
                </h1>
                <% if section['subheadline'] %>
                  <p class="hero-subheadline lead mb-4">
                    <%= sanitize_html(section['subheadline']) %>
                  </p>
                <% end %>
                <% if section['cta'] %>
                  <%= render_button(section['cta']) %>
                <% end %>
              </div>
              <% if section['image'] %>
                <div class="col-lg-6">
                  <%= render_image(section['image'], 'hero-image img-fluid rounded') %>
                </div>
              <% end %>
            </div>
          </div>
        </section>
      HTML
      required: ['headline'],
      optional: ['subheadline', 'cta', 'image', 'background']
    },
    
    'features' => {
      template: <<~HTML,
        <section class="features-section <%= theme_class('features') %> py-5">
          <div class="container">
            <div class="row">
              <div class="col-12 text-center mb-5">
                <h2 class="section-title h1 mb-3">
                  <%= sanitize_html(section['title']) %>
                </h2>
                <% if section['subtitle'] %>
                  <p class="section-subtitle lead text-muted">
                    <%= sanitize_html(section['subtitle']) %>
                  </p>
                <% end %>
              </div>
            </div>
            <div class="row g-4">
              <% section['items'].each do |item| %>
                <div class="col-md-6 col-lg-<%= 12 / [section['items'].size, 3].min %>">
                  <div class="feature-card h-100 p-4 <%= theme_class('card') %>">
                    <% if item['icon'] %>
                      <div class="feature-icon mb-3">
                        <i class="bi bi-<%= sanitize_attribute(item['icon']) %> fs-1 text-primary"></i>
                      </div>
                    <% end %>
                    <h3 class="feature-title h4 mb-3">
                      <%= sanitize_html(item['title']) %>
                    </h3>
                    <p class="feature-description text-muted">
                      <%= sanitize_html(item['description']) %>
                    </p>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </section>
      HTML
      required: ['title', 'items'],
      optional: ['subtitle']
    },
    
    'cta' => {
      template: <<~HTML,
        <section class="cta-section <%= theme_class('cta') %> py-5" <% if section['background'] %>style="<%= background_style(section['background']) %>"<% end %>>
          <div class="container">
            <div class="row">
              <div class="col-12 text-center">
                <h2 class="cta-headline h1 mb-3">
                  <%= sanitize_html(section['headline']) %>
                </h2>
                <% if section['description'] %>
                  <p class="cta-description lead mb-4">
                    <%= sanitize_html(section['description']) %>
                  </p>
                <% end %>
                <%= render_button(section['button'], 'btn-lg') %>
              </div>
            </div>
          </div>
        </section>
      HTML
      required: ['headline', 'button'],
      optional: ['description', 'background']
    },
    
    'testimonials' => {
      template: <<~HTML,
        <section class="testimonials-section <%= theme_class('testimonials') %> py-5">
          <div class="container">
            <div class="row">
              <div class="col-12 text-center mb-5">
                <h2 class="section-title h1 mb-3">
                  <%= sanitize_html(section['title']) %>
                </h2>
              </div>
            </div>
            <div class="row g-4">
              <% section['items'].each do |testimonial| %>
                <div class="col-md-6 col-lg-<%= 12 / [section['items'].size, 3].min %>">
                  <div class="testimonial-card h-100 p-4 <%= theme_class('card') %>">
                    <blockquote class="blockquote mb-3">
                      <p>"<%= sanitize_html(testimonial['quote']) %>"</p>
                    </blockquote>
                    <div class="testimonial-author d-flex align-items-center">
                      <% if testimonial['avatar'] %>
                        <%= render_image(testimonial['avatar'], 'avatar rounded-circle me-3', 48, 48) %>
                      <% end %>
                      <div>
                        <div class="author-name fw-bold">
                          <%= sanitize_html(testimonial['author']) %>
                        </div>
                        <% if testimonial['title'] %>
                          <div class="author-title text-muted small">
                            <%= sanitize_html(testimonial['title']) %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </section>
      HTML
      required: ['title', 'items'],
      optional: []
    },
    
    'contact' => {
      template: <<~HTML,
        <section class="contact-section <%= theme_class('contact') %> py-5">
          <div class="container">
            <div class="row">
              <div class="col-12 text-center mb-5">
                <h2 class="section-title h1 mb-3">
                  <%= sanitize_html(section['title']) %>
                </h2>
                <% if section['description'] %>
                  <p class="section-description lead text-muted">
                    <%= sanitize_html(section['description']) %>
                  </p>
                <% end %>
              </div>
            </div>
            <div class="row justify-content-center">
              <div class="col-lg-8">
                <%= render_form(section, 'contact') %>
              </div>
            </div>
          </div>
        </section>
      HTML
      required: ['title'],
      optional: ['description', 'fields']
    },
    
    'about' => {
      template: <<~HTML,
        <section class="about-section <%= theme_class('about') %> py-5">
          <div class="container">
            <div class="row align-items-center">
              <div class="col-lg-<%= section['image'] ? '6' : '12' %>">
                <h2 class="section-title h1 mb-3">
                  <%= sanitize_html(section['title']) %>
                </h2>
                <div class="about-content">
                  <%= sanitize_and_format_content(section['content']) %>
                </div>
              </div>
              <% if section['image'] %>
                <div class="col-lg-6">
                  <%= render_image(section['image'], 'about-image img-fluid rounded') %>
                </div>
              <% end %>
            </div>
          </div>
        </section>
      HTML
      required: ['title', 'content'],
      optional: ['image']
    }
  }.freeze
  
  def initialize(dsl_content, options = {})
    @dsl_content = dsl_content.is_a?(String) ? JSON.parse(dsl_content) : dsl_content
    @options = options
    @theme = @dsl_content.dig('page', 'theme') || 'clean'
    @theme_config = ::LandingPageDSL.theme_config(@theme)
    @landing_page_slug = options[:landing_page_slug]
  end
  
  def compile
    # Validate DSL first
    validation = ::LandingPageDSL.validate(@dsl_content)
    unless validation[:valid]
      raise "Invalid DSL: #{validation[:errors].join(', ')}"
    end
    
    # Generate HTML
    html = generate_html
    
    # Return complete HTML document
    wrap_in_document(html)
  end
  
  private
  
  def generate_html
    page_data = @dsl_content['page']
    sections_html = page_data['sections'].map { |section| compile_section(section) }.join("\n")
    
    # Add any custom CSS for the theme
    sections_html
  end
  
  def compile_section(section)
    @current_section = section
    section_type = section['type']
    component = COMPONENTS[section_type]
    
    unless component
      raise "Unknown section type: #{section_type}"
    end
    
    # Validate required fields
    component[:required].each do |field|
      unless section[field].present?
        raise "Missing required field '#{field}' in #{section_type} section"
      end
    end
    
    # Render the template
    template = ERB.new(component[:template])
    template.result(binding)
  end
  
  def wrap_in_document(body_html)
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{sanitize_html(@dsl_content.dig('page', 'title') || 'Landing Page')}</title>
        <meta name="description" content="#{sanitize_attribute(@dsl_content.dig('page', 'description') || '')}">
        
        <!-- Bootstrap CSS -->
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css" rel="stylesheet">
        
        <!-- Custom Theme Styles -->
        <style>
          #{generate_theme_css}
        </style>
      </head>
      <body class="theme-#{@theme}">
        #{body_html}
        
        <!-- Bootstrap JS -->
        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
        
        <!-- Form Handling Script -->
        <script>
          #{generate_form_script}
        </script>
      </body>
      </html>
    HTML
  end
  
  def generate_theme_css
    <<~CSS
      :root {
        --primary-color: #{@theme_config[:primary_color]};
        --secondary-color: #{@theme_config[:secondary_color]};
        --font-family: #{@theme_config[:font_family]};
        --border-radius: #{@theme_config[:border_radius]};
      }
      
      body {
        font-family: var(--font-family);
      }
      
      .btn-primary {
        background-color: var(--primary-color);
        border-color: var(--primary-color);
        border-radius: var(--border-radius);
      }
      
      .btn-primary:hover {
        background-color: color-mix(in srgb, var(--primary-color) 85%, black);
        border-color: color-mix(in srgb, var(--primary-color) 85%, black);
      }
      
      .theme-card {
        border: 1px solid #e9ecef;
        border-radius: var(--border-radius);
        transition: all 0.3s ease;
      }
      
      .theme-card:hover {
        box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        transform: translateY(-2px);
      }
      
      .hero-section {
        min-height: 60vh;
        display: flex;
        align-items: center;
      }
      
      .section-spacing {
        padding: 4rem 0;
      }
    CSS
  end
  
  def generate_form_script
    submission_url = @landing_page_slug ? 
      "/api/v1/landing_pages/#{@landing_page_slug}/submit" : 
      "/api/v1/landing_page_submissions"
    
    <<~JAVASCRIPT
      document.addEventListener('DOMContentLoaded', function() {
        const forms = document.querySelectorAll('.landing-page-form');
        
        forms.forEach(function(form) {
          form.addEventListener('submit', function(e) {
            e.preventDefault();
            
            const formData = new FormData(form);
            const submitButton = form.querySelector('button[type="submit"]');
            const originalText = submitButton.textContent;
            
            // Show loading state
            submitButton.disabled = true;
            submitButton.textContent = 'Sending...';
            
            fetch('#{submission_url}', {
              method: 'POST',
              body: formData,
              headers: {
                'X-Requested-With': 'XMLHttpRequest'
              }
            })
            .then(response => response.json())
            .then(data => {
              if (data.success) {
                // Show success message
                form.innerHTML = '<div class="alert alert-success"><h4>Thank you!</h4><p>' + data.message + '</p></div>';
              } else {
                // Show error message
                showFormError(form, data.message || 'There was an error submitting your form.');
                submitButton.disabled = false;
                submitButton.textContent = originalText;
              }
            })
            .catch(error => {
              showFormError(form, 'There was an error submitting your form. Please try again.');
              submitButton.disabled = false;
              submitButton.textContent = originalText;
            });
          });
        });
        
        function showFormError(form, message) {
          let errorDiv = form.querySelector('.form-error');
          if (!errorDiv) {
            errorDiv = document.createElement('div');
            errorDiv.className = 'alert alert-danger form-error';
            form.insertBefore(errorDiv, form.firstChild);
          }
          errorDiv.textContent = message;
        }
      });
    JAVASCRIPT
  end
  
  # Helper methods available in ERB templates
  def sanitize_html(content)
    return '' unless content
    CGI.escapeHTML(content.to_s)
  end
  
  def sanitize_attribute(content)
    return '' unless content
    content.to_s.gsub(/[<>"']/, '')
  end
  
  def theme_class(element)
    case element
    when 'hero'
      'bg-light'
    when 'features'
      'bg-white'
    when 'cta'
      'bg-primary text-white'
    when 'testimonials'
      'bg-light'
    when 'contact'
      'bg-white'
    when 'about'
      'bg-light'
    when 'card'
      'theme-card'
    else
      ''
    end
  end
  
  def background_style(background)
    return '' unless background
    
    case background['type']
    when 'color'
      "background-color: #{sanitize_attribute(background['value'])};"
    when 'gradient'
      "background: #{sanitize_attribute(background['value'])};"
    when 'image'
      "background-image: url('#{sanitize_attribute(background['value'])}'); background-size: cover; background-position: center;"
    else
      ''
    end
  end
  
  def render_button(button_data, extra_classes = '')
    return '' unless button_data
    
    style = button_data['style'] || 'primary'
    text = sanitize_html(button_data['text'])
    action = button_data['action']
    target = sanitize_attribute(button_data['target'] || '#')
    
    case action
    when 'submit_form'
      "<button type='submit' class='btn btn-#{style} #{extra_classes}'>#{text}</button>"
    when 'external_link'
      "<a href='#{target}' class='btn btn-#{style} #{extra_classes}' target='_blank'>#{text}</a>"
    when 'scroll_to'
      "<a href='#{target}' class='btn btn-#{style} #{extra_classes}' onclick='document.querySelector(\"#{target}\").scrollIntoView({behavior: \"smooth\"})'>#{text}</a>"
    when 'download'
      "<a href='#{target}' class='btn btn-#{style} #{extra_classes}' download>#{text}</a>"
    else
      "<a href='#{target}' class='btn btn-#{style} #{extra_classes}'>#{text}</a>"
    end
  end
  
  def render_image(image_data, css_class = '', width = nil, height = nil)
    return '' unless image_data
    
    src = sanitize_attribute(image_data['src'])
    alt = sanitize_html(image_data['alt'])
    width_attr = width ? "width='#{width}'" : (image_data['width'] ? "width='#{image_data['width']}'" : '')
    height_attr = height ? "height='#{height}'" : (image_data['height'] ? "height='#{image_data['height']}'" : '')
    
    "<img src='#{src}' alt='#{alt}' class='#{css_class}' #{width_attr} #{height_attr} loading='lazy'>"
  end
  
  def render_form(section, form_type)
    fields = section['fields'] || %w[name email message]
    
    form_html = "<form class='landing-page-form' method='POST'>\n"
    form_html += "<input type='hidden' name='form_type' value='#{form_type}'>\n"
    
    fields.each do |field|
      form_html += render_form_field(field)
    end
    
    form_html += "<button type='submit' class='btn btn-primary btn-lg w-100 mt-3'>Send Message</button>\n"
    form_html += "</form>"
    
    form_html
  end
  
  def render_form_field(field)
    case field
    when 'name'
      <<~HTML
        <div class="row mb-3">
          <div class="col-md-6">
            <label for="first_name" class="form-label">First Name *</label>
            <input type="text" class="form-control" id="first_name" name="first_name" required>
          </div>
          <div class="col-md-6">
            <label for="last_name" class="form-label">Last Name *</label>
            <input type="text" class="form-control" id="last_name" name="last_name" required>
          </div>
        </div>
      HTML
    when 'email'
      <<~HTML
        <div class="mb-3">
          <label for="email" class="form-label">Email Address *</label>
          <input type="email" class="form-control" id="email" name="email" required>
        </div>
      HTML
    when 'phone'
      <<~HTML
        <div class="mb-3">
          <label for="phone" class="form-label">Phone Number</label>
          <input type="tel" class="form-control" id="phone" name="phone">
        </div>
      HTML
    when 'company'
      <<~HTML
        <div class="mb-3">
          <label for="company" class="form-label">Company</label>
          <input type="text" class="form-control" id="company" name="company">
        </div>
      HTML
    when 'message'
      <<~HTML
        <div class="mb-3">
          <label for="message" class="form-label">Message *</label>
          <textarea class="form-control" id="message" name="message" rows="4" required></textarea>
        </div>
      HTML
    else
      ''
    end
  end
  
  def sanitize_and_format_content(content)
    return '' unless content
    
    # Convert line breaks to paragraphs
    paragraphs = content.split(/\n\s*\n/).reject(&:blank?)
    paragraphs.map { |p| "<p>#{sanitize_html(p.strip)}</p>" }.join("\n")
  end
  
  # Expose section variable to ERB templates
  def section
    @current_section
  end
end
