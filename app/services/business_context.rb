# frozen_string_literal: true

# BusinessContext — Single source of truth for resolving business profile data.
#
# The BusinessProfile model is linked via user_id, but sometimes entity_id
# is nil (legacy data). This service centralizes the lookup logic so every
# service doesn't re-implement the same fallback chain.
#
# Usage:
#   ctx = BusinessContext.for(user, entity)
#   ctx.company_name  # => "Nuvola Networks"
#   ctx.industry       # => "eLearning"
#   ctx.to_h           # => { company_name: "Nuvola Networks", industry: "eLearning", ... }
#   ctx.present?       # => true (has at least a name)
#
# When the data model is cleaned up (entity_id always set), this class
# can be simplified to a single query — one place to change.
#
class BusinessContext
  PROFILE_FIELDS = %i[industry description target_audience tone_of_voice website].freeze
  STYLE_FIELDS   = %w[colors brand_colors tagline value_proposition services mission].freeze

  attr_reader :profile

  def self.for(user, entity)
    new(user: user, entity: entity)
  end

  def initialize(user:, entity:)
    @profile = resolve_profile(user, entity)
    @entity = entity
    @user = user

    # Backfill entity_id if missing (one-time self-healing)
    if @profile && @profile.entity_id.nil? && entity&.id.present?
      @profile.update_column(:entity_id, entity.id) rescue nil
    end
  end

  # Core accessors — safe even if profile is nil
  def company_name
    @profile&.name || @entity&.name || "Organization"
  end

  def industry;        @profile&.industry;        end
  def description;     @profile&.description;     end
  def target_audience; @profile&.target_audience;  end
  def tone_of_voice;   @profile&.tone_of_voice;   end
  def website;         @profile&.website;          end

  # Style guidelines accessors (from JSONB)
  def brand_colors
    style_value("colors") || style_value("brand_colors") || entity_brand("colors")
  end

  def tagline;           style_value("tagline");           end
  def value_proposition; style_value("value_proposition"); end
  def services;          style_value("services");          end
  def mission;           style_value("mission");           end
  def brand_fonts;       entity_brand("fonts");            end

  def present?
    @profile.present?
  end

  # Full hash for injection into prompts / tool context
  def to_h
    return {} unless @profile

    result = {
      company_name: company_name,
      industry: industry,
      description: description,
      target_audience: target_audience,
      tone_of_voice: tone_of_voice,
      website: website,
      brand_colors: brand_colors,
      brand_fonts: brand_fonts,
      tagline: tagline,
      value_proposition: value_proposition,
      services: services,
      mission: mission,
    }

    result[:logo_url] = @entity.logo_url if @entity.respond_to?(:logo_url)

    result.compact
  end

  # Brief one-liner for system prompts (avoids bloating token count)
  def summary
    parts = []
    parts << "Business: #{company_name}" if company_name.present?
    parts << "Industry: #{industry}" if industry.present?
    parts << "Description: #{description}" if description.present?
    parts << "Target Audience: #{target_audience}" if target_audience.present?
    parts << "Website: #{website}" if website.present?
    parts << "Brand Voice: #{tone_of_voice}" if tone_of_voice.present?
    parts.join("\n- ")
  end

  private

  def resolve_profile(user, entity)
    # 1. Entity-scoped lookup (correct path)
    profile = entity&.business_profiles&.first rescue nil
    return profile if profile

    # 2. User-scoped fallback (legacy data with nil entity_id)
    user&.business_profile rescue nil
  end

  def style_value(key)
    sg = @profile&.style_guidelines
    sg.is_a?(Hash) ? sg[key] : nil
  end

  def entity_brand(key)
    @entity&.respond_to?(:brand_settings) ? @entity.brand_settings&.dig(key) : nil
  end
end
