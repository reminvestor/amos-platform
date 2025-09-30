require 'concurrent'

class WorkflowEngineV2 < WorkflowEngine
  attr_reader :execution_mode, :parallel_executor, :resource_manager
  
  def initialize(task_session)
    super(task_session)
    @execution_mode = :intelligent # :sequential, :parallel, :intelligent
    @parallel_executor = Concurrent::FixedThreadPool.new(
      determine_thread_pool_size,
      name: "workflow-#{task_session.id}"
    )
    @resource_manager = ResourceManager.new(task_session.user.entity)
    @execution_graph = {}
    @step_futures = {}
    @execution_context = Agents::Communication::SharedContext.new(
      task_session_id: task_session.id
    )
  end
  
  # Start workflow with enhanced capabilities
  def start_workflow(workflow_spec, initial_inputs = {}, progress_callback = nil)
    @progress_callback = progress_callback
    
    # Analyze workflow for optimization opportunities
    analyze_workflow_structure(workflow_spec)
    
    # Set execution mode based on analysis
    @execution_mode = determine_execution_mode(workflow_spec)
    
    Rails.logger.info "WorkflowEngineV2: Starting workflow in #{@execution_mode} mode"
    
    # Notify progress
    @progress_callback&.call({
      type: :workflow_started,
      workflow_name: workflow_spec[:name] || workflow_spec['name'],
      total_steps: workflow_spec[:steps]&.length || 0
    })
    
    # Set progress callback on parent
    set_progress_callback(@progress_callback) if @progress_callback
    
    # Call parent implementation with enhancements
    super(workflow_spec, initial_inputs)
  end
  
  # Override to support parallel execution
  def execute_next_step(inputs = {})
    unless @workflow
      return {
        status: 'error',
        message: 'No active workflow'
      }
    end
    
    case @execution_mode
    when :parallel
      execute_parallel_workflow(inputs)
    when :intelligent
      execute_intelligent_workflow(inputs)
    else
      super # Sequential execution
    end
  end
  
  # Execute entire workflow in parallel where possible
  def execute_parallel_workflow(inputs = {})
    # Build execution graph
    build_execution_graph
    
    # Find all steps that can start immediately (no dependencies)
    ready_steps = find_ready_steps
    
    if ready_steps.empty?
      return {
        status: 'completed',
        message: 'No executable steps found',
        result: {}
      }
    end
    
    # Execute ready steps in parallel
    execute_step_batch(ready_steps, inputs)
    
    # Continue until all steps are complete
    while has_pending_steps?
      # Wait for any step to complete
      completed = wait_for_completions
      
      # Update execution graph
      mark_steps_completed(completed)
      
      # Find newly ready steps
      newly_ready = find_ready_steps
      
      if newly_ready.any?
        execute_step_batch(newly_ready, current_execution_context)
      end
    end
    
    # Collect final results
    collect_workflow_results
  end
  
  # Intelligent execution - mix of parallel and sequential
  def execute_intelligent_workflow(inputs = {})
    current_step = @workflow.current_step
    return super(inputs) unless current_step
    
    # Check if current step is part of a parallel group
    if parallel_group = find_parallel_group(current_step)
      execute_parallel_group(parallel_group, inputs)
    else
      # Check if we should prefetch/prepare next steps
      prefetch_next_steps(current_step)
      
      # Execute current step normally
      super(inputs)
    end
  end
  
  # Execute a group of steps in parallel
  def execute_parallel_group(steps, inputs)
    Rails.logger.info "WorkflowEngineV2: Executing #{steps.size} steps in parallel"
    
    # Check resource availability
    required_resources = calculate_required_resources(steps)
    unless @resource_manager.reserve_resources(required_resources)
      Rails.logger.warn "Insufficient resources for parallel execution, falling back to sequential"
      return execute_sequential_group(steps, inputs)
    end
    
    begin
      # Create futures for each step
      futures = steps.map do |step|
        Concurrent::Future.execute(executor: @parallel_executor) do
          execute_single_step(step, inputs)
        end
      end
      
      # Wait for all to complete with timeout
      timeout = calculate_timeout(steps)
      results = []
      
      futures.each_with_index do |future, index|
        begin
          result = future.value(timeout)
          results << result
          
          # Stream progress
          emit_progress_update(steps[index], result)
          
        rescue Concurrent::TimeoutError
          handle_step_timeout(steps[index])
          results << { status: 'timeout', step: steps[index].id }
        rescue => e
          handle_step_error(steps[index], e)
          results << { status: 'error', step: steps[index].id, error: e.message }
        end
      end
      
      # Process results
      process_parallel_results(steps, results)
      
    ensure
      @resource_manager.release_resources(required_resources)
    end
  end
  
  # Execute conditional logic
  def execute_conditional_step(step, inputs)
    condition = step.config[:condition]
    
    # Evaluate condition
    result = evaluate_condition(condition, inputs)
    
    # Determine which branch to take
    if result
      execute_branch(step.config[:then_branch], inputs)
    else
      execute_branch(step.config[:else_branch], inputs)
    end
  end
  
  # Execute loop logic
  def execute_loop_step(step, inputs)
    loop_config = step.config[:loop]
    items = resolve_items(loop_config[:over], inputs)
    
    # Determine if we can parallelize the loop
    if loop_config[:parallel] != false && items.size > 1
      execute_parallel_loop(step, items, inputs)
    else
      execute_sequential_loop(step, items, inputs)
    end
  end
  
  private
  
  def analyze_workflow_structure(workflow_spec)
    steps = workflow_spec[:steps] || []
    
    # Build dependency graph
    @execution_graph = build_dependency_graph(steps)
    
    # Analyze patterns
    @has_parallel_opportunities = detect_parallel_opportunities(steps)
    @has_conditional_logic = steps.any? { |s| s[:type] == 'conditional' }
    @has_loops = steps.any? { |s| s[:type] == 'loop' }
    @estimated_duration = estimate_workflow_duration(steps)
    
    Rails.logger.info "Workflow analysis: parallel=#{@has_parallel_opportunities}, " \
                     "conditional=#{@has_conditional_logic}, loops=#{@has_loops}, " \
                     "estimated_duration=#{@estimated_duration}s"
  end
  
  def determine_execution_mode(workflow_spec)
    return :sequential unless @has_parallel_opportunities
    
    # Check user preference
    if workflow_spec[:execution_mode]
      return workflow_spec[:execution_mode].to_sym
    end
    
    # Check resource constraints
    if @resource_manager.limited_resources?
      return :sequential
    end
    
    # Use intelligent mode for complex workflows
    :intelligent
  end
  
  def build_dependency_graph(steps)
    graph = {}
    
    steps.each do |step|
      graph[step[:id]] = {
        step: step,
        dependencies: step[:dependencies] || [],
        dependents: [],
        status: :pending
      }
    end
    
    # Build reverse dependencies
    graph.each do |step_id, node|
      node[:dependencies].each do |dep_id|
        if graph[dep_id]
          graph[dep_id][:dependents] << step_id
        end
      end
    end
    
    graph
  end
  
  def detect_parallel_opportunities(steps)
    # Group steps by their dependencies
    dependency_groups = steps.group_by { |s| (s[:dependencies] || []).sort }
    
    # If multiple steps have same dependencies, they can run in parallel
    dependency_groups.any? { |_, group| group.size > 1 }
  end
  
  def find_ready_steps
    @execution_graph.select do |step_id, node|
      node[:status] == :pending &&
      node[:dependencies].all? { |dep| @execution_graph[dep][:status] == :completed }
    end.map { |_, node| node[:step] }
  end
  
  def execute_step_batch(steps, inputs)
    futures = steps.map do |step|
      future = Concurrent::Future.execute(executor: @parallel_executor) do
        with_error_handling(step) do
          with_resource_tracking(step) do
            execute_single_step(step, inputs)
          end
        end
      end
      
      @step_futures[step[:id]] = future
      future
    end
    
    futures
  end
  
  def execute_single_step(step, inputs)
    # Create step-specific agent if needed
    agent = create_agent_for_step(step)
    
    # Execute through agent
    if agent
      agent.execute_step(step, inputs)
    else
      # Fallback to direct execution
      @workflow.execute_step(step, inputs)
    end
  end
  
  def create_agent_for_step(step)
    role = step[:agent_role] || :executor
    
    case role
    when :planner
      Agents::Specialized::PlannerAgent.new(task_session: @task_session)
    when :executor
      Agents::Specialized::ExecutorAgent.new(task_session: @task_session)
    when :analyst
      # Create analyst agent when implemented
      nil
    else
      # Default executor
      Agents::Specialized::ExecutorAgent.new(task_session: @task_session)
    end
  end
  
  def wait_for_completions
    completed = []
    
    @step_futures.each do |step_id, future|
      if future.fulfilled?
        completed << {
          step_id: step_id,
          result: future.value,
          status: :success
        }
      elsif future.rejected?
        completed << {
          step_id: step_id,
          error: future.reason,
          status: :failed
        }
      end
    end
    
    # Remove completed futures
    completed.each do |completion|
      @step_futures.delete(completion[:step_id])
    end
    
    completed
  end
  
  def mark_steps_completed(completed)
    completed.each do |completion|
      if node = @execution_graph[completion[:step_id]]
        node[:status] = completion[:status] == :success ? :completed : :failed
        node[:result] = completion[:result] || completion[:error]
        
        # Update shared context
        @execution_context.write(
          "step_#{completion[:step_id]}_result",
          node[:result],
          "workflow_engine"
        )
      end
    end
  end
  
  def has_pending_steps?
    @execution_graph.any? { |_, node| node[:status] == :pending }
  end
  
  def current_execution_context
    # Gather context from completed steps
    context = {}
    
    @execution_graph.each do |step_id, node|
      if node[:status] == :completed && node[:result]
        context[step_id] = node[:result]
      end
    end
    
    context
  end
  
  def collect_workflow_results
    results = {}
    failed_steps = []
    
    @execution_graph.each do |step_id, node|
      if node[:status] == :completed
        results[step_id] = node[:result]
      elsif node[:status] == :failed
        failed_steps << {
          step_id: step_id,
          error: node[:result]
        }
      end
    end
    
    if failed_steps.any?
      {
        status: 'partial_failure',
        message: "Workflow completed with #{failed_steps.size} failed steps",
        results: results,
        failed_steps: failed_steps
      }
    else
      {
        status: 'completed',
        message: 'Workflow completed successfully',
        results: results
      }
    end
  end
  
  def find_parallel_group(step)
    return nil unless step.config[:parallel_group]
    
    group_id = step.config[:parallel_group]
    @workflow.steps.select { |s| s.config[:parallel_group] == group_id }
  end
  
  def prefetch_next_steps(current_step)
    # Find likely next steps
    next_steps = @workflow.steps.select do |step|
      step.dependencies.include?(current_step.id)
    end
    
    # Prefetch data or prepare resources
    next_steps.each do |step|
      if step.type == 'tool_call' && should_prefetch?(step)
        Thread.new { prefetch_tool_data(step) }
      end
    end
  end
  
  def should_prefetch?(step)
    # Determine if prefetching would be beneficial
    tool_name = step.config[:tool]
    return false unless tool_name
    
    # Prefetch read-only operations
    %w[get_data list_connections get_schema].include?(tool_name)
  end
  
  def prefetch_tool_data(step)
    # Warm up caches or prepare data
    Rails.logger.debug "Prefetching data for step #{step.id}"
    # Implementation depends on specific tool
  end
  
  def execute_sequential_group(steps, inputs)
    results = []
    current_context = inputs.dup
    
    steps.each do |step|
      result = execute_single_step(step, current_context)
      results << result
      
      # Update context for next step
      if result[:success] && result[:result].is_a?(Hash)
        current_context.merge!(result[:result])
      end
    end
    
    {
      status: 'completed',
      results: results
    }
  end
  
  def calculate_required_resources(steps)
    resources = {
      cpu_threads: steps.size,
      memory_mb: 0,
      api_calls: 0
    }
    
    steps.each do |step|
      if step[:estimated_resources]
        resources[:memory_mb] += step[:estimated_resources][:memory] || 0
        resources[:api_calls] += step[:estimated_resources][:api_calls] || 0
      else
        # Default estimates
        resources[:memory_mb] += 100
        resources[:api_calls] += 1 if step[:type] == 'tool_call'
      end
    end
    
    resources
  end
  
  def calculate_timeout(steps)
    # Maximum time across all steps plus buffer
    max_duration = steps.map { |s| s[:estimated_duration] || 30 }.max
    max_duration * 1.5 # 50% buffer
  end
  
  def emit_progress_update(step, result)
    # Emit real-time progress via ActionCable or callbacks
    if @progress_callback
      @progress_callback.call({
        step_id: step.id,
        status: result[:status] || 'completed',
        progress: calculate_overall_progress
      })
    end
  end
  
  def calculate_overall_progress
    total_steps = @execution_graph.size
    completed_steps = @execution_graph.count { |_, node| node[:status] == :completed }
    
    (completed_steps.to_f / total_steps * 100).round
  end
  
  def handle_step_timeout(step)
    Rails.logger.error "Step #{step.id} timed out"
    
    @task_session.add_event('step_timeout', {
      step_id: step.id,
      timeout_duration: calculate_timeout([step])
    })
    
    # Mark as failed in graph
    if node = @execution_graph[step.id]
      node[:status] = :failed
      node[:result] = { error: 'Step execution timed out' }
    end
  end
  
  def handle_step_error(step, error)
    Rails.logger.error "Step #{step.id} failed: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
    
    @task_session.add_event('step_error', {
      step_id: step.id,
      error: error.message,
      error_class: error.class.name
    })
  end
  
  def evaluate_condition(condition, inputs)
    case condition[:type]
    when 'expression'
      evaluate_expression(condition[:expression], inputs)
    when 'comparison'
      evaluate_comparison(condition, inputs)
    when 'script'
      evaluate_script(condition[:script], inputs)
    else
      true # Default to true
    end
  end
  
  def evaluate_expression(expression, context)
    # Simple expression evaluator
    # In production, use a safe expression language
    begin
      # This is simplified - use proper sandboxing in production
      eval(expression, binding)
    rescue => e
      Rails.logger.error "Failed to evaluate expression: #{e.message}"
      false
    end
  end
  
  def evaluate_comparison(comparison, context)
    left = resolve_value(comparison[:left], context)
    right = resolve_value(comparison[:right], context)
    operator = comparison[:operator]
    
    case operator
    when '==' then left == right
    when '!=' then left != right
    when '>' then left > right
    when '<' then left < right
    when '>=' then left >= right
    when '<=' then left <= right
    when 'contains' then left.to_s.include?(right.to_s)
    when 'matches' then left.to_s.match?(Regexp.new(right.to_s))
    else
      false
    end
  end
  
  def evaluate_script(script, context)
    # Execute script in sandbox
    sandbox = Agents::Platform::Sandbox.new(
      name: "condition_#{SecureRandom.hex(4)}",
      permissions: [:read_context],
      resource_limits: { cpu_time: 1.second, memory: '64MB' }
    )
    
    result = sandbox.execute do |env|
      env.context = context
      env.eval(script)
    end
    
    result[:success] && result[:result]
  end
  
  def resolve_value(value, context)
    return value unless value.is_a?(String)
    
    # Handle variable references ${var_name}
    value.gsub(/\$\{([^}]+)\}/) do |match|
      var_path = $1.split('.')
      
      current = context
      var_path.each do |part|
        current = current[part] || current[part.to_sym] if current.is_a?(Hash)
      end
      
      current || match
    end
  end
  
  def execute_branch(branch_steps, inputs)
    return { status: 'skipped' } unless branch_steps
    
    # Execute branch steps
    branch_workflow = Workflow.new({
      steps: branch_steps,
      type: 'branch'
    })
    
    branch_engine = self.class.new(@task_session)
    branch_engine.instance_variable_set(:@workflow, branch_workflow)
    
    branch_engine.execute_next_step(inputs)
  end
  
  def resolve_items(items_spec, context)
    case items_spec
    when Array
      items_spec
    when String
      # Resolve from context
      resolve_value(items_spec, context) || []
    when Hash
      # Execute to get items
      if items_spec[:tool]
        result = execute_single_step({
          type: 'tool_call',
          config: { tool: items_spec[:tool], tool_args: items_spec[:args] }
        }, context)
        
        result[:result] || []
      else
        []
      end
    else
      []
    end
  end
  
  def execute_parallel_loop(step, items, inputs)
    Rails.logger.info "Executing parallel loop over #{items.size} items"
    
    # Limit parallelism for large collections
    batch_size = [items.size, 10].min
    results = []
    
    items.each_slice(batch_size) do |batch|
      batch_futures = batch.map do |item|
        Concurrent::Future.execute(executor: @parallel_executor) do
          execute_loop_iteration(step, item, inputs)
        end
      end
      
      # Wait for batch to complete
      batch_results = batch_futures.map(&:value)
      results.concat(batch_results)
    end
    
    {
      status: 'completed',
      results: results
    }
  end
  
  def execute_sequential_loop(step, items, inputs)
    results = []
    
    items.each_with_index do |item, index|
      result = execute_loop_iteration(step, item, inputs.merge(index: index))
      results << result
      
      # Check for early exit
      if step.config[:loop][:break_on] && should_break_loop?(result, step.config[:loop][:break_on])
        break
      end
    end
    
    {
      status: 'completed',
      results: results
    }
  end
  
  def execute_loop_iteration(step, item, inputs)
    iteration_context = inputs.merge(
      item: item,
      loop_item: item
    )
    
    # Execute loop body
    body_steps = step.config[:loop][:body] || []
    
    if body_steps.any?
      body_workflow = Workflow.new({
        steps: body_steps,
        type: 'loop_body'
      })
      
      body_engine = self.class.new(@task_session)
      body_engine.instance_variable_set(:@workflow, body_workflow)
      
      body_engine.execute_next_step(iteration_context)
    else
      { status: 'skipped', message: 'Empty loop body' }
    end
  end
  
  def should_break_loop?(result, break_condition)
    case break_condition[:type]
    when 'on_error'
      !result[:success]
    when 'on_condition'
      evaluate_condition(break_condition[:condition], result)
    else
      false
    end
  end
  
  def with_error_handling(step)
    yield
  rescue => e
    if handler = step[:error_handler]
      execute_error_handler(handler, step, e)
    else
      raise
    end
  end
  
  def with_resource_tracking(step)
    start_time = Time.current
    start_memory = current_memory_usage
    
    result = yield
    
    # Track resource usage
    duration = Time.current - start_time
    memory_delta = current_memory_usage - start_memory
    
    track_step_resources(step, {
      duration: duration,
      memory_mb: memory_delta / 1024.0 / 1024.0
    })
    
    result
  end
  
  def current_memory_usage
    # Simple memory tracking - can be enhanced
    `ps -o rss= -p #{Process.pid}`.to_i * 1024
  end
  
  def track_step_resources(step, usage)
    @task_session.add_event('step_resources', {
      step_id: step[:id],
      duration_seconds: usage[:duration],
      memory_mb: usage[:memory_mb]
    })
  end
  
  def execute_error_handler(handler, step, error)
    case handler[:type]
    when 'retry'
      retry_step(step, handler[:max_retries] || 3)
    when 'fallback'
      execute_fallback(handler[:fallback], step)
    when 'ignore'
      { status: 'ignored', error: error.message }
    else
      raise error
    end
  end
  
  def retry_step(step, max_retries)
    retries = 0
    
    begin
      retries += 1
      execute_single_step(step, current_execution_context)
    rescue => e
      if retries < max_retries
        sleep(2 ** retries) # Exponential backoff
        retry
      else
        raise
      end
    end
  end
  
  def execute_fallback(fallback_spec, original_step)
    fallback_step = original_step.merge(fallback_spec)
    execute_single_step(fallback_step, current_execution_context)
  end
  
  def determine_thread_pool_size
    # Determine optimal thread pool size
    cpu_count = Concurrent.processor_count
    
    # Consider available memory
    available_memory = begin
      if RUBY_PLATFORM =~ /darwin/
        # macOS (for local development) - just use a reasonable default
        4000 # 4GB assumed for local dev
      else
        # Linux (production) - use free command
        `free -m | awk 'NR==2{print $7}'`.to_i
      end
    rescue => e
      Rails.logger.warn "Could not determine available memory: #{e.message}, using default"
      1000 # 1GB fallback
    end
    
    memory_per_thread = 200 # MB
    memory_limited_threads = [available_memory / memory_per_thread, 1].max
    
    # Use smaller of CPU or memory limit, with a reasonable maximum
    [cpu_count * 2, memory_limited_threads, 10].min.tap do |size|
      Rails.logger.info "WorkflowEngineV2: Thread pool size set to #{size} (CPUs: #{cpu_count}, Available Memory: #{available_memory}MB)"
    end
  end
  
  def estimate_workflow_duration(steps)
    # Analyze critical path through workflow
    return 0 if steps.empty?
    
    # Build duration map
    durations = {}
    steps.each do |step|
      durations[step[:id]] = step[:estimated_duration] || 30
    end
    
    # Find critical path
    critical_path_duration = calculate_critical_path(steps, durations)
    
    # Adjust for parallelism
    if @has_parallel_opportunities
      critical_path_duration * 0.7 # Assume 30% speedup
    else
      critical_path_duration
    end
  end
  
  def calculate_critical_path(steps, durations)
    # Simple critical path calculation
    # In production, use proper graph algorithms
    
    # Create adjacency list
    graph = Hash.new { |h, k| h[k] = [] }
    steps.each do |step|
      (step[:dependencies] || []).each do |dep|
        graph[dep] << step[:id]
      end
    end
    
    # Find longest path
    memo = {}
    
    def longest_path_from(node, graph, durations, memo)
      return memo[node] if memo.key?(node)
      
      if graph[node].empty?
        memo[node] = durations[node] || 0
      else
        max_child = graph[node].map do |child|
          longest_path_from(child, graph, durations, memo)
        end.max || 0
        
        memo[node] = (durations[node] || 0) + max_child
      end
      
      memo[node]
    end
    
    # Find all start nodes (no dependencies)
    start_nodes = steps.select { |s| (s[:dependencies] || []).empty? }.map { |s| s[:id] }
    
    # Calculate longest path from each start node
    start_nodes.map do |node|
      longest_path_from(node, graph, durations, memo)
    end.max || 0
  end
  
  # Cleanup when done
  def shutdown
    @parallel_executor.shutdown
    @parallel_executor.wait_for_termination(10)
  rescue => e
    Rails.logger.error "Error shutting down workflow engine: #{e.message}"
  end
end
