module Tools
  class GetTemplateDetailsTool < BaseTool
    def self.metadata
      {
        name: 'get_template_details',
        description: 'Get detailed information about a workflow template to understand its purpose and capabilities',
        category: 'workflow',
        input_schema: {
          type: 'object',
          properties: {
            template_slug: {
              type: 'string',
              description: 'The slug/ID of the template to get details for'
            }
          },
          required: ['template_slug']
        }
      }
    end
    
    def execute(args)
      template_slug = args['template_slug']
      
      # Load the template
      template_data = WorkflowTemplateLoader.load_template_by_slug(template_slug)
      
      unless template_data
        return {
          success: false,
          error: "Template '#{template_slug}' not found"
        }
      end
      
      # Return detailed information
      {
        success: true,
        template: {
          slug: template_data[:slug] || template_data['slug'],
          name: template_data[:name] || template_data['name'],
          description: template_data[:description] || template_data['description'],
          category: template_data[:category] || template_data['category'],
          
          # Phase information (V2 structure)
          phases: extract_phase_summary(template_data),
          
          # What this template does
          capabilities: extract_capabilities(template_data),
          
          # What it needs from the user
          required_inputs: extract_required_inputs(template_data),
          
          # Full spec (if needed)
          full_spec: template_data[:template_spec] || template_data['template_spec']
        }
      }
    end
    
    private
    
    def extract_phase_summary(template_data)
      spec = template_data[:template_spec] || template_data['template_spec']
      phases = spec[:phases] || spec['phases'] || []
      
      phases.map do |phase|
        {
          id: phase[:id] || phase['id'],
          name: phase[:name] || phase['name'],
          type: phase[:type] || phase['type'],
          goal: phase[:goal] || phase['goal']
        }
      end
    end
    
    def extract_capabilities(template_data)
      spec = template_data[:template_spec] || template_data['template_spec']
      
      # Extract from config and phases
      capabilities = []
      
      # From config
      config = spec[:config] || spec['config'] || {}
      capabilities << "Context-aware (uses uploaded files)" if config[:context_aware] || config['context_aware']
      capabilities << "Conversational (natural dialogue)" if config[:conversational] || config['conversational']
      capabilities << "Self-healing (auto-fixes issues)" if config[:self_healing] || config['self_healing']
      
      # From phases
      phases = spec[:phases] || spec['phases'] || []
      phases.each do |phase|
        type = phase[:type] || phase['type']
        case type.to_s
        when 'gather_context'
          capabilities << "Intelligently gathers requirements from files and conversation"
        when 'execute_goal'
          capabilities << "Adaptively achieves goals using available tools"
        when 'validate_result'
          capabilities << "Validates quality and auto-fixes issues"
        end
      end
      
      capabilities.uniq
    end
    
    def extract_required_inputs(template_data)
      spec = template_data[:template_spec] || template_data['template_spec']
      phases = spec[:phases] || spec['phases'] || []
      
      # Find gather_context phases and extract required knowledge
      required_inputs = []
      
      phases.each do |phase|
        if (phase[:type] || phase['type']).to_s == 'gather_context'
          knowledge = phase[:required_knowledge] || phase['required_knowledge'] || {}
          knowledge.each do |category, fields|
            required_inputs << {
              category: category,
              fields: fields
            }
          end
        end
      end
      
      required_inputs
    end
  end
end
