# frozen_string_literal: true

# WebAppScript - Manages JavaScript libraries for web apps, websites, and landing pages
#
# Supports three types of scripts:
# 1. CDN - External scripts loaded from CDN (with SRI hash)
# 2. Inline - Custom inline JavaScript
# 3. NPM - Reference to npm packages (for build systems)
#
# Security: Only allowlisted libraries can be loaded via CDN
#
class WebAppScript < ApplicationRecord
  belongs_to :entity
  belongs_to :web_app, optional: true
  belongs_to :website, optional: true
  belongs_to :landing_page, optional: true

  # ============================================
  # ALLOWLISTED LIBRARIES (Security)
  # ============================================
  
  # Only these libraries can be loaded from CDN
  # Each entry includes: name, CDN URL pattern, and description
  ALLOWED_LIBRARIES = {
    # UI/UX Libraries
    'alpine.js' => {
      cdn: 'https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js',
      description: 'Lightweight reactive framework',
      category: 'ui'
    },
    'htmx' => {
      cdn: 'https://unpkg.com/htmx.org@1.x.x',
      description: 'HTML extensions for AJAX, WebSockets',
      category: 'ui'
    },
    'hyperscript' => {
      cdn: 'https://unpkg.com/hyperscript.org@0.x.x',
      description: 'Scripting language for web',
      category: 'ui'
    },
    
    # Animation
    'gsap' => {
      cdn: 'https://cdnjs.cloudflare.com/ajax/libs/gsap/3.x.x/gsap.min.js',
      description: 'GreenSock Animation Platform',
      category: 'animation'
    },
    'animate.css' => {
      cdn: 'https://cdnjs.cloudflare.com/ajax/libs/animate.css/4.x.x/animate.min.css',
      description: 'CSS animations library',
      category: 'animation',
      is_css: true
    },
    'aos' => {
      cdn: 'https://unpkg.com/aos@2.x.x/dist/aos.js',
      description: 'Animate On Scroll library',
      category: 'animation'
    },
    
    # Charts/Data Viz
    'chart.js' => {
      cdn: 'https://cdn.jsdelivr.net/npm/chart.js@4.x.x/dist/chart.umd.min.js',
      description: 'Simple yet flexible charting',
      category: 'charts'
    },
    'apexcharts' => {
      cdn: 'https://cdn.jsdelivr.net/npm/apexcharts@3.x.x/dist/apexcharts.min.js',
      description: 'Modern charting library',
      category: 'charts'
    },
    
    # Forms
    'flatpickr' => {
      cdn: 'https://cdn.jsdelivr.net/npm/flatpickr@4.x.x/dist/flatpickr.min.js',
      description: 'Lightweight date picker',
      category: 'forms'
    },
    'choices.js' => {
      cdn: 'https://cdn.jsdelivr.net/npm/choices.js@10.x.x/public/assets/scripts/choices.min.js',
      description: 'Configurable select boxes',
      category: 'forms'
    },
    'imask' => {
      cdn: 'https://unpkg.com/imask@7.x.x/dist/imask.min.js',
      description: 'Input masking',
      category: 'forms'
    },
    
    # Utilities
    'lodash' => {
      cdn: 'https://cdn.jsdelivr.net/npm/lodash@4.x.x/lodash.min.js',
      description: 'Utility library',
      category: 'utility'
    },
    'dayjs' => {
      cdn: 'https://cdn.jsdelivr.net/npm/dayjs@1.x.x/dayjs.min.js',
      description: '2KB date library',
      category: 'utility'
    },
    'axios' => {
      cdn: 'https://cdn.jsdelivr.net/npm/axios@1.x.x/dist/axios.min.js',
      description: 'HTTP client',
      category: 'utility'
    },
    
    # Media
    'swiper' => {
      cdn: 'https://cdn.jsdelivr.net/npm/swiper@11.x.x/swiper-bundle.min.js',
      description: 'Modern touch slider',
      category: 'media'
    },
    'lightgallery' => {
      cdn: 'https://cdn.jsdelivr.net/npm/lightgallery@2.x.x/lightgallery.min.js',
      description: 'Lightbox gallery',
      category: 'media'
    },
    'plyr' => {
      cdn: 'https://cdn.plyr.io/3.x.x/plyr.js',
      description: 'Media player',
      category: 'media'
    },
    
    # Maps
    'leaflet' => {
      cdn: 'https://unpkg.com/leaflet@1.x.x/dist/leaflet.js',
      description: 'Interactive maps',
      category: 'maps'
    }
  }.freeze

  # ============================================
  # ENUMS & VALIDATIONS
  # ============================================

  enum :library_type, { cdn: 'cdn', inline: 'inline', npm: 'npm' }
  enum :load_strategy, { defer: 'defer', async: 'async', blocking: 'blocking' }
  enum :status, { active: 'active', disabled: 'disabled', deprecated: 'deprecated' }

  validates :name, presence: true
  validates :library_type, presence: true
  validates :cdn_url, presence: true, if: :cdn?
  validates :inline_code, presence: true, if: :inline?
  validates :library_name, presence: true, if: :cdn?
  validate :validate_allowed_library, if: :cdn?
  validate :validate_inline_code_safety, if: :inline?

  # ============================================
  # SCOPES
  # ============================================

  scope :active, -> { where(status: :active) }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_web_app, ->(web_app) { where(web_app: web_app) }
  scope :for_website, ->(website) { where(website: website) }
  scope :for_landing_page, ->(lp) { where(landing_page: lp) }
  scope :in_load_order, -> { order(:load_order) }
  scope :by_category, ->(cat) { where("metadata->>'category' = ?", cat) }

  # ============================================
  # CLASS METHODS
  # ============================================

  def self.available_libraries
    ALLOWED_LIBRARIES.map do |name, config|
      {
        name: name,
        description: config[:description],
        category: config[:category],
        is_css: config[:is_css] || false
      }
    end
  end

  def self.libraries_by_category
    ALLOWED_LIBRARIES.group_by { |_, config| config[:category] }
      .transform_values { |libs| libs.map { |name, config| { name: name }.merge(config) } }
  end

  # ============================================
  # INSTANCE METHODS
  # ============================================

  def script_tag
    case library_type
    when 'cdn'
      attrs = []
      attrs << %(src="#{cdn_url}")
      attrs << %(integrity="#{integrity_hash}") if integrity_hash.present?
      attrs << 'crossorigin="anonymous"'
      attrs << load_strategy unless load_strategy == 'blocking'
      attrs << 'type="module"' if is_module?
      
      %(<script #{attrs.join(' ')}></script>)
    when 'inline'
      type_attr = is_module? ? ' type="module"' : ''
      %(<script#{type_attr}>\n#{inline_code}\n</script>)
    when 'npm'
      # NPM packages need to be bundled - return a comment
      %(<!-- NPM: #{library_name}@#{version} -->)
    end
  end

  def library_info
    return nil unless cdn? && library_name.present?
    ALLOWED_LIBRARIES[library_name]
  end

  def category
    library_info&.dig(:category) || metadata['category']
  end

  private

  def validate_allowed_library
    return if library_name.blank?
    
    unless ALLOWED_LIBRARIES.key?(library_name)
      errors.add(:library_name, "is not in the allowlist. Allowed: #{ALLOWED_LIBRARIES.keys.join(', ')}")
    end
  end

  def validate_inline_code_safety
    return if inline_code.blank?
    
    # Basic security checks for inline code
    dangerous_patterns = [
      /eval\s*\(/i,
      /Function\s*\(/i,
      /document\.write/i,
      /innerHTML\s*=/i,
      /outerHTML\s*=/i,
      /<script/i,
      /\.constructor\s*\(/i,
      /window\[['"]eval['"]\]/i
    ]
    
    dangerous_patterns.each do |pattern|
      if inline_code.match?(pattern)
        errors.add(:inline_code, "contains potentially dangerous code pattern: #{pattern.source}")
        break
      end
    end
    
    # Max size limit
    if inline_code.bytesize > 100_000
      errors.add(:inline_code, "is too large (max 100KB)")
    end
  end
end

