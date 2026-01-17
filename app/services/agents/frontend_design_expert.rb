# frozen_string_literal: true

module Agents
  # FrontendDesignExpert - Specialized agent for creating beautiful, Bootstrap-based UIs
  #
  # This agent has deep knowledge of:
  # - Bootstrap 5 component library
  # - Responsive design patterns
  # - Modern UI/UX best practices
  # - Color theory and typography
  # - Animation and micro-interactions
  #
  class FrontendDesignExpert
    # ============================================
    # BOOTSTRAP 5 COMPONENT LIBRARY
    # ============================================

    COMPONENT_LIBRARY = {
      # Hero Sections
      hero: {
        variants: {
          gradient: {
            name: 'Gradient Hero',
            description: 'Bold gradient background with centered content',
            classes: 'bg-gradient text-white py-5',
            best_for: 'SaaS, modern startups'
          },
          image_bg: {
            name: 'Image Background Hero',
            description: 'Full-width background image with overlay',
            classes: 'position-relative text-white',
            best_for: 'Portfolio, creative agencies'
          },
          split: {
            name: 'Split Hero',
            description: 'Content on left, image on right',
            classes: 'd-flex align-items-center',
            best_for: 'Product launches, apps'
          },
          minimal: {
            name: 'Minimal Hero',
            description: 'Clean, typography-focused',
            classes: 'py-5 text-center',
            best_for: 'Professional services, B2B'
          },
          video_bg: {
            name: 'Video Background',
            description: 'Looping video with overlay',
            classes: 'position-relative overflow-hidden',
            best_for: 'Event pages, entertainment'
          }
        }
      },

      # Feature Sections
      features: {
        variants: {
          icon_cards: {
            name: 'Icon Cards',
            description: 'Grid of cards with icons and descriptions',
            classes: 'row g-4',
            best_for: 'Feature lists, services'
          },
          alternating: {
            name: 'Alternating Rows',
            description: 'Image-text alternating left and right',
            classes: 'row align-items-center',
            best_for: 'Product features, how it works'
          },
          timeline: {
            name: 'Timeline',
            description: 'Vertical timeline with connected points',
            classes: 'position-relative',
            best_for: 'Process, history, roadmap'
          },
          tabs: {
            name: 'Tabbed Features',
            description: 'Features organized in tabs',
            classes: 'nav nav-tabs',
            best_for: 'Complex products, documentation'
          }
        }
      },

      # Testimonials
      testimonials: {
        variants: {
          carousel: {
            name: 'Carousel',
            description: 'Sliding testimonial cards',
            classes: 'carousel slide',
            best_for: 'Multiple testimonials, social proof'
          },
          quote_cards: {
            name: 'Quote Cards',
            description: 'Grid of quote cards with avatars',
            classes: 'row g-4',
            best_for: 'B2B, professional services'
          },
          video: {
            name: 'Video Testimonials',
            description: 'Video thumbnails with play buttons',
            classes: 'row g-4',
            best_for: 'High-trust products, SaaS'
          },
          logo_bar: {
            name: 'Logo Bar',
            description: 'Row of client logos',
            classes: 'd-flex justify-content-center gap-4',
            best_for: 'Enterprise, B2B trust'
          }
        }
      },

      # Pricing
      pricing: {
        variants: {
          cards: {
            name: 'Pricing Cards',
            description: 'Side-by-side pricing tiers',
            classes: 'row g-4 justify-content-center',
            best_for: 'SaaS, subscription products'
          },
          comparison: {
            name: 'Comparison Table',
            description: 'Feature comparison grid',
            classes: 'table table-hover',
            best_for: 'Complex products, enterprise'
          },
          toggle: {
            name: 'Monthly/Annual Toggle',
            description: 'Pricing with billing toggle',
            classes: 'btn-group',
            best_for: 'SaaS with discounts'
          }
        }
      },

      # Forms
      forms: {
        variants: {
          inline: {
            name: 'Inline Form',
            description: 'Horizontal form in one row',
            classes: 'row g-3 align-items-center',
            best_for: 'Newsletter signup, quick actions'
          },
          stacked: {
            name: 'Stacked Form',
            description: 'Vertical form with labels',
            classes: 'needs-validation',
            best_for: 'Contact forms, registration'
          },
          wizard: {
            name: 'Multi-Step Wizard',
            description: 'Form broken into steps',
            classes: 'card',
            best_for: 'Complex forms, onboarding'
          },
          floating: {
            name: 'Floating Labels',
            description: 'Modern floating label inputs',
            classes: 'form-floating',
            best_for: 'Modern apps, clean design'
          }
        }
      },

      # Navigation
      navigation: {
        variants: {
          sticky: {
            name: 'Sticky Navbar',
            description: 'Fixed to top on scroll',
            classes: 'navbar navbar-expand-lg sticky-top',
            best_for: 'Long pages, SaaS'
          },
          transparent: {
            name: 'Transparent Navbar',
            description: 'Transparent over hero, solid on scroll',
            classes: 'navbar navbar-expand-lg fixed-top',
            best_for: 'Landing pages with hero images'
          },
          sidebar: {
            name: 'Sidebar Navigation',
            description: 'Vertical sidebar navigation',
            classes: 'nav flex-column',
            best_for: 'Dashboards, documentation'
          },
          mega_menu: {
            name: 'Mega Menu',
            description: 'Dropdown with multiple columns',
            classes: 'dropdown-menu dropdown-menu-lg',
            best_for: 'E-commerce, large sites'
          }
        }
      },

      # Footer
      footer: {
        variants: {
          simple: {
            name: 'Simple Footer',
            description: 'Logo, links, copyright',
            classes: 'bg-dark text-white py-4',
            best_for: 'Simple sites, landing pages'
          },
          multi_column: {
            name: 'Multi-Column Footer',
            description: 'Multiple link columns',
            classes: 'bg-dark text-white py-5',
            best_for: 'Complex sites, SaaS'
          },
          centered: {
            name: 'Centered Footer',
            description: 'Centered layout with social icons',
            classes: 'text-center py-4',
            best_for: 'Minimal sites, portfolios'
          },
          newsletter: {
            name: 'Newsletter Footer',
            description: 'Footer with newsletter signup',
            classes: 'bg-dark text-white py-5',
            best_for: 'Content sites, blogs'
          }
        }
      },

      # Call to Action
      cta: {
        variants: {
          banner: {
            name: 'Full-Width Banner',
            description: 'Bold colored banner with CTA',
            classes: 'bg-primary text-white py-5 text-center',
            best_for: 'Driving conversions'
          },
          card: {
            name: 'CTA Card',
            description: 'Contained CTA in a card',
            classes: 'card shadow-lg',
            best_for: 'Inline promotions'
          },
          floating: {
            name: 'Floating CTA',
            description: 'Fixed position button',
            classes: 'position-fixed bottom-0 end-0 m-4',
            best_for: 'Persistent actions'
          }
        }
      }
    }.freeze

    # ============================================
    # DESIGN SYSTEMS / THEMES
    # ============================================

    DESIGN_SYSTEMS = {
      modern: {
        name: 'Modern',
        font_family: "'Inter', -apple-system, BlinkMacSystemFont, sans-serif",
        heading_font: "'Inter', sans-serif",
        heading_weight: 700,
        base_size: '16px',
        border_radius: '0.5rem',
        shadow: '0 4px 6px -1px rgba(0, 0, 0, 0.1)',
        colors: {
          primary: '#3b82f6',      # Blue
          secondary: '#64748b',    # Slate
          success: '#22c55e',      # Green
          danger: '#ef4444',       # Red
          warning: '#f59e0b',      # Amber
          info: '#06b6d4',         # Cyan
          light: '#f8fafc',
          dark: '#0f172a'
        },
        best_for: 'SaaS, tech products, startups'
      },

      minimal: {
        name: 'Minimal',
        font_family: "'DM Sans', sans-serif",
        heading_font: "'DM Sans', sans-serif",
        heading_weight: 600,
        base_size: '16px',
        border_radius: '0',
        shadow: 'none',
        colors: {
          primary: '#000000',
          secondary: '#6b7280',
          success: '#10b981',
          danger: '#dc2626',
          warning: '#d97706',
          info: '#0ea5e9',
          light: '#ffffff',
          dark: '#111827'
        },
        best_for: 'Portfolios, agencies, luxury brands'
      },

      corporate: {
        name: 'Corporate',
        font_family: "'Source Sans Pro', sans-serif",
        heading_font: "'Source Serif Pro', serif",
        heading_weight: 600,
        base_size: '16px',
        border_radius: '0.25rem',
        shadow: '0 1px 3px rgba(0, 0, 0, 0.12)',
        colors: {
          primary: '#1e40af',      # Navy blue
          secondary: '#475569',
          success: '#059669',
          danger: '#b91c1c',
          warning: '#b45309',
          info: '#0369a1',
          light: '#f1f5f9',
          dark: '#1e293b'
        },
        best_for: 'B2B, enterprise, professional services'
      },

      playful: {
        name: 'Playful',
        font_family: "'Nunito', sans-serif",
        heading_font: "'Nunito', sans-serif",
        heading_weight: 800,
        base_size: '17px',
        border_radius: '1rem',
        shadow: '0 10px 25px -5px rgba(0, 0, 0, 0.1)',
        colors: {
          primary: '#8b5cf6',      # Purple
          secondary: '#ec4899',    # Pink
          success: '#34d399',
          danger: '#f87171',
          warning: '#fbbf24',
          info: '#38bdf8',
          light: '#faf5ff',
          dark: '#1f2937'
        },
        best_for: 'Consumer apps, education, entertainment'
      },

      elegant: {
        name: 'Elegant',
        font_family: "'Cormorant Garamond', serif",
        heading_font: "'Playfair Display', serif",
        heading_weight: 500,
        base_size: '18px',
        border_radius: '0.125rem',
        shadow: '0 2px 4px rgba(0, 0, 0, 0.05)',
        colors: {
          primary: '#78350f',      # Brown/gold
          secondary: '#a16207',
          success: '#15803d',
          danger: '#9f1239',
          warning: '#a16207',
          info: '#0e7490',
          light: '#fffbeb',
          dark: '#292524'
        },
        best_for: 'Luxury, hospitality, fashion'
      },

      dark_mode: {
        name: 'Dark Mode',
        font_family: "'Space Grotesk', sans-serif",
        heading_font: "'Space Grotesk', sans-serif",
        heading_weight: 700,
        base_size: '16px',
        border_radius: '0.5rem',
        shadow: '0 4px 6px -1px rgba(0, 0, 0, 0.3)',
        colors: {
          primary: '#60a5fa',
          secondary: '#94a3b8',
          success: '#4ade80',
          danger: '#f87171',
          warning: '#fbbf24',
          info: '#22d3ee',
          light: '#1e293b',
          dark: '#0f172a',
          background: '#0f172a',
          surface: '#1e293b',
          text: '#f1f5f9'
        },
        best_for: 'Developer tools, night-use apps, creative'
      }
    }.freeze

    # ============================================
    # COMPONENT TEMPLATES
    # ============================================

    def self.get_component_template(type, variant)
      component = COMPONENT_LIBRARY[type.to_sym]
      return nil unless component

      variant_config = component[:variants][variant.to_sym]
      return nil unless variant_config

      # Load template from file or generate
      template_path = Rails.root.join(
        'app', 'views', 'components', 'bootstrap',
        type.to_s, "_#{variant}.html.erb"
      )

      if File.exist?(template_path)
        File.read(template_path)
      else
        generate_component_template(type, variant, variant_config)
      end
    end

    def self.generate_component_template(type, variant, config)
      # Generate a basic template based on the component type
      case type.to_sym
      when :hero
        generate_hero_template(variant, config)
      when :features
        generate_features_template(variant, config)
      when :testimonials
        generate_testimonials_template(variant, config)
      when :pricing
        generate_pricing_template(variant, config)
      when :forms
        generate_form_template(variant, config)
      when :cta
        generate_cta_template(variant, config)
      else
        %(<div class="#{config[:classes]}">#{config[:name]} Component</div>)
      end
    end

    # ============================================
    # DESIGN RECOMMENDATIONS
    # ============================================

    def self.recommend_design_system(business_type:, industry: nil, style_preference: nil)
      # Map business types to design systems
      recommendations = case business_type.to_s.downcase
      when 'saas', 'tech', 'startup', 'software'
        [:modern, :dark_mode]
      when 'agency', 'creative', 'portfolio', 'design'
        [:minimal, :elegant]
      when 'enterprise', 'b2b', 'consulting', 'professional'
        [:corporate, :modern]
      when 'ecommerce', 'retail', 'consumer'
        [:playful, :modern]
      when 'luxury', 'fashion', 'hospitality'
        [:elegant, :minimal]
      when 'education', 'kids', 'entertainment'
        [:playful]
      else
        [:modern, :minimal]
      end

      # Get full design system details
      recommendations.map { |key| DESIGN_SYSTEMS[key].merge(key: key) }
    end

    def self.generate_css_variables(design_system_key)
      system = DESIGN_SYSTEMS[design_system_key.to_sym]
      return '' unless system

      colors = system[:colors]
      
      <<~CSS
        :root {
          /* Colors */
          --bs-primary: #{colors[:primary]};
          --bs-secondary: #{colors[:secondary]};
          --bs-success: #{colors[:success]};
          --bs-danger: #{colors[:danger]};
          --bs-warning: #{colors[:warning]};
          --bs-info: #{colors[:info]};
          --bs-light: #{colors[:light]};
          --bs-dark: #{colors[:dark]};
          #{colors[:background] ? "--bs-body-bg: #{colors[:background]};" : ''}
          #{colors[:surface] ? "--bs-surface: #{colors[:surface]};" : ''}
          #{colors[:text] ? "--bs-body-color: #{colors[:text]};" : ''}
          
          /* Typography */
          --bs-font-sans-serif: #{system[:font_family]};
          --heading-font: #{system[:heading_font]};
          --heading-weight: #{system[:heading_weight]};
          --bs-body-font-size: #{system[:base_size]};
          
          /* Borders & Shadows */
          --bs-border-radius: #{system[:border_radius]};
          --bs-box-shadow: #{system[:shadow]};
        }

        h1, h2, h3, h4, h5, h6 {
          font-family: var(--heading-font);
          font-weight: var(--heading-weight);
        }

        .btn-primary {
          --bs-btn-bg: var(--bs-primary);
          --bs-btn-border-color: var(--bs-primary);
        }

        .card {
          border-radius: var(--bs-border-radius);
          box-shadow: var(--bs-box-shadow);
        }
      CSS
    end

    # ============================================
    # COMPONENT GENERATORS
    # ============================================

    private_class_method def self.generate_hero_template(variant, config)
      case variant.to_sym
      when :gradient
        <<~HTML
          <section class="hero-gradient py-5" style="background: linear-gradient(135deg, var(--bs-primary) 0%, var(--bs-secondary) 100%);">
            <div class="container">
              <div class="row justify-content-center text-center text-white py-5">
                <div class="col-lg-8">
                  <h1 class="display-4 fw-bold mb-4">{{headline}}</h1>
                  <p class="lead mb-4">{{subheadline}}</p>
                  <div class="d-flex gap-3 justify-content-center">
                    <a href="{{cta_url}}" class="btn btn-light btn-lg">{{cta_text}}</a>
                    <a href="{{secondary_url}}" class="btn btn-outline-light btn-lg">{{secondary_text}}</a>
                  </div>
                </div>
              </div>
            </div>
          </section>
        HTML
      when :split
        <<~HTML
          <section class="hero-split py-5">
            <div class="container">
              <div class="row align-items-center g-5">
                <div class="col-lg-6">
                  <h1 class="display-5 fw-bold mb-4">{{headline}}</h1>
                  <p class="lead text-muted mb-4">{{subheadline}}</p>
                  <div class="d-flex gap-3">
                    <a href="{{cta_url}}" class="btn btn-primary btn-lg">{{cta_text}}</a>
                    <a href="{{secondary_url}}" class="btn btn-outline-secondary btn-lg">{{secondary_text}}</a>
                  </div>
                </div>
                <div class="col-lg-6">
                  <img src="{{hero_image}}" alt="Hero" class="img-fluid rounded-3 shadow-lg">
                </div>
              </div>
            </div>
          </section>
        HTML
      else
        <<~HTML
          <section class="hero py-5 text-center">
            <div class="container">
              <h1 class="display-4 fw-bold">{{headline}}</h1>
              <p class="lead">{{subheadline}}</p>
              <a href="{{cta_url}}" class="btn btn-primary btn-lg">{{cta_text}}</a>
            </div>
          </section>
        HTML
      end
    end

    private_class_method def self.generate_features_template(variant, config)
      case variant.to_sym
      when :icon_cards
        <<~HTML
          <section class="features py-5">
            <div class="container">
              <div class="text-center mb-5">
                <h2 class="fw-bold">{{section_title}}</h2>
                <p class="text-muted">{{section_subtitle}}</p>
              </div>
              <div class="row g-4">
                {{#features}}
                <div class="col-md-4">
                  <div class="card h-100 border-0 shadow-sm">
                    <div class="card-body text-center p-4">
                      <div class="feature-icon bg-primary bg-gradient text-white rounded-circle d-inline-flex align-items-center justify-content-center mb-3" style="width: 64px; height: 64px;">
                        <i data-lucide="{{icon}}" style="width: 28px; height: 28px;"></i>
                      </div>
                      <h5 class="card-title">{{title}}</h5>
                      <p class="card-text text-muted">{{description}}</p>
                    </div>
                  </div>
                </div>
                {{/features}}
              </div>
            </div>
          </section>
        HTML
      when :alternating
        <<~HTML
          <section class="features-alternating py-5">
            <div class="container">
              {{#features}}
              <div class="row align-items-center g-5 mb-5 {{#odd}}flex-row-reverse{{/odd}}">
                <div class="col-lg-6">
                  <img src="{{image}}" alt="{{title}}" class="img-fluid rounded-3 shadow">
                </div>
                <div class="col-lg-6">
                  <h3 class="fw-bold mb-3">{{title}}</h3>
                  <p class="text-muted mb-4">{{description}}</p>
                  <a href="{{link}}" class="btn btn-outline-primary">Learn more →</a>
                </div>
              </div>
              {{/features}}
            </div>
          </section>
        HTML
      else
        <<~HTML
          <section class="features py-5">
            <div class="container">
              <h2 class="text-center fw-bold mb-5">{{section_title}}</h2>
              <div class="row g-4">
                {{#features}}
                <div class="col-md-4">
                  <h5>{{title}}</h5>
                  <p class="text-muted">{{description}}</p>
                </div>
                {{/features}}
              </div>
            </div>
          </section>
        HTML
      end
    end

    private_class_method def self.generate_testimonials_template(variant, config)
      <<~HTML
        <section class="testimonials py-5 bg-light">
          <div class="container">
            <h2 class="text-center fw-bold mb-5">{{section_title}}</h2>
            <div class="row g-4">
              {{#testimonials}}
              <div class="col-md-4">
                <div class="card h-100 border-0 shadow-sm">
                  <div class="card-body p-4">
                    <div class="d-flex align-items-center mb-3">
                      <div class="avatar bg-primary text-white rounded-circle d-flex align-items-center justify-content-center me-3" style="width: 48px; height: 48px;">
                        {{initials}}
                      </div>
                      <div>
                        <h6 class="mb-0">{{name}}</h6>
                        <small class="text-muted">{{role}}</small>
                      </div>
                    </div>
                    <p class="card-text">{{quote}}</p>
                  </div>
                </div>
              </div>
              {{/testimonials}}
            </div>
          </div>
        </section>
      HTML
    end

    private_class_method def self.generate_pricing_template(variant, config)
      <<~HTML
        <section class="pricing py-5">
          <div class="container">
            <div class="text-center mb-5">
              <h2 class="fw-bold">{{section_title}}</h2>
              <p class="text-muted">{{section_subtitle}}</p>
            </div>
            <div class="row g-4 justify-content-center">
              {{#plans}}
              <div class="col-lg-4">
                <div class="card h-100 {{#featured}}border-primary shadow-lg{{/featured}}">
                  {{#featured}}<div class="card-header bg-primary text-white text-center py-2">Most Popular</div>{{/featured}}
                  <div class="card-body p-4">
                    <h5 class="card-title">{{name}}</h5>
                    <div class="display-5 fw-bold mb-3">{{price}}<small class="fs-6 fw-normal text-muted">/{{interval}}</small></div>
                    <p class="text-muted mb-4">{{description}}</p>
                    <ul class="list-unstyled mb-4">
                      {{#features}}
                      <li class="mb-2"><i data-lucide="check" class="text-success me-2" style="width: 16px;"></i>{{.}}</li>
                      {{/features}}
                    </ul>
                    <a href="{{cta_url}}" class="btn {{#featured}}btn-primary{{/featured}}{{^featured}}btn-outline-primary{{/featured}} w-100">{{cta_text}}</a>
                  </div>
                </div>
              </div>
              {{/plans}}
            </div>
          </div>
        </section>
      HTML
    end

    private_class_method def self.generate_form_template(variant, config)
      case variant.to_sym
      when :floating
        <<~HTML
          <section class="form-section py-5">
            <div class="container">
              <div class="row justify-content-center">
                <div class="col-lg-6">
                  <div class="card shadow-sm">
                    <div class="card-body p-4">
                      <h4 class="card-title text-center mb-4">{{form_title}}</h4>
                      <form action="{{form_action}}" method="POST">
                        {{#fields}}
                        <div class="form-floating mb-3">
                          <input type="{{type}}" class="form-control" id="{{name}}" name="{{name}}" placeholder="{{label}}" {{#required}}required{{/required}}>
                          <label for="{{name}}">{{label}}</label>
                        </div>
                        {{/fields}}
                        <button type="submit" class="btn btn-primary w-100">{{submit_text}}</button>
                      </form>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </section>
        HTML
      else
        <<~HTML
          <section class="form-section py-5">
            <div class="container">
              <form action="{{form_action}}" method="POST">
                {{#fields}}
                <div class="mb-3">
                  <label for="{{name}}" class="form-label">{{label}}</label>
                  <input type="{{type}}" class="form-control" id="{{name}}" name="{{name}}" {{#required}}required{{/required}}>
                </div>
                {{/fields}}
                <button type="submit" class="btn btn-primary">{{submit_text}}</button>
              </form>
            </div>
          </section>
        HTML
      end
    end

    private_class_method def self.generate_cta_template(variant, config)
      <<~HTML
        <section class="cta py-5 bg-primary text-white">
          <div class="container text-center">
            <h2 class="fw-bold mb-3">{{headline}}</h2>
            <p class="lead mb-4">{{subheadline}}</p>
            <a href="{{cta_url}}" class="btn btn-light btn-lg">{{cta_text}}</a>
          </div>
        </section>
      HTML
    end
  end
end

