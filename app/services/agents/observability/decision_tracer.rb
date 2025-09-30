module Agents
  module Observability
    class DecisionTracer
      include Singleton
      
      def initialize
        @traces = Concurrent::Array.new
        @active_traces = Concurrent::Hash.new
        @subscribers = Concurrent::Array.new
        @trace_store = TraceStore.new
      end
      
      # Start tracing a decision
      def start_trace(agent_id, decision_type, context = {})
        trace_id = SecureRandom.uuid
        
        trace = {
          id: trace_id,
          agent_id: agent_id,
          decision_type: decision_type,
          context: context,
          started_at: Time.current,
          steps: [],
          reasoning: [],
          alternatives_considered: [],
          confidence_scores: {},
          resources_used: {},
          status: :in_progress
        }
        
        @active_traces[trace_id] = trace
        
        # Notify subscribers
        notify_subscribers(:trace_started, trace)
        
        trace_id
      end
      
      # Add a reasoning step
      def add_reasoning(trace_id, step_name, reasoning, evidence = {})
        return unless trace = @active_traces[trace_id]
        
        reasoning_step = {
          step: step_name,
          reasoning: reasoning,
          evidence: evidence,
          timestamp: Time.current
        }
        
        trace[:reasoning] << reasoning_step
        
        # Log for debugging
        Rails.logger.debug "Agent reasoning [#{trace[:agent_id]}]: #{step_name} - #{reasoning}"
      end
      
      # Record alternative considered
      def add_alternative(trace_id, alternative, score, reason_rejected = nil)
        return unless trace = @active_traces[trace_id]
        
        trace[:alternatives_considered] << {
          alternative: alternative,
          score: score,
          reason_rejected: reason_rejected,
          timestamp: Time.current
        }
      end
      
      # Add confidence score
      def add_confidence(trace_id, metric, score, explanation = nil)
        return unless trace = @active_traces[trace_id]
        
        trace[:confidence_scores][metric] = {
          score: score,
          explanation: explanation,
          timestamp: Time.current
        }
      end
      
      # Record resource usage
      def record_resource_use(trace_id, resource_type, amount, details = {})
        return unless trace = @active_traces[trace_id]
        
        trace[:resources_used][resource_type] ||= []
        trace[:resources_used][resource_type] << {
          amount: amount,
          details: details,
          timestamp: Time.current
        }
      end
      
      # Complete a trace
      def complete_trace(trace_id, outcome, final_decision = nil)
        return unless trace = @active_traces.delete(trace_id)
        
        trace[:completed_at] = Time.current
        trace[:duration] = trace[:completed_at] - trace[:started_at]
        trace[:outcome] = outcome
        trace[:final_decision] = final_decision
        trace[:status] = :completed
        
        # Calculate decision quality metrics
        trace[:quality_metrics] = calculate_quality_metrics(trace)
        
        # Store trace
        @trace_store.store(trace)
        @traces << trace
        
        # Notify subscribers
        notify_subscribers(:trace_completed, trace)
        
        # Emit metrics
        emit_trace_metrics(trace)
        
        trace
      end
      
      # Get active traces
      def active_traces(agent_id = nil)
        if agent_id
          @active_traces.values.select { |t| t[:agent_id] == agent_id }
        else
          @active_traces.values
        end
      end
      
      # Get trace history
      def trace_history(filters = {})
        @trace_store.query(filters)
      end
      
      # Subscribe to trace events
      def subscribe(&block)
        @subscribers << block
      end
      
      # Generate trace report
      def generate_report(agent_id, time_range = 24.hours)
        traces = @trace_store.query(
          agent_id: agent_id,
          time_range: time_range
        )
        
        DecisionReport.new(traces).generate
      end
      
      private
      
      def calculate_quality_metrics(trace)
        {
          decision_time: trace[:duration],
          reasoning_depth: trace[:reasoning].size,
          alternatives_explored: trace[:alternatives_considered].size,
          average_confidence: calculate_average_confidence(trace[:confidence_scores]),
          resource_efficiency: calculate_resource_efficiency(trace[:resources_used]),
          outcome_success: trace[:outcome] == :success
        }
      end
      
      def calculate_average_confidence(confidence_scores)
        return 0 if confidence_scores.empty?
        
        scores = confidence_scores.values.map { |c| c[:score] }
        scores.sum.to_f / scores.size
      end
      
      def calculate_resource_efficiency(resources_used)
        # Simple efficiency calculation
        # Could be enhanced with cost modeling
        total_resources = resources_used.values.flatten.sum { |r| r[:amount] }
        
        case total_resources
        when 0..10 then 1.0
        when 11..50 then 0.8
        when 51..100 then 0.6
        else 0.4
        end
      end
      
      def notify_subscribers(event, trace)
        @subscribers.each do |subscriber|
          begin
            subscriber.call(event, trace)
          rescue => e
            Rails.logger.error "Trace subscriber error: #{e.message}"
          end
        end
      end
      
      def emit_trace_metrics(trace)
        ActiveSupport::Notifications.instrument('agent.decision_completed', {
          agent_id: trace[:agent_id],
          decision_type: trace[:decision_type],
          duration: trace[:duration],
          outcome: trace[:outcome],
          quality_metrics: trace[:quality_metrics]
        })
      end
    end
    
    # Trace storage
    class TraceStore
      def initialize
        @redis = $redis || Redis.new
        @index_ttl = 7.days
        @trace_ttl = 30.days
      end
      
      def store(trace)
        key = "trace:#{trace[:id]}"
        
        # Store trace data
        @redis.setex(key, @trace_ttl, trace.to_json)
        
        # Update indices
        index_by_agent(trace)
        index_by_time(trace)
        index_by_type(trace)
      end
      
      def query(filters = {})
        keys = find_trace_keys(filters)
        
        traces = @redis.mget(keys).compact.map do |json|
          JSON.parse(json, symbolize_names: true)
        end
        
        # Apply additional filters
        traces = filter_traces(traces, filters)
        
        # Sort by timestamp
        traces.sort_by { |t| t[:started_at] }.reverse
      end
      
      private
      
      def index_by_agent(trace)
        key = "trace_index:agent:#{trace[:agent_id]}:#{Date.current}"
        @redis.zadd(key, trace[:started_at].to_f, trace[:id])
        @redis.expire(key, @index_ttl)
      end
      
      def index_by_time(trace)
        key = "trace_index:time:#{trace[:started_at].strftime('%Y%m%d%H')}"
        @redis.zadd(key, trace[:started_at].to_f, trace[:id])
        @redis.expire(key, @index_ttl)
      end
      
      def index_by_type(trace)
        key = "trace_index:type:#{trace[:decision_type]}:#{Date.current}"
        @redis.zadd(key, trace[:started_at].to_f, trace[:id])
        @redis.expire(key, @index_ttl)
      end
      
      def find_trace_keys(filters)
        if filters[:agent_id]
          find_by_agent(filters[:agent_id], filters[:time_range])
        elsif filters[:decision_type]
          find_by_type(filters[:decision_type], filters[:time_range])
        else
          find_by_time(filters[:time_range])
        end
      end
      
      def find_by_agent(agent_id, time_range)
        keys = []
        
        (time_range || 24.hours).to_i.times do |hours_ago|
          date = (Time.current - hours_ago.hours).to_date
          key = "trace_index:agent:#{agent_id}:#{date}"
          
          trace_ids = @redis.zrange(key, 0, -1)
          keys.concat(trace_ids.map { |id| "trace:#{id}" })
        end
        
        keys.uniq
      end
      
      def find_by_time(time_range)
        keys = []
        hours = (time_range || 24.hours) / 1.hour
        
        hours.to_i.times do |hour_offset|
          time = Time.current - hour_offset.hours
          key = "trace_index:time:#{time.strftime('%Y%m%d%H')}"
          
          trace_ids = @redis.zrange(key, 0, -1)
          keys.concat(trace_ids.map { |id| "trace:#{id}" })
        end
        
        keys.uniq
      end
      
      def filter_traces(traces, filters)
        if filters[:outcome]
          traces = traces.select { |t| t[:outcome] == filters[:outcome] }
        end
        
        if filters[:min_confidence]
          traces = traces.select do |t|
            avg = t[:quality_metrics][:average_confidence]
            avg >= filters[:min_confidence]
          end
        end
        
        traces
      end
    end
    
    # Decision quality report generator
    class DecisionReport
      def initialize(traces)
        @traces = traces
      end
      
      def generate
        {
          summary: generate_summary,
          decision_types: analyze_by_type,
          quality_trends: analyze_quality_trends,
          resource_usage: analyze_resource_usage,
          improvement_recommendations: generate_recommendations
        }
      end
      
      private
      
      def generate_summary
        successful = @traces.count { |t| t[:outcome] == :success }
        
        {
          total_decisions: @traces.size,
          success_rate: @traces.empty? ? 0 : (successful.to_f / @traces.size),
          average_decision_time: average_metric(:duration),
          average_confidence: average_metric(:average_confidence),
          total_resources_used: sum_resources
        }
      end
      
      def analyze_by_type
        @traces.group_by { |t| t[:decision_type] }.transform_values do |traces|
          {
            count: traces.size,
            success_rate: success_rate(traces),
            avg_duration: average_duration(traces),
            avg_confidence: average_confidence(traces)
          }
        end
      end
      
      def analyze_quality_trends
        # Group by hour
        hourly_groups = @traces.group_by do |t|
          Time.parse(t[:started_at].to_s).beginning_of_hour
        end
        
        hourly_groups.transform_values do |traces|
          {
            decision_count: traces.size,
            success_rate: success_rate(traces),
            avg_quality: average_quality_score(traces)
          }
        end
      end
      
      def analyze_resource_usage
        resources = Hash.new(0)
        
        @traces.each do |trace|
          trace[:resources_used].each do |type, uses|
            resources[type] += uses.sum { |u| u[:amount] }
          end
        end
        
        resources
      end
      
      def generate_recommendations
        recommendations = []
        
        # Check success rate
        if success_rate(@traces) < 0.8
          recommendations << {
            type: :low_success_rate,
            message: "Success rate below 80%. Consider reviewing decision logic.",
            severity: :high
          }
        end
        
        # Check confidence
        avg_confidence = average_metric(:average_confidence)
        if avg_confidence < 0.7
          recommendations << {
            type: :low_confidence,
            message: "Average confidence below 70%. Consider gathering more data.",
            severity: :medium
          }
        end
        
        # Check alternatives explored
        avg_alternatives = average_metric(:alternatives_explored)
        if avg_alternatives < 2
          recommendations << {
            type: :limited_exploration,
            message: "Few alternatives considered. Encourage broader exploration.",
            severity: :low
          }
        end
        
        recommendations
      end
      
      def average_metric(metric)
        return 0 if @traces.empty?
        
        values = @traces.map do |t|
          if metric == :duration
            t[metric]
          else
            t[:quality_metrics][metric]
          end
        end.compact
        
        values.sum.to_f / values.size
      end
      
      def success_rate(traces)
        return 0 if traces.empty?
        
        successful = traces.count { |t| t[:outcome] == :success }
        successful.to_f / traces.size
      end
      
      def average_duration(traces)
        return 0 if traces.empty?
        
        total = traces.sum { |t| t[:duration] || 0 }
        total / traces.size
      end
      
      def average_confidence(traces)
        return 0 if traces.empty?
        
        total = traces.sum { |t| t[:quality_metrics][:average_confidence] || 0 }
        total / traces.size
      end
      
      def average_quality_score(traces)
        return 0 if traces.empty?
        
        # Composite quality score
        traces.sum do |t|
          metrics = t[:quality_metrics]
          
          score = 0
          score += 0.3 if metrics[:outcome_success]
          score += 0.3 * (metrics[:average_confidence] || 0)
          score += 0.2 * (metrics[:resource_efficiency] || 0)
          score += 0.2 * [metrics[:alternatives_explored] / 5.0, 1.0].min
          
          score
        end / traces.size
      end
      
      def sum_resources
        total = Hash.new(0)
        
        @traces.each do |trace|
          trace[:resources_used].each do |type, uses|
            total[type] += uses.sum { |u| u[:amount] }
          end
        end
        
        total
      end
    end
  end
end
