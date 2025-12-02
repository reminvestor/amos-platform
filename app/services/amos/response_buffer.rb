# Intelligent response buffering and ordering for Amos
module Amos
  class ResponseBuffer
    def initialize
      @buffer = []
      @last_flush = Time.current
      @flush_interval = 0.5 # seconds
    end
    
    def add(content, priority: :normal, metadata: {})
      @buffer << {
        content: content,
        priority: priority_value(priority),
        metadata: metadata,
        timestamp: Time.current
      }
      
      # Sort by priority (higher = more urgent)
      @buffer.sort_by! { |item| -item[:priority] }
    end
    
    def flush(&block)
      return if @buffer.empty?
      
      # Group related responses
      grouped = group_responses(@buffer)
      
      # Process each group
      grouped.each do |group|
        if group.size == 1
          # Single response
          yield group.first
        else
          # Merge related responses
          merged = merge_responses(group)
          yield merged
        end
      end
      
      # Clear buffer
      @buffer.clear
      @last_flush = Time.current
    end
    
    def should_auto_flush?
      return false if @buffer.empty?
      
      # Auto-flush if:
      # 1. High priority message waiting
      # 2. Buffer getting full
      # 3. Time threshold reached
      
      has_high_priority = @buffer.any? { |item| item[:priority] >= 9 }
      buffer_full = @buffer.size >= 10
      time_elapsed = (Time.current - @last_flush) >= @flush_interval
      
      has_high_priority || buffer_full || time_elapsed
    end
    
    private
    
    def priority_value(priority)
      case priority
      when :immediate then 10
      when :high then 8
      when :normal then 5
      when :low then 3
      else 5
      end
    end
    
    def group_responses(responses)
      # Group responses that should be merged
      groups = []
      current_group = []
      
      responses.each do |response|
        if current_group.empty?
          current_group << response
        elsif should_group_together?(current_group.last, response)
          current_group << response
        else
          groups << current_group
          current_group = [response]
        end
      end
      
      groups << current_group unless current_group.empty?
      groups
    end
    
    def should_group_together?(resp1, resp2)
      # Group if:
      # 1. From same job/agent
      # 2. Within 2 seconds of each other
      # 3. Similar priority
      
      same_source = resp1.dig(:metadata, :job_id) == resp2.dig(:metadata, :job_id)
      time_close = (resp2[:timestamp] - resp1[:timestamp]).abs < 2
      priority_close = (resp1[:priority] - resp2[:priority]).abs <= 2
      
      same_source && time_close && priority_close
    end
    
    def merge_responses(group)
      # Intelligently merge related responses
      contents = group.map { |r| r[:content] }
      
      # If all are status updates, create a summary
      if contents.all? { |c| c.match?(/progress|status|update/i) }
        merged_content = "Progress Update:\n" + contents.join("\n")
      else
        # Otherwise join with appropriate spacing
        merged_content = contents.join("\n\n")
      end
      
      {
        content: merged_content,
        priority: group.map { |r| r[:priority] }.max,
        metadata: group.first[:metadata].merge(
          merged_count: group.size,
          merged_at: Time.current
        ),
        timestamp: Time.current
      }
    end
  end
end


