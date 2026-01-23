# frozen_string_literal: true

module Workflows
  # CompilerService converts a visual workflow definition (nodes + connections)
  # into an executable set of compiled steps.
  #
  # This is the bridge between "design with probability" and "run with determinism":
  # - Visual design: AI helps create, suggests improvements, handles ambiguity
  # - Compiled steps: Deterministic execution order, validated inputs/outputs
  #
  # The compilation process:
  # 1. Parse the visual definition (nodes, connections)
  # 2. Validate all nodes and their configurations
  # 3. Build a directed graph of execution flow
  # 4. Topologically sort nodes (respecting dependencies)
  # 5. Resolve variable references between nodes
  # 6. Generate executable step definitions
  # 7. Store compiled_steps on the AutomationCode
  #
  class CompilerService
    attr_reader :automation_code, :errors, :warnings

    def initialize(automation_code)
      @automation_code = automation_code
      @errors = []
      @warnings = []
      @node_registry = NodeRegistry.instance
    end

    # Compile the workflow and update the automation_code
    # Returns { success: true/false, errors: [], warnings: [], compiled_steps: [] }
    def compile!
      @errors = []
      @warnings = []

      # Parse the visual definition
      definition = parse_definition
      return failure("No workflow definition found") if definition.blank?

      nodes = definition['nodes'] || []
      connections = definition['connections'] || []

      return failure("No nodes in workflow") if nodes.empty?

      # Step 1: Validate all nodes
      validated_nodes = validate_nodes(nodes)
      return failure("Node validation failed") if @errors.any?

      # Step 2: Find trigger node (entry point)
      trigger_node = find_trigger_node(validated_nodes)
      return failure("Workflow must have exactly one trigger node") unless trigger_node

      # Step 3: Build connection graph
      graph = build_graph(validated_nodes, connections)

      # Step 4: Topologically sort (execution order)
      sorted_node_ids = topological_sort(graph, trigger_node['id'])
      return failure("Workflow has circular dependencies") if @errors.any?

      # Step 5: Generate compiled steps
      compiled_steps = generate_compiled_steps(validated_nodes, sorted_node_ids, graph)

      # Step 6: Resolve variable references
      resolved_steps = resolve_variable_references(compiled_steps)

      # Step 7: Save to automation_code
      save_compilation(resolved_steps)

      {
        success: true,
        errors: @errors,
        warnings: @warnings,
        compiled_steps: resolved_steps,
        stats: {
          total_nodes: nodes.size,
          compiled_steps: resolved_steps.size,
          trigger_type: trigger_node['type']
        }
      }
    rescue => e
      Rails.logger.error "[WorkflowCompiler] Compilation failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      failure("Compilation error: #{e.message}")
    end

    # Validate without saving
    def validate
      compile_result = compile!
      
      # Roll back the save
      @automation_code.reload
      
      compile_result
    end

    private

    def parse_definition
      definition = automation_code.workflow_definition
      return {} if definition.blank?

      definition.is_a?(String) ? JSON.parse(definition) : definition.with_indifferent_access
    rescue JSON::ParserError
      @errors << "Invalid workflow definition JSON"
      {}
    end

    def validate_nodes(nodes)
      validated = []

      nodes.each do |node|
        node_id = node['id']
        node_type = node['type']
        node_config = node['config'] || node['data'] || {}

        # Check if node type exists in registry
        node_def = @node_registry.get(node_type)
        unless node_def
          @errors << "Unknown node type: #{node_type} (node: #{node_id})"
          next
        end

        # Validate node configuration against schema
        validation = @node_registry.validate_node(node_type, node_config)
        unless validation[:valid]
          validation[:errors].each do |err|
            @errors << "Node #{node_id}: #{err}"
          end
          next
        end

        validated << node.merge(
          'definition' => node_def,
          'validated_config' => node_config
        )
      end

      validated
    end

    def find_trigger_node(nodes)
      triggers = nodes.select { |n| n['definition'][:category] == 'trigger' }

      if triggers.empty?
        @errors << "Workflow must have a trigger node"
        return nil
      end

      if triggers.size > 1
        @warnings << "Workflow has multiple trigger nodes, using first one: #{triggers.first['id']}"
      end

      triggers.first
    end

    def build_graph(nodes, connections)
      # Build adjacency lists for the graph
      # forward: node_id -> [downstream_node_ids]
      # backward: node_id -> [upstream_node_ids]
      
      graph = {
        nodes: {},
        forward: Hash.new { |h, k| h[k] = [] },
        backward: Hash.new { |h, k| h[k] = [] },
        connections: {}
      }

      # Index nodes by ID
      nodes.each do |node|
        graph[:nodes][node['id']] = node
      end

      # Process connections
      connections.each do |conn|
        from_id = conn['from'] || conn['fromNode'] || conn['source']
        to_id = conn['to'] || conn['toNode'] || conn['target']
        from_port = conn['fromPort'] || conn['sourcePort'] || 'default'
        to_port = conn['toPort'] || conn['targetPort'] || 'default'

        unless graph[:nodes][from_id]
          @warnings << "Connection references unknown source node: #{from_id}"
          next
        end

        unless graph[:nodes][to_id]
          @warnings << "Connection references unknown target node: #{to_id}"
          next
        end

        graph[:forward][from_id] << { node: to_id, from_port: from_port, to_port: to_port }
        graph[:backward][to_id] << { node: from_id, from_port: from_port, to_port: to_port }
        
        # Store connection details for variable resolution
        conn_key = "#{from_id}:#{from_port}->#{to_id}:#{to_port}"
        graph[:connections][conn_key] = conn
      end

      graph
    end

    def topological_sort(graph, start_node_id)
      visited = Set.new
      temp_mark = Set.new
      sorted = []

      visit = lambda do |node_id|
        return if visited.include?(node_id)

        if temp_mark.include?(node_id)
          @errors << "Circular dependency detected involving node: #{node_id}"
          return
        end

        temp_mark.add(node_id)

        # Visit all downstream nodes
        graph[:forward][node_id].each do |downstream|
          visit.call(downstream[:node])
        end

        temp_mark.delete(node_id)
        visited.add(node_id)
        sorted.unshift(node_id)
      end

      # Start from trigger node
      visit.call(start_node_id)

      # Also visit any unreachable nodes (warning)
      graph[:nodes].keys.each do |node_id|
        unless visited.include?(node_id)
          @warnings << "Node #{node_id} is not reachable from trigger"
          visit.call(node_id)
        end
      end

      sorted
    end

    def generate_compiled_steps(nodes_map, sorted_node_ids, graph)
      steps = []
      step_index = 0

      sorted_node_ids.each do |node_id|
        node = graph[:nodes][node_id]
        next unless node

        node_def = node['definition']
        config = node['validated_config'] || node['config'] || node['data'] || {}

        step = {
          'step_index' => step_index,
          'step_id' => node_id,
          'node_type' => node['type'],
          'category' => node_def[:category],
          'label' => node['label'] || node_def[:label],
          'executor' => node_def[:executor],
          'config' => config,
          'inputs' => build_step_inputs(node, node_def, graph),
          'outputs' => build_step_outputs(node, node_def, graph),
          'next_steps' => graph[:forward][node_id].map { |d| d[:node] },
          'conditions' => extract_conditions(node, node_def, graph),
          'position' => { 'x' => node['x'], 'y' => node['y'] }
        }

        steps << step
        step_index += 1
      end

      steps
    end

    def build_step_inputs(node, node_def, graph)
      inputs = {}

      # Get input definitions from node type
      (node_def[:inputs] || []).each do |input_def|
        input_name = input_def[:name]
        inputs[input_name] = {
          'name' => input_name,
          'type' => input_def[:type],
          'required' => input_def[:required] || false,
          'source' => nil  # Will be resolved from connections
        }
      end

      # Resolve sources from connections
      graph[:backward][node['id']].each do |upstream|
        from_port = upstream[:from_port]
        to_port = upstream[:to_port]

        # Map connection to input
        input_key = to_port == 'default' ? inputs.keys.first : to_port
        if inputs[input_key]
          inputs[input_key]['source'] = {
            'step_id' => upstream[:node],
            'output' => from_port == 'default' ? 'result' : from_port
          }
        end
      end

      inputs
    end

    def build_step_outputs(node, node_def, graph)
      outputs = {}

      (node_def[:outputs] || []).each do |output_def|
        output_name = output_def[:name]
        outputs[output_name] = {
          'name' => output_name,
          'type' => output_def[:type],
          'targets' => []
        }
      end

      # Find targets from connections
      graph[:forward][node['id']].each do |downstream|
        from_port = downstream[:from_port]
        output_key = from_port == 'default' ? outputs.keys.first : from_port

        if outputs[output_key]
          outputs[output_key]['targets'] << {
            'step_id' => downstream[:node],
            'input' => downstream[:to_port]
          }
        end
      end

      outputs
    end

    def extract_conditions(node, node_def, graph)
      return nil unless node_def[:category] == 'logic'

      config = node['config'] || node['data'] || {}

      case node['type']
      when 'logic-condition'
        {
          'type' => 'if',
          'field' => config['field'],
          'operator' => config['operator'],
          'compare_to' => config['compare_to'],
          'true_step' => graph[:forward][node['id']].find { |d| d[:from_port] == 'true' }&.dig(:node),
          'false_step' => graph[:forward][node['id']].find { |d| d[:from_port] == 'false' }&.dig(:node)
        }
      when 'logic-switch'
        cases = (config['cases'] || []).map do |c|
          target = graph[:forward][node['id']].find { |d| d[:from_port] == c['output_name'] }
          {
            'value' => c['value'],
            'step' => target&.dig(:node)
          }
        end
        default_target = graph[:forward][node['id']].find { |d| d[:from_port] == 'default' }
        {
          'type' => 'switch',
          'field' => config['field'],
          'cases' => cases,
          'default_step' => default_target&.dig(:node)
        }
      when 'logic-loop'
        {
          'type' => 'loop',
          'items_field' => config['items_field'],
          'max_iterations' => config['max_iterations'] || 100,
          'parallel' => config['parallel'] || false,
          'loop_body_step' => graph[:forward][node['id']].find { |d| d[:from_port] == 'item' }&.dig(:node),
          'completed_step' => graph[:forward][node['id']].find { |d| d[:from_port] == 'completed' }&.dig(:node)
        }
      else
        nil
      end
    end

    def resolve_variable_references(steps)
      # Build a map of step_id -> step for quick lookup
      step_map = steps.index_by { |s| s['step_id'] }

      steps.each do |step|
        config = step['config'] || {}
        
        # Resolve {{variable}} references in config values
        step['config'] = deep_resolve_variables(config, step_map, step)

        # Mark where outputs come from
        step['inputs'].each do |input_name, input_def|
          next unless input_def['source']
          
          source_step_id = input_def['source']['step_id']
          source_output = input_def['source']['output']
          
          # Create a reference path
          input_def['variable_path'] = "steps.#{source_step_id}.outputs.#{source_output}"
        end
      end

      steps
    end

    def deep_resolve_variables(obj, step_map, current_step)
      case obj
      when Hash
        obj.transform_values { |v| deep_resolve_variables(v, step_map, current_step) }
      when Array
        obj.map { |v| deep_resolve_variables(v, step_map, current_step) }
      when String
        resolve_string_variables(obj, step_map, current_step)
      else
        obj
      end
    end

    def resolve_string_variables(str, step_map, current_step)
      # Replace {{step_id.output_name}} with reference markers
      # These will be resolved at runtime
      str.gsub(/\{\{([^}]+)\}\}/) do |match|
        var_path = $1.strip
        
        # Parse the path
        parts = var_path.split('.')
        
        if parts.size == 1
          # Simple variable reference - look in trigger context or previous step outputs
          "{{context.#{var_path}}}"
        elsif parts.size >= 2
          # Step output reference
          step_id = parts[0]
          output_name = parts[1..-1].join('.')
          
          if step_map[step_id]
            "{{steps.#{step_id}.outputs.#{output_name}}}"
          else
            @warnings << "Variable reference to unknown step: #{step_id}"
            match
          end
        else
          match
        end
      end
    end

    def save_compilation(compiled_steps)
      automation_code.update!(
        compiled_steps: compiled_steps,
        compiled_at: Time.current,
        compilation_errors: @errors,
        is_compiled: @errors.empty?
      )
    end

    def failure(message)
      @errors << message unless @errors.include?(message)
      {
        success: false,
        errors: @errors,
        warnings: @warnings,
        compiled_steps: []
      }
    end
  end
end
