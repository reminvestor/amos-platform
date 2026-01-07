# AI Ruleset Service - Builds system prompt sections from active rulesets
#
# Usage:
#   service = AiRulesetService.new(entity)
#   prompt_section = service.to_system_prompt_section
#
class AiRulesetService
  def initialize(entity)
    @entity = entity
  end

  # Get all active rulesets for this entity (includes global rulesets)
  def active_rulesets
    AiRuleset.for_entity(@entity).active.by_priority
  end

  # Get rulesets grouped by category
  def rulesets_by_category
    active_rulesets.group_by(&:category)
  end

  # Build the system prompt section from all active rulesets
  def to_system_prompt_section
    rulesets = active_rulesets
    return "" if rulesets.empty?

    sections = build_category_sections(rulesets)
    return "" if sections.empty?

    <<~PROMPT
      ## BEHAVIORAL RULES
      You MUST follow these rules strictly. These are non-negotiable constraints.

      #{sections.join("\n\n")}
    PROMPT
  end

  # Preview what the prompt section will look like (for admin UI)
  def preview_prompt
    section = to_system_prompt_section
    return "No active rulesets for this entity." if section.blank?
    section
  end

  # Get statistics about rulesets for this entity
  def stats
    rulesets = active_rulesets
    {
      total_rulesets: rulesets.count,
      global_rulesets: rulesets.count(&:global?),
      entity_rulesets: rulesets.count { |r| !r.global? },
      total_rules: rulesets.sum { |r| r.rules.count },
      categories: rulesets.map(&:category).uniq,
      system_presets: rulesets.count(&:is_system?)
    }
  end

  private

  def build_category_sections(rulesets)
    rulesets.group_by(&:category).map do |category, category_rulesets|
      rules = category_rulesets.flat_map(&:rules).compact.reject(&:blank?)
      next if rules.empty?

      numbered_rules = rules.map.with_index(1) { |rule, i| "#{i}. #{rule}" }.join("\n")
      "### #{format_category_name(category)}\n#{numbered_rules}"
    end.compact
  end

  def format_category_name(category)
    case category
    when "safety"
      "Safety & Security Rules"
    when "tone"
      "Tone & Communication Rules"
    when "compliance"
      "Compliance & Legal Rules"
    when "domain"
      "Domain Best Practices"
    when "custom"
      "Custom Rules"
    else
      category.titleize
    end
  end
end
