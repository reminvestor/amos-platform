# Imports Claude SKILL.md files and converts them into AgentPlugins
#
# This enables users to:
# 1. Paste a SKILL.md file content
# 2. Import from a URL (e.g., GitHub raw file)
# 3. Upload a .md file
#
# The service parses the three-level structure:
# - Level 1: Metadata (name, description) -> AgentPlugin.name, .description
# - Level 2: Instructions -> AgentPlugin.system_prompt
# - Level 3: Resources (referenced scripts/docs) -> AgentPlugin.configuration['resources']
#
class SkillFileImporterService
  SKILL_MD_SECTIONS = %w[description instructions examples resources verification].freeze

  Result = Struct.new(:success, :agent_plugin, :errors, keyword_init: true)

  def initialize(entity:, user:)
    @entity = entity
    @user = user
    @errors = []
  end

  # Import from raw markdown content
  def import_from_content(content, source: 'paste')
    parsed = parse_skill_md(content)
    
    return Result.new(success: false, errors: @errors) if @errors.any?
    
    agent = create_agent_plugin(parsed, source: source)
    
    if agent.persisted?
      Result.new(success: true, agent_plugin: agent)
    else
      Result.new(success: false, errors: agent.errors.full_messages)
    end
  end

  # Import from a URL (e.g., GitHub raw file)
  def import_from_url(url)
    require 'net/http'
    require 'uri'
    
    begin
      uri = URI.parse(url)
      
      # Convert GitHub blob URLs to raw URLs
      if uri.host == 'github.com' && url.include?('/blob/')
        url = url.gsub('github.com', 'raw.githubusercontent.com').gsub('/blob/', '/')
        uri = URI.parse(url)
      end
      
      response = Net::HTTP.get_response(uri)
      
      if response.is_a?(Net::HTTPSuccess)
        import_from_content(response.body, source: url)
      else
        Result.new(success: false, errors: ["Failed to fetch URL: #{response.code} #{response.message}"])
      end
    rescue => e
      Result.new(success: false, errors: ["Failed to fetch URL: #{e.message}"])
    end
  end

  private

  def parse_skill_md(content)
    result = {
      name: nil,
      description: nil,
      sections: {},
      use_when: [],
      examples: []
    }

    lines = content.lines
    current_section = nil
    current_content = []

    lines.each do |line|
      # Title line - first H1
      if line.match?(/^#\s+(.+)$/) && result[:name].nil?
        result[:name] = line.match(/^#\s+(.+)$/)[1].strip
        next
      end

      # First paragraph after title (before any ##) is the short description
      if result[:name] && current_section.nil? && !line.match?(/^##/) && line.strip.present?
        result[:description] ||= ''
        result[:description] += line
        next
      end

      # Section headers (##)
      if line.match?(/^##\s+(.+)$/)
        # Save previous section
        if current_section
          result[:sections][current_section] = current_content.join
        end

        section_name = line.match(/^##\s+(.+)$/)[1].strip.downcase
        current_section = normalize_section_name(section_name)
        current_content = []
        next
      end

      # Accumulate content
      current_content << line if current_section
    end

    # Save final section
    if current_section
      result[:sections][current_section] = current_content.join
    end

    # Extract "Use this skill when:" bullet points
    if result[:sections]['description']
      desc = result[:sections]['description']
      if desc.include?('Use this skill when:') || desc.include?('**Use this skill when:**')
        use_when_match = desc.match(/\*?\*?Use this skill when:\*?\*?\s*\n((?:[-*]\s+.+\n?)+)/i)
        if use_when_match
          result[:use_when] = use_when_match[1].scan(/[-*]\s+(.+)/).flatten.map(&:strip)
        end
      end
    end

    # Extract examples
    if result[:sections]['examples']
      result[:examples] = extract_code_blocks(result[:sections]['examples'])
    end

    # Validate required fields
    @errors << "Missing skill name (# Title)" if result[:name].blank?
    @errors << "Missing description" if result[:description].blank? && result[:sections]['description'].blank?
    @errors << "Missing instructions section" if result[:sections]['instructions'].blank?

    result
  end

  def normalize_section_name(name)
    case name.downcase
    when /description/i then 'description'
    when /instruction/i then 'instructions'
    when /example/i then 'examples'
    when /resource/i then 'resources'
    when /verification|checklist/i then 'verification'
    when /usage|when to use/i then 'usage'
    else name.parameterize.underscore
    end
  end

  def extract_code_blocks(content)
    content.scan(/```(?:\w+)?\n(.*?)```/m).flatten
  end

  def create_agent_plugin(parsed, source:)
    # Generate slug from name
    base_slug = parsed[:name].parameterize.underscore
    slug = base_slug
    
    # Ensure unique slug
    counter = 1
    while AgentPlugin.exists?(slug: slug)
      slug = "#{base_slug}_#{counter}"
      counter += 1
    end

    # Combine description sources
    full_description = parsed[:description].to_s.strip
    if parsed[:sections]['description'].present?
      full_description = parsed[:sections]['description'].strip
    end

    # Build system prompt from instructions
    system_prompt = build_system_prompt(parsed)

    # Determine role based on content
    role = detect_role(parsed)

    # Build configuration
    configuration = {
      'source' => source,
      'imported_at' => Time.current.iso8601,
      'skill_format' => 'claude_skill_md',
      'use_when' => parsed[:use_when],
      'examples' => parsed[:examples],
      'resources' => extract_resource_references(parsed[:sections]['resources'])
    }.compact

    # Build capabilities definition
    capabilities = {
      'primary' => detect_capabilities(parsed),
      'use_cases' => parsed[:use_when]
    }

    AgentPlugin.create(
      name: parsed[:name],
      slug: slug,
      description: full_description.truncate(1000),
      role: role,
      status: 'draft',
      entity: @entity,
      user: @user,
      system_prompt: system_prompt,
      configuration: configuration,
      capabilities_definition: capabilities
    )
  end

  def build_system_prompt(parsed)
    prompt_parts = []

    # Core identity
    prompt_parts << "You are a specialized agent that follows the #{parsed[:name]} methodology."
    prompt_parts << ""

    # Instructions (the meat of the skill)
    if parsed[:sections]['instructions'].present?
      prompt_parts << "## Instructions"
      prompt_parts << parsed[:sections]['instructions'].strip
    end

    # Verification checklist (if present)
    if parsed[:sections]['verification'].present?
      prompt_parts << ""
      prompt_parts << "## Verification Checklist"
      prompt_parts << parsed[:sections]['verification'].strip
    end

    {
      'prompt' => prompt_parts.join("\n"),
      'style' => 'instructional',
      'format' => 'skill_based'
    }
  end

  def detect_role(parsed)
    content = "#{parsed[:name]} #{parsed[:description]} #{parsed[:sections].values.join(' ')}".downcase

    if content.include?('test') || content.include?('tdd') || content.include?('verification')
      'verifier'
    elsif content.include?('analyz') || content.include?('review') || content.include?('audit')
      'analyst'
    elsif content.include?('plan') || content.include?('design') || content.include?('architect')
      'planner'
    elsif content.include?('build') || content.include?('create') || content.include?('implement')
      'executor'
    else
      'executor'  # Default
    end
  end

  def detect_capabilities(parsed)
    capabilities = []
    content = "#{parsed[:name]} #{parsed[:sections].values.join(' ')}".downcase

    capabilities << 'testing' if content.include?('test')
    capabilities << 'code_review' if content.include?('review')
    capabilities << 'debugging' if content.include?('debug')
    capabilities << 'documentation' if content.include?('document')
    capabilities << 'deployment' if content.include?('deploy')
    capabilities << 'development' if content.include?('develop') || content.include?('implement')
    capabilities << 'analysis' if content.include?('analyz')
    capabilities << 'git_operations' if content.include?('git') || content.include?('commit')

    capabilities.uniq
  end

  def extract_resource_references(resources_section)
    return [] if resources_section.blank?

    # Extract markdown links and references
    resources_section.scan(/\[([^\]]+)\]\(([^)]+)\)/).map do |name, path|
      { 'name' => name, 'path' => path }
    end
  end
end
