module Tools
  class GetWorkflowContextTool < BaseTool
    def self.metadata
      {
        name: "get_workflow_context",
        description: "Retrieve stored context data from the current workflow (files, user inputs, etc)",
        category: "workflow",
        input_schema: {
          type: "object",
          properties: {
            key: {
              type: "string",
              description: "Specific context key to retrieve (optional). If not provided, returns all context."
            },
            data_type: {
              type: "string",
              enum: [ "file_reference", "user_input", "extracted_data", "all" ],
              description: "Filter by data type (optional)"
            }
          }
        }
      }
    end

    def execute(args)
      key = args["key"]
      data_type = args["data_type"]

      # Get current workflow execution from context
      task_session = context[:task_session]
      workflow_execution = task_session&.workflow_execution

      unless workflow_execution
        return {
          success: false,
          error: "No active workflow found"
        }
      end

      begin
        if key
          # Get specific context by key
          context_item = workflow_execution.workflow_contexts.find_by(key: key)

          if context_item
            format_context_item(context_item)
          else
            {
              success: false,
              error: "No context found with key: #{key}"
            }
          end
        else
          # Get all context, optionally filtered by type
          contexts = workflow_execution.workflow_contexts
          contexts = contexts.where(data_type: data_type) if data_type && data_type != "all"

          {
            success: true,
            contexts: contexts.map { |item| format_context_item(item) },
            total_count: contexts.count,
            summary: build_summary(contexts)
          }
        end
      rescue => e
        {
          success: false,
          error: "Failed to retrieve workflow context: #{e.message}"
        }
      end
    end

    private

    def format_context_item(item)
      formatted = {
        key: item.key,
        data_type: item.data_type,
        value: item.value,
        created_at: item.created_at
      }

      # Add file-specific formatting
      if item.file?
        formatted[:file_info] = item.as_file_info
      end

      formatted
    end

    def build_summary(contexts)
      summary = {
        total_items: contexts.count,
        by_type: contexts.group(:data_type).count
      }

      # Add file summary
      file_contexts = contexts.files
      if file_contexts.any?
        summary[:files] = file_contexts.map do |fc|
          info = fc.as_file_info
          {
            key: fc.key,
            filename: info[:filename],
            type: info[:content_type],
            size: info[:size]
          }
        end
      end

      summary
    end
  end
end
