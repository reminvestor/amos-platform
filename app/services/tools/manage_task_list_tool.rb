module Tools
  class ManageTaskListTool < BaseTool
    def self.metadata
      {
        name: 'manage_task_list',
        description: 'Create and manage a task list for the current session',
        category: 'task_management',
        input_schema: {
          type: 'object',
          properties: {
            action: {
              type: 'string',
              enum: ['create', 'update', 'complete', 'add', 'remove', 'reorder'],
              description: 'Action to perform on the task list'
            },
            tasks: {
              type: 'array',
              description: 'Array of tasks (for create/update actions)',
              items: {
                type: 'object',
                properties: {
                  id: { type: 'string' },
                  name: { type: 'string' },
                  status: { 
                    type: 'string',
                    enum: ['pending', 'in_progress', 'completed', 'blocked']
                  },
                  description: { type: 'string' },
                  dependencies: { type: 'array', items: { type: 'string' } }
                }
              }
            },
            task_id: {
              type: 'string',
              description: 'ID of specific task (for complete/remove actions)'
            },
            updates: {
              type: 'object',
              description: 'Updates to apply to a task'
            }
          },
          required: ['action']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      action = get_arg(args, :action)
      
      # Validate required args
      if error = validate_required_args(args, [:action])
        return error
      end
      
      begin
        # Get or initialize task list from session cache
        task_list = get_task_list
        
        # Perform action
        result = case action
        when 'create'
          create_task_list(args, task_list)
        when 'update'
          update_task_list(args, task_list)
        when 'complete'
          complete_task(args, task_list)
        when 'add'
          add_task(args, task_list)
        when 'remove'
          remove_task(args, task_list)
        when 'reorder'
          reorder_tasks(args, task_list)
        else
          error_response("Unknown action: #{action}")
        end
        
        # Save updated task list
        if result[:success]
          save_task_list(task_list)
          
          # Load task progress canvas
          load_task_canvas(task_list)
        end
        
        result
      rescue => e
        Rails.logger.error "Task management failed: #{e.message}"
        error_response("Task management failed: #{e.message}")
      end
    end
    
    private
    
    def get_task_list
      Rails.cache.fetch(task_list_cache_key, expires_in: 24.hours) do
        { tasks: [], created_at: Time.current }
      end
    end
    
    def save_task_list(task_list)
      Rails.cache.write(task_list_cache_key, task_list, expires_in: 24.hours)
    end
    
    def task_list_cache_key
      "task_list:#{context[:session_id] || 'default'}"
    end
    
    def create_task_list(args, task_list)
      tasks = get_arg(args, :tasks, [])
      
      # Initialize new task list
      task_list[:tasks] = tasks.map.with_index do |task, index|
        {
          'id' => task['id'] || task[:id] || "task_#{index + 1}",
          'name' => task['name'] || task[:name] || "Task #{index + 1}",
          'status' => task['status'] || task[:status] || 'pending',
          'description' => task['description'] || task[:description],
          'dependencies' => task['dependencies'] || task[:dependencies] || [],
          'created_at' => Time.current.iso8601,
          'order' => index
        }
      end
      
      task_list[:created_at] = Time.current
      task_list[:updated_at] = Time.current
      
      success_response(
        tasks: task_list[:tasks],
        total_tasks: task_list[:tasks].length,
        message: "Created task list with #{task_list[:tasks].length} tasks"
      )
    end
    
    def update_task_list(args, task_list)
      task_id = get_arg(args, :task_id)
      updates = get_arg(args, :updates, {})
      
      return error_response("Task ID required for update") if task_id.blank?
      
      task = task_list[:tasks].find { |t| t['id'] == task_id }
      return error_response("Task not found: #{task_id}") unless task
      
      # Apply updates
      updates.each do |key, value|
        task[key.to_s] = value if %w[name status description dependencies].include?(key.to_s)
      end
      
      task['updated_at'] = Time.current.iso8601
      task_list[:updated_at] = Time.current
      
      success_response(
        task: task,
        message: "Updated task: #{task['name']}"
      )
    end
    
    def complete_task(args, task_list)
      task_id = get_arg(args, :task_id)
      
      return error_response("Task ID required") if task_id.blank?
      
      task = task_list[:tasks].find { |t| t['id'] == task_id }
      return error_response("Task not found: #{task_id}") unless task
      
      # Mark as completed
      task['status'] = 'completed'
      task['completed_at'] = Time.current.iso8601
      task['updated_at'] = Time.current.iso8601
      
      # Check for dependent tasks to unblock
      unblocked_tasks = []
      task_list[:tasks].each do |other_task|
        if other_task['dependencies']&.include?(task_id) && other_task['status'] == 'blocked'
          # Check if all dependencies are completed
          all_deps_complete = other_task['dependencies'].all? do |dep_id|
            dep_task = task_list[:tasks].find { |t| t['id'] == dep_id }
            dep_task && dep_task['status'] == 'completed'
          end
          
          if all_deps_complete
            other_task['status'] = 'pending'
            unblocked_tasks << other_task['name']
          end
        end
      end
      
      message = "Completed task: #{task['name']}"
      message += " (unblocked: #{unblocked_tasks.join(', ')})" if unblocked_tasks.any?
      
      success_response(
        task: task,
        unblocked_tasks: unblocked_tasks,
        message: message
      )
    end
    
    def add_task(args, task_list)
      new_task = get_arg(args, :tasks, []).first || {}
      
      return error_response("Task data required") if new_task.empty?
      
      # Create new task
      task_id = new_task['id'] || new_task[:id] || "task_#{task_list[:tasks].length + 1}"
      
      task = {
        'id' => task_id,
        'name' => new_task['name'] || new_task[:name] || "New Task",
        'status' => new_task['status'] || new_task[:status] || 'pending',
        'description' => new_task['description'] || new_task[:description],
        'dependencies' => new_task['dependencies'] || new_task[:dependencies] || [],
        'created_at' => Time.current.iso8601,
        'order' => task_list[:tasks].length
      }
      
      task_list[:tasks] << task
      task_list[:updated_at] = Time.current
      
      success_response(
        task: task,
        total_tasks: task_list[:tasks].length,
        message: "Added task: #{task['name']}"
      )
    end
    
    def remove_task(args, task_list)
      task_id = get_arg(args, :task_id)
      
      return error_response("Task ID required") if task_id.blank?
      
      task = task_list[:tasks].find { |t| t['id'] == task_id }
      return error_response("Task not found: #{task_id}") unless task
      
      # Remove task
      task_list[:tasks].delete(task)
      
      # Remove from dependencies of other tasks
      task_list[:tasks].each do |other_task|
        other_task['dependencies']&.delete(task_id)
      end
      
      task_list[:updated_at] = Time.current
      
      success_response(
        removed_task: task['name'],
        total_tasks: task_list[:tasks].length,
        message: "Removed task: #{task['name']}"
      )
    end
    
    def reorder_tasks(args, task_list)
      tasks = get_arg(args, :tasks, [])
      
      # Update order based on provided array
      tasks.each_with_index do |task_ref, index|
        task_id = task_ref['id'] || task_ref[:id]
        task = task_list[:tasks].find { |t| t['id'] == task_id }
        task['order'] = index if task
      end
      
      # Sort tasks by order
      task_list[:tasks].sort_by! { |t| t['order'] || 999 }
      task_list[:updated_at] = Time.current
      
      success_response(
        tasks: task_list[:tasks],
        message: "Reordered tasks"
      )
    end
    
    def load_task_canvas(task_list)
      # Calculate task statistics
      total = task_list[:tasks].length
      completed = task_list[:tasks].count { |t| t['status'] == 'completed' }
      in_progress = task_list[:tasks].count { |t| t['status'] == 'in_progress' }
      pending = task_list[:tasks].count { |t| t['status'] == 'pending' }
      blocked = task_list[:tasks].count { |t| t['status'] == 'blocked' }
      
      @context[:canvas_suggestion] = 'task_progress'
      @context[:canvas_data] = {
        tasks: task_list[:tasks],
        stats: {
          total: total,
          completed: completed,
          in_progress: in_progress,
          pending: pending,
          blocked: blocked,
          completion_rate: total > 0 ? (completed.to_f / total * 100).round : 0
        },
        created_at: task_list[:created_at],
        updated_at: task_list[:updated_at]
      }
    end
  end
end
