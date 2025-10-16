module Agents
  module Learning
    class LearningEngine
      attr_reader :entity, :feedback_store, :pattern_analyzer, :optimization_service

      def initialize(entity = nil)
        @entity = entity
        @feedback_store = FeedbackStore.new
        @pattern_analyzer = PatternAnalyzer.new
        @optimization_service = OptimizationService.new
        @model_trainer = ModelTrainer.new
        @knowledge_base = KnowledgeBase.new
      end

      # Learn from workflow execution
      def learn_from_execution(workflow, execution_result)
        # Capture execution metrics
        metrics = extract_execution_metrics(workflow, execution_result)

        # Store experience
        experience = {
          workflow_type: workflow.type,
          workflow_id: workflow.id,
          steps: workflow.steps.map(&:to_h),
          execution_time: metrics[:total_duration],
          success: execution_result[:status] == "completed",
          metrics: metrics,
          timestamp: Time.current
        }

        @feedback_store.store_experience(experience)

        # Analyze patterns
        patterns = @pattern_analyzer.analyze_workflow_patterns(workflow.type)

        # Generate insights
        insights = generate_insights(experience, patterns)

        # Update knowledge base
        @knowledge_base.update_from_insights(insights)

        # Trigger optimization if needed
        if should_optimize?(patterns)
          optimize_workflow_template(workflow.type, patterns)
        end

        insights
      end

      # Learn from user feedback
      def learn_from_feedback(task_session, feedback)
        # Store feedback
        @feedback_store.store_user_feedback({
          task_session_id: task_session.id,
          feedback: feedback,
          workflow_type: task_session.workflow_type,
          timestamp: Time.current
        })

        # Analyze sentiment and extract insights
        sentiment = analyze_feedback_sentiment(feedback)
        insights = extract_feedback_insights(feedback)

        # Update agent performance metrics
        if feedback[:agent_ratings]
          update_agent_performance(feedback[:agent_ratings])
        end

        # Identify improvement areas
        improvements = identify_improvements(task_session, feedback, sentiment)

        # Schedule retraining if needed
        if significant_feedback?(sentiment, improvements)
          schedule_retraining(task_session.workflow_type)
        end

        {
          sentiment: sentiment,
          insights: insights,
          improvements: improvements
        }
      end

      # Get recommendations for workflow improvement
      def get_optimization_recommendations(workflow_type)
        # Analyze historical data
        patterns = @pattern_analyzer.analyze_workflow_patterns(workflow_type)

        # Get similar successful workflows
        similar_workflows = find_similar_successful_workflows(workflow_type)

        # Generate recommendations
        recommendations = []

        # Step order optimization
        if step_order_rec = optimize_step_order(patterns)
          recommendations << step_order_rec
        end

        # Parallel execution opportunities
        if parallel_rec = identify_parallelization_opportunities(patterns)
          recommendations << parallel_rec
        end

        # Tool selection optimization
        if tool_rec = optimize_tool_selection(patterns)
          recommendations << tool_rec
        end

        # Resource allocation
        if resource_rec = optimize_resource_allocation(patterns)
          recommendations << resource_rec
        end

        # Agent assignment
        if agent_rec = optimize_agent_assignment(patterns)
          recommendations << agent_rec
        end

        recommendations
      end

      # Train custom model for specific task
      def train_task_model(task_type, training_data = nil)
        # Gather training data if not provided
        training_data ||= gather_training_data(task_type)

        # Prepare dataset
        dataset = prepare_training_dataset(training_data)

        # Configure training
        config = {
          model_type: determine_model_type(task_type),
          hyperparameters: optimize_hyperparameters(task_type, dataset),
          validation_split: 0.2
        }

        # Train model
        model = @model_trainer.train(dataset, config)

        # Evaluate performance
        evaluation = evaluate_model(model, dataset)

        # Deploy if performance is good
        if evaluation[:accuracy] > 0.85
          deploy_model(task_type, model)
        end

        {
          model_id: model.id,
          evaluation: evaluation,
          deployed: evaluation[:accuracy] > 0.85
        }
      end

      # Get performance analytics
      def get_performance_analytics(time_range = 7.days)
        end_time = Time.current
        start_time = end_time - time_range

        # Gather metrics
        workflow_metrics = analyze_workflow_performance(start_time, end_time)
        agent_metrics = analyze_agent_performance(start_time, end_time)
        tool_metrics = analyze_tool_performance(start_time, end_time)
        cost_metrics = analyze_cost_performance(start_time, end_time)

        # Calculate trends
        trends = calculate_performance_trends(workflow_metrics, agent_metrics)

        # Generate insights
        insights = generate_performance_insights(
          workflow_metrics,
          agent_metrics,
          tool_metrics,
          cost_metrics,
          trends
        )

        {
          time_range: {
            start: start_time,
            end: end_time
          },
          workflows: workflow_metrics,
          agents: agent_metrics,
          tools: tool_metrics,
          costs: cost_metrics,
          trends: trends,
          insights: insights
        }
      end

      # Predict workflow success
      def predict_success(workflow_spec, context = {})
        features = extract_workflow_features(workflow_spec, context)

        # Get historical success patterns
        patterns = @pattern_analyzer.get_success_patterns(workflow_spec[:type])

        # Calculate similarity to successful workflows
        similarity_scores = calculate_pattern_similarity(features, patterns)

        # Predict success probability
        success_probability = predict_from_patterns(similarity_scores)

        # Identify risk factors
        risk_factors = identify_risk_factors(workflow_spec, patterns)

        # Generate recommendations
        recommendations = generate_success_recommendations(
          workflow_spec,
          risk_factors,
          success_probability
        )

        {
          success_probability: success_probability,
          confidence: calculate_prediction_confidence(similarity_scores),
          risk_factors: risk_factors,
          recommendations: recommendations
        }
      end

      private

      def extract_execution_metrics(workflow, result)
        {
          total_duration: result[:duration] || 0,
          step_durations: extract_step_durations(result),
          resource_usage: result[:resource_usage] || {},
          api_calls: count_api_calls(result),
          tokens_used: result[:tokens_used] || 0,
          errors: result[:errors] || [],
          retries: result[:retries] || 0
        }
      end

      def generate_insights(experience, patterns)
        insights = []

        # Performance insights
        if experience[:execution_time] > patterns[:avg_duration] * 1.5
          insights << {
            type: :performance,
            severity: :warning,
            message: "Workflow took #{(experience[:execution_time] / patterns[:avg_duration]).round(1)}x longer than average",
            suggestion: "Consider optimizing slow steps or parallelizing operations"
          }
        end

        # Success rate insights
        if !experience[:success] && patterns[:success_rate] > 0.9
          insights << {
            type: :reliability,
            severity: :error,
            message: "Workflow failed despite high historical success rate",
            suggestion: "Investigate unique factors in this execution"
          }
        end

        # Resource usage insights
        if experience[:metrics][:tokens_used] > patterns[:avg_tokens] * 2
          insights << {
            type: :cost,
            severity: :warning,
            message: "Token usage significantly higher than average",
            suggestion: "Review prompts and responses for efficiency"
          }
        end

        insights
      end

      def should_optimize?(patterns)
        # Optimize if performance is degrading
        return true if patterns[:performance_trend] == :degrading

        # Optimize if success rate is low
        return true if patterns[:success_rate] < 0.8

        # Optimize if we have enough data
        patterns[:execution_count] >= 100 &&
        patterns[:last_optimization].nil? ||
        patterns[:last_optimization] < 7.days.ago
      end

      def optimize_workflow_template(workflow_type, patterns)
        @optimization_service.optimize_workflow(workflow_type, patterns)
      end

      def analyze_feedback_sentiment(feedback)
        text = feedback[:text] || feedback[:message] || ""
        rating = feedback[:rating]

        # Simple sentiment analysis
        positive_words = %w[great excellent perfect amazing good helpful fantastic awesome]
        negative_words = %w[bad poor terrible awful horrible wrong failed broken]

        positive_count = positive_words.count { |word| text.downcase.include?(word) }
        negative_count = negative_words.count { |word| text.downcase.include?(word) }

        # Combine with rating if available
        if rating
          sentiment_score = (rating / 5.0) * 0.7 + (positive_count - negative_count) * 0.3
        else
          sentiment_score = (positive_count - negative_count).to_f / (positive_count + negative_count + 1)
        end

        {
          score: sentiment_score,
          label: sentiment_label(sentiment_score),
          confidence: calculate_sentiment_confidence(text, rating)
        }
      end

      def sentiment_label(score)
        case score
        when 0.6..1.0 then :positive
        when -0.6...0.6 then :neutral
        else :negative
        end
      end

      def extract_feedback_insights(feedback)
        insights = []
        text = feedback[:text] || ""

        # Extract mentioned issues
        if text =~ /slow|long|forever|stuck/i
          insights << { category: :performance, issue: :slow_execution }
        end

        if text =~ /wrong|incorrect|mistake|error/i
          insights << { category: :accuracy, issue: :incorrect_results }
        end

        if text =~ /confus|unclear|understand/i
          insights << { category: :usability, issue: :unclear_interface }
        end

        if text =~ /miss|lack|need|want|should/i
          insights << { category: :features, issue: :missing_functionality }
        end

        insights
      end

      def update_agent_performance(agent_ratings)
        agent_ratings.each do |agent_id, rating|
          key = "agent_performance:#{agent_id}"

          # Update rolling average
          current = ($redis || Redis.new).hgetall(key)
          total_ratings = current["count"].to_i
          avg_rating = current["average"].to_f

          new_avg = (avg_rating * total_ratings + rating) / (total_ratings + 1)

          ($redis || Redis.new).hmset(key,
            "average", new_avg,
            "count", total_ratings + 1,
            "last_updated", Time.current.to_i
          )
        end
      end

      def identify_improvements(task_session, feedback, sentiment)
        improvements = []

        # Based on sentiment
        if sentiment[:label] == :negative
          improvements << {
            area: :user_satisfaction,
            priority: :high,
            suggestion: "Review and improve workflow quality"
          }
        end

        # Based on specific feedback
        if feedback[:issues]
          feedback[:issues].each do |issue|
            improvements << map_issue_to_improvement(issue)
          end
        end

        # Based on metrics
        if task_session.duration > expected_duration(task_session.workflow_type) * 2
          improvements << {
            area: :performance,
            priority: :medium,
            suggestion: "Optimize workflow execution time"
          }
        end

        improvements
      end

      def significant_feedback?(sentiment, improvements)
        sentiment[:label] == :negative ||
        improvements.any? { |i| i[:priority] == :high } ||
        improvements.size >= 3
      end

      def schedule_retraining(workflow_type)
        RetrainingJob.perform_later(workflow_type)
      end

      def find_similar_successful_workflows(workflow_type)
        @feedback_store.find_workflows(
          type: workflow_type,
          success: true,
          limit: 100
        ).select { |w| w[:metrics][:satisfaction_score] > 4.0 }
      end

      def optimize_step_order(patterns)
        current_order = patterns[:common_step_order]
        optimal_order = calculate_optimal_step_order(patterns)

        if current_order != optimal_order
          {
            type: :step_order,
            current: current_order,
            recommended: optimal_order,
            expected_improvement: "15-20% faster execution",
            confidence: 0.85
          }
        end
      end

      def identify_parallelization_opportunities(patterns)
        independent_steps = find_independent_steps(patterns)

        if independent_steps.size >= 2
          {
            type: :parallelization,
            steps: independent_steps,
            expected_improvement: "#{independent_steps.size * 20}% faster execution",
            confidence: 0.9
          }
        end
      end

      def optimize_tool_selection(patterns)
        tool_performance = patterns[:tool_performance]
        recommendations = []

        tool_performance.each do |tool, metrics|
          if metrics[:success_rate] < 0.7
            alternative = find_alternative_tool(tool, patterns)
            if alternative
              recommendations << {
                current_tool: tool,
                recommended_tool: alternative[:tool],
                reason: alternative[:reason],
                expected_improvement: "#{alternative[:improvement]}% higher success rate"
              }
            end
          end
        end

        if recommendations.any?
          {
            type: :tool_optimization,
            recommendations: recommendations,
            confidence: 0.8
          }
        end
      end

      def optimize_resource_allocation(patterns)
        resource_usage = patterns[:resource_usage]

        # Analyze resource waste
        waste_analysis = analyze_resource_waste(resource_usage)

        if waste_analysis[:waste_percentage] > 20
          {
            type: :resource_optimization,
            current_allocation: resource_usage[:average],
            recommended_allocation: calculate_optimal_resources(patterns),
            expected_savings: "#{waste_analysis[:waste_percentage]}% cost reduction",
            confidence: 0.75
          }
        end
      end

      def optimize_agent_assignment(patterns)
        agent_performance = patterns[:agent_performance]
        recommendations = []

        patterns[:steps].each do |step|
          current_agent = step[:assigned_agent]
          optimal_agent = find_optimal_agent(step, agent_performance)

          if optimal_agent != current_agent
            recommendations << {
              step: step[:name],
              current_agent: current_agent,
              recommended_agent: optimal_agent,
              reason: "Higher success rate and faster execution"
            }
          end
        end

        if recommendations.any?
          {
            type: :agent_assignment,
            recommendations: recommendations,
            confidence: 0.82
          }
        end
      end

      def gather_training_data(task_type)
        @feedback_store.get_training_data(
          task_type: task_type,
          min_quality_score: 4.0,
          limit: 10000
        )
      end

      def prepare_training_dataset(training_data)
        # Convert to feature vectors
        features = training_data.map { |data| extract_features(data) }
        labels = training_data.map { |data| extract_labels(data) }

        {
          features: features,
          labels: labels,
          size: training_data.size
        }
      end

      def extract_features(data)
        # Extract relevant features for ML
        {
          workflow_complexity: calculate_complexity(data[:workflow]),
          step_count: data[:workflow][:steps].size,
          tool_diversity: calculate_tool_diversity(data[:workflow]),
          estimated_duration: data[:estimated_duration],
          context_richness: calculate_context_richness(data[:context]),
          user_experience_level: data[:user][:experience_level] || 0
        }
      end

      def extract_labels(data)
        {
          success: data[:success],
          duration: data[:actual_duration],
          satisfaction: data[:satisfaction_score]
        }
      end

      def determine_model_type(task_type)
        case task_type
        when :classification
          :random_forest
        when :regression
          :gradient_boosting
        when :sequence_prediction
          :lstm
        else
          :neural_network
        end
      end

      def optimize_hyperparameters(task_type, dataset)
        # Simple hyperparameter optimization
        base_params = {
          learning_rate: 0.01,
          batch_size: 32,
          epochs: 100
        }

        # Adjust based on dataset size
        if dataset[:size] < 1000
          base_params[:learning_rate] = 0.001
          base_params[:epochs] = 200
        elsif dataset[:size] > 10000
          base_params[:batch_size] = 128
          base_params[:learning_rate] = 0.1
        end

        base_params
      end

      def evaluate_model(model, dataset)
        # Split data
        test_size = (dataset[:size] * 0.2).to_i
        test_features = dataset[:features].last(test_size)
        test_labels = dataset[:labels].last(test_size)

        # Make predictions
        predictions = model.predict(test_features)

        # Calculate metrics
        {
          accuracy: calculate_accuracy(predictions, test_labels),
          precision: calculate_precision(predictions, test_labels),
          recall: calculate_recall(predictions, test_labels),
          f1_score: calculate_f1_score(predictions, test_labels)
        }
      end

      def deploy_model(task_type, model)
        # Save model
        model_path = Rails.root.join("models", task_type.to_s, "model_#{Time.current.to_i}.pkl")
        model.save(model_path)

        # Update configuration
        Rails.cache.write("active_model:#{task_type}", model_path)

        # Notify agents
        AgentRegistry.instance.broadcast(:model_updated, {
          task_type: task_type,
          model_path: model_path
        })
      end

      def calculate_prediction_confidence(similarity_scores)
        return 0.5 if similarity_scores.empty?

        # Higher confidence if many similar successful patterns
        top_scores = similarity_scores.first(5)
        avg_similarity = top_scores.sum / top_scores.size.to_f

        # Adjust for number of similar patterns
        confidence = avg_similarity * [ similarity_scores.size / 10.0, 1.0 ].min

        [ confidence, 0.95 ].min # Cap at 95%
      end

      def expected_duration(workflow_type)
        @pattern_analyzer.get_average_duration(workflow_type) || 60
      end

      def map_issue_to_improvement(issue)
        improvements = {
          slow_execution: {
            area: :performance,
            priority: :high,
            suggestion: "Optimize slow steps and consider parallelization"
          },
          high_failure_rate: {
            area: :reliability,
            priority: :critical,
            suggestion: "Review error handling and add retries"
          },
          resource_waste: {
            area: :efficiency,
            priority: :medium,
            suggestion: "Optimize resource allocation"
          }
        }

        improvements[issue] || {
          area: :general,
          priority: :low,
          suggestion: "Review and optimize #{issue}"
        }
      end
    end

    # Supporting classes
    class FeedbackStore
      def initialize
        @redis = ($redis || Redis.new)
      end

      def store_experience(experience)
        key = "learning:experiences:#{experience[:workflow_type]}"
        @redis.zadd(key, Time.current.to_f, experience.to_json)
        @redis.expire(key, 90.days)
      end

      def store_user_feedback(feedback)
        key = "learning:feedback:#{feedback[:workflow_type]}"
        @redis.zadd(key, Time.current.to_f, feedback.to_json)
        @redis.expire(key, 90.days)
      end

      def find_workflows(criteria)
        key = "learning:experiences:#{criteria[:type]}"

        experiences = @redis.zrevrange(key, 0, criteria[:limit] - 1).map do |json|
          JSON.parse(json, symbolize_names: true)
        end

        experiences.select do |exp|
          criteria.all? do |k, v|
            next true if [ :type, :limit ].include?(k)
            exp[k] == v
          end
        end
      end

      def get_training_data(criteria)
        workflows = find_workflows(criteria)

        # Filter by quality
        workflows.select do |w|
          w[:metrics][:satisfaction_score] >= criteria[:min_quality_score]
        end
      end
    end

    class PatternAnalyzer
      def analyze_workflow_patterns(workflow_type)
        # Analyze execution patterns
        executions = get_recent_executions(workflow_type)

        {
          execution_count: executions.size,
          success_rate: calculate_success_rate(executions),
          avg_duration: calculate_average_duration(executions),
          avg_tokens: calculate_average_tokens(executions),
          common_step_order: extract_common_step_order(executions),
          tool_performance: analyze_tool_performance(executions),
          agent_performance: analyze_agent_performance(executions),
          resource_usage: analyze_resource_usage(executions),
          performance_trend: detect_performance_trend(executions),
          last_optimization: get_last_optimization_time(workflow_type)
        }
      end

      def get_success_patterns(workflow_type)
        successful_workflows = get_successful_workflows(workflow_type)

        successful_workflows.map do |workflow|
          {
            features: extract_pattern_features(workflow),
            score: workflow[:metrics][:satisfaction_score],
            duration: workflow[:execution_time]
          }
        end
      end

      def get_average_duration(workflow_type)
        ($redis || Redis.new).get("patterns:#{workflow_type}:avg_duration")&.to_f
      end

      private

      def get_recent_executions(workflow_type, limit = 1000)
        key = "learning:experiences:#{workflow_type}"
        ($redis || Redis.new).zrevrange(key, 0, limit - 1).map do |json|
          JSON.parse(json, symbolize_names: true)
        end
      end

      def calculate_success_rate(executions)
        return 0 if executions.empty?
        successful = executions.count { |e| e[:success] }
        successful.to_f / executions.size
      end

      def calculate_average_duration(executions)
        return 0 if executions.empty?
        total = executions.sum { |e| e[:execution_time] || 0 }
        total / executions.size.to_f
      end

      def calculate_average_tokens(executions)
        return 0 if executions.empty?
        total = executions.sum { |e| e[:metrics][:tokens_used] || 0 }
        total / executions.size.to_f
      end
    end

    class OptimizationService
      def optimize_workflow(workflow_type, patterns)
        # Implementation of workflow optimization
      end
    end

    class ModelTrainer
      def train(dataset, config)
        # Simplified model training
        OpenStruct.new(
          id: SecureRandom.uuid,
          predict: ->(features) { Array.new(features.size) { rand > 0.5 } },
          save: ->(path) { File.write(path, "model_data") }
        )
      end
    end

    class KnowledgeBase
      def update_from_insights(insights)
        insights.each do |insight|
          store_insight(insight)
        end
      end

      private

      def store_insight(insight)
        key = "knowledge:#{insight[:type]}"
        ($redis || Redis.new).zadd(key, Time.current.to_f, insight.to_json)
      end
    end
  end
end
