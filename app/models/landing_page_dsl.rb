require "json-schema"

class LandingPageDsl
  # JSON Schema for validating landing page DSL structure
  SCHEMA = {
    "$schema" => "http://json-schema.org/draft-04/schema#",
    "type" => "object",
    "required" => [ "page" ],
    "properties" => {
      "page" => {
        "type" => "object",
        "required" => [ "theme", "sections" ],
        "properties" => {
          "theme" => {
            "type" => "string",
            "enum" => [ "clean", "modern", "bold", "professional", "creative" ]
          },
          "title" => {
            "type" => "string",
            "maxLength" => 100
          },
          "description" => {
            "type" => "string",
            "maxLength" => 200
          },
          "sections" => {
            "type" => "array",
            "minItems" => 1,
            "maxItems" => 10,
            "items" => {
              "type" => "object",
              "required" => [ "type" ],
              "properties" => {
                "type" => {
                  "type" => "string",
                  "enum" => [ "hero", "features", "cta", "testimonials", "contact", "about" ]
                },
                "headline" => { "type" => "string" },
                "subheadline" => { "type" => "string" },
                "title" => { "type" => "string" },
                "subtitle" => { "type" => "string" },
                "description" => { "type" => "string" },
                "content" => { "type" => "string" },
                "items" => { "type" => "array" },
                "fields" => { "type" => "array" },
                "cta" => { "type" => "object" },
                "button" => { "type" => "object" },
                "image" => { "type" => "object" },
                "background" => { "type" => "object" }
              },
              "additionalProperties": false
            }
          }
        }
      }
    },
    "definitions" => {
      "hero" => {
        "type" => "object",
        "required" => [ "type", "headline" ],
        "properties" => {
          "type" => { "const" => "hero" },
          "headline" => {
            "type" => "string",
            "minLength" => 5,
            "maxLength" => 100
          },
          "subheadline" => {
            "type" => "string",
            "maxLength" => 200
          },
          "cta" => { "$ref" => "#/definitions/button" },
          "image" => { "$ref" => "#/definitions/image" },
          "background" => { "$ref" => "#/definitions/background" }
        }
      },
      "features" => {
        "type" => "object",
        "required" => [ "type", "title", "items" ],
        "properties" => {
          "type" => { "const" => "features" },
          "title" => {
            "type" => "string",
            "maxLength" => 80
          },
          "subtitle" => {
            "type" => "string",
            "maxLength" => 150
          },
          "items" => {
            "type" => "array",
            "minItems" => 2,
            "maxItems" => 6,
            "items" => {
              "type" => "object",
              "required" => [ "title", "description" ],
              "properties" => {
                "title" => {
                  "type" => "string",
                  "maxLength" => 50
                },
                "description" => {
                  "type" => "string",
                  "maxLength" => 150
                },
                "icon" => {
                  "type" => "string",
                  "pattern" => "^[a-zA-Z0-9_-]+$"
                }
              }
            }
          }
        }
      },
      "cta" => {
        "type" => "object",
        "required" => [ "type", "headline", "button" ],
        "properties" => {
          "type" => { "const" => "cta" },
          "headline" => {
            "type" => "string",
            "maxLength" => 80
          },
          "description" => {
            "type" => "string",
            "maxLength" => 200
          },
          "button" => { "$ref" => "#/definitions/button" },
          "background" => { "$ref" => "#/definitions/background" }
        }
      },
      "testimonials" => {
        "type" => "object",
        "required" => [ "type", "title", "items" ],
        "properties" => {
          "type" => { "const" => "testimonials" },
          "title" => {
            "type" => "string",
            "maxLength" => 80
          },
          "items" => {
            "type" => "array",
            "minItems" => 1,
            "maxItems" => 3,
            "items" => {
              "type" => "object",
              "required" => [ "quote", "author" ],
              "properties" => {
                "quote" => {
                  "type" => "string",
                  "maxLength" => 300
                },
                "author" => {
                  "type" => "string",
                  "maxLength" => 50
                },
                "title" => {
                  "type" => "string",
                  "maxLength" => 50
                },
                "avatar" => { "$ref" => "#/definitions/image" }
              }
            }
          }
        }
      },
      "contact" => {
        "type" => "object",
        "required" => [ "type", "title" ],
        "properties" => {
          "type" => { "const" => "contact" },
          "title" => {
            "type" => "string",
            "maxLength" => 80
          },
          "description" => {
            "type" => "string",
            "maxLength" => 200
          },
          "fields" => {
            "type" => "array",
            "items" => {
              "type" => "string",
              "enum" => [ "name", "email", "phone", "company", "message" ]
            }
          }
        }
      },
      "about" => {
        "type" => "object",
        "required" => [ "type", "title", "content" ],
        "properties" => {
          "type" => { "const" => "about" },
          "title" => {
            "type" => "string",
            "maxLength" => 80
          },
          "content" => {
            "type" => "string",
            "maxLength" => 500
          },
          "image" => { "$ref" => "#/definitions/image" }
        }
      },
      "button" => {
        "type" => "object",
        "required" => [ "text", "action" ],
        "properties" => {
          "text" => {
            "type" => "string",
            "minLength" => 2,
            "maxLength" => 30
          },
          "action" => {
            "type" => "string",
            "enum" => [ "submit_form", "scroll_to", "external_link", "download" ]
          },
          "target" => {
            "type" => "string",
            "maxLength" => 200
          },
          "style" => {
            "type" => "string",
            "enum" => [ "primary", "secondary", "outline" ]
          }
        }
      },
      "image" => {
        "type" => "object",
        "required" => [ "src", "alt" ],
        "properties" => {
          "src" => {
            "type" => "string",
            "format" => "uri"
          },
          "alt" => {
            "type" => "string",
            "maxLength" => 100
          },
          "width" => {
            "type" => "integer",
            "minimum" => 50,
            "maximum" => 2000
          },
          "height" => {
            "type" => "integer",
            "minimum" => 50,
            "maximum" => 2000
          }
        }
      },
      "background" => {
        "type" => "object",
        "properties" => {
          "type" => {
            "type" => "string",
            "enum" => [ "color", "gradient", "image" ]
          },
          "value" => {
            "type" => "string"
          }
        }
      }
    }
  }.freeze

  # Theme configurations
  THEMES = {
    "clean" => {
      primary_color: "#2563eb",
      secondary_color: "#64748b",
      font_family: "Inter, sans-serif",
      border_radius: "8px"
    },
    "modern" => {
      primary_color: "#7c3aed",
      secondary_color: "#a78bfa",
      font_family: "Poppins, sans-serif",
      border_radius: "12px"
    },
    "bold" => {
      primary_color: "#dc2626",
      secondary_color: "#f59e0b",
      font_family: "Montserrat, sans-serif",
      border_radius: "4px"
    },
    "professional" => {
      primary_color: "#1f2937",
      secondary_color: "#6b7280",
      font_family: "Source Sans Pro, sans-serif",
      border_radius: "6px"
    },
    "creative" => {
      primary_color: "#ec4899",
      secondary_color: "#8b5cf6",
      font_family: "Nunito, sans-serif",
      border_radius: "16px"
    }
  }.freeze

  class << self
    # Validate DSL content against schema
    def validate(dsl_content)
      begin
        JSON::Validator.validate!(SCHEMA, dsl_content)
        { valid: true, errors: [] }
      rescue JSON::Schema::ValidationError => e
        { valid: false, errors: [ e.message ] }
      rescue => e
        { valid: false, errors: [ "Invalid JSON format: #{e.message}" ] }
      end
    end

    # Quick validation check
    def valid?(dsl_content)
      validate(dsl_content)[:valid]
    end

    # Get theme configuration
    def theme_config(theme_name)
      THEMES[theme_name] || THEMES["clean"]
    end

    # Get available themes
    def available_themes
      THEMES.keys
    end

    # Sanitize and normalize DSL content
    def sanitize(dsl_content)
      return nil unless dsl_content.is_a?(Hash)

      # Deep clone to avoid modifying original
      sanitized = deep_clone(dsl_content)

      # Sanitize strings
      sanitize_strings!(sanitized)

      # Ensure required structure
      sanitized["page"] ||= {}
      sanitized["page"]["theme"] ||= "clean"
      sanitized["page"]["sections"] ||= []

      sanitized
    end

    # Create a sample DSL for testing/examples
    def sample_dsl(business_type = "consulting")
      case business_type.downcase
      when "consulting"
        consulting_sample
      when "restaurant"
        restaurant_sample
      when "tech"
        tech_sample
      else
        generic_sample
      end
    end

    private

    def deep_clone(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_clone(v) }
      when Array
        obj.map { |v| deep_clone(v) }
      else
        obj.dup rescue obj
      end
    end

    def sanitize_strings!(obj)
      case obj
      when Hash
        obj.each do |key, value|
          if value.is_a?(String)
            obj[key] = sanitize_string(value)
          else
            sanitize_strings!(value)
          end
        end
      when Array
        obj.each { |item| sanitize_strings!(item) }
      end
    end

    def sanitize_string(str)
      # Remove HTML tags and dangerous characters
      str.gsub(/<[^>]*>/, "")
         .gsub(/[<>\"'&]/, "")
         .strip
         .truncate(500)
    end

    def consulting_sample
      {
        "page" => {
          "theme" => "professional",
          "title" => "Professional Consulting Services",
          "description" => "Expert consulting to grow your business",
          "sections" => [
            {
              "type" => "hero",
              "headline" => "Transform Your Business with Expert Consulting",
              "subheadline" => "Get strategic insights and actionable solutions from industry experts",
              "cta" => {
                "text" => "Schedule Consultation",
                "action" => "submit_form",
                "style" => "primary"
              }
            },
            {
              "type" => "features",
              "title" => "Our Services",
              "items" => [
                {
                  "title" => "Strategic Planning",
                  "description" => "Develop comprehensive strategies for sustainable growth",
                  "icon" => "strategy"
                },
                {
                  "title" => "Process Optimization",
                  "description" => "Streamline operations for maximum efficiency",
                  "icon" => "optimize"
                },
                {
                  "title" => "Market Analysis",
                  "description" => "Deep insights into your market and competition",
                  "icon" => "analytics"
                }
              ]
            },
            {
              "type" => "cta",
              "headline" => "Ready to Get Started?",
              "description" => "Book a free 30-minute consultation to discuss your needs",
              "button" => {
                "text" => "Book Now",
                "action" => "submit_form",
                "style" => "primary"
              }
            }
          ]
        }
      }
    end

    def restaurant_sample
      {
        "page" => {
          "theme" => "bold",
          "title" => "Delicious Dining Experience",
          "sections" => [
            {
              "type" => "hero",
              "headline" => "Authentic Italian Cuisine",
              "subheadline" => "Fresh ingredients, traditional recipes, unforgettable flavors",
              "cta" => {
                "text" => "Make Reservation",
                "action" => "external_link",
                "target" => "/reservations"
              }
            }
          ]
        }
      }
    end

    def tech_sample
      {
        "page" => {
          "theme" => "modern",
          "title" => "Innovative Tech Solutions",
          "sections" => [
            {
              "type" => "hero",
              "headline" => "Build the Future with Our Platform",
              "subheadline" => "Cutting-edge technology solutions for modern businesses"
            }
          ]
        }
      }
    end

    def generic_sample
      {
        "page" => {
          "theme" => "clean",
          "title" => "Welcome to Our Service",
          "sections" => [
            {
              "type" => "hero",
              "headline" => "Your Success Starts Here",
              "subheadline" => "Professional services tailored to your needs"
            }
          ]
        }
      }
    end
  end
end

# Add truncate method if not available
class String
  def truncate(limit)
    length > limit ? "#{self[0...limit]}..." : self
  end unless method_defined?(:truncate)
end
