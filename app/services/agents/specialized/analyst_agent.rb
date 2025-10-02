module Agents
  module Specialized
    class AnalystAgent < Agents::Base::BaseAgent
      include Agents::Resilience
      
      def initialize(initial_context: {})
        super(
          role: 'analyst',
          capabilities: [
            'data_analysis',
            'pattern_recognition',
            'insight_generation',
            'report_creation',
            'trend_analysis',
            'performance_metrics',
            'workflow_analysis',
            'adaptive_planning'
          ],
          context: initial_context,
          task_session: initial_context[:task_session]
        )
        
        # Load analytics-specific tools
        @tool_catalog = ::Tools::ToolCatalog.instance rescue nil
        @ai_service = BedrockService.new(
          user: initial_context[:user],
          entity: initial_context[:entity]
        ) rescue nil
        
        Rails.logger.info "AnalystAgent #{@id}: Initialized with analytics capabilities"
      end
      
      def execute_step(step, inputs = {})
        Rails.logger.info "AnalystAgent #{@id}: Analyzing step #{step[:id]} (#{step[:type]})"
        
        # Record analysis start
        analysis_record = {
          step_id: step[:id],
          started_at: Time.current,
          inputs: sanitize_inputs(inputs),
          analysis_type: determine_analysis_type(step)
        }
        
        begin
          # Validate step requirements
          validate_step_requirements(step, inputs)
          
          # Execute analysis based on step type
          result = case step[:type]
          when 'tool_call'
            analyze_and_execute_tool(step, inputs)
          when 'data_analysis'
            perform_data_analysis(step, inputs)
          when 'insight_generation'
            generate_insights(step, inputs)
          when 'report_creation'
            create_analytical_report(step, inputs)
          else
            execute_tool_step(step, inputs)
          end
          
          # Enhance result with analytical insights
          if result[:success] && step[:config][:generate_insights]
            insights = generate_contextual_insights(result, step, inputs)
            result[:insights] = insights
            result[:analytical_summary] = create_summary(result, insights)
          end
          
          # Update memory with analysis outcome
          update_memory(:analysis_completed, {
            step_id: step[:id],
            result: result,
            insights_generated: result[:insights]&.any? || false,
            timestamp: Time.current
          })
          
          result
        rescue => e
          Rails.logger.error "AnalystAgent #{@id}: Analysis failed - #{e.message}"
          
          {
            success: false,
            error: "Analysis error: #{e.message}",
            analysis_failed: true
          }
        end
      end
      
      def analyze_data_patterns(data, analysis_config = {})
        Rails.logger.info "AnalystAgent #{@id}: Analyzing data patterns"
        
        patterns = {
          trends: [],
          anomalies: [],
          correlations: [],
          insights: []
        }
        
        # Detect trends
        if data.is_a?(Array) && data.length > 1
          patterns[:trends] = detect_trends(data, analysis_config)
        end
        
        # Find anomalies
        patterns[:anomalies] = detect_anomalies(data, analysis_config)
        
        # Identify correlations
        if analysis_config[:correlation_fields]
          patterns[:correlations] = find_correlations(data, analysis_config[:correlation_fields])
        end
        
        # Generate insights using AI
        if @ai_service && analysis_config[:ai_insights]
          patterns[:insights] = generate_ai_insights(data, patterns)
        end
        
        patterns
      end
      
      def create_visualization_plan(data, visualization_type = 'auto')
        Rails.logger.info "AnalystAgent #{@id}: Creating visualization plan"
        
        # Analyze data structure
        data_analysis = analyze_data_structure(data)
        
        # Determine best visualization type
        recommended_type = if visualization_type == 'auto'
          recommend_visualization_type(data_analysis)
        else
          visualization_type
        end
        
        # Create visualization configuration
        {
          type: recommended_type,
          data_structure: data_analysis,
          config: build_visualization_config(data_analysis, recommended_type),
          title: generate_visualization_title(data_analysis),
          description: generate_visualization_description(data_analysis)
        }
      end
      
      def generate_analytical_report(data, report_config = {})
        Rails.logger.info "AnalystAgent #{@id}: Generating analytical report"
        
        # Analyze the data
        patterns = analyze_data_patterns(data, report_config)
        
        # Generate report sections
        report = {
          title: report_config[:title] || "Data Analysis Report",
          generated_at: Time.current,
          data_summary: summarize_data(data),
          key_findings: extract_key_findings(patterns),
          trends: patterns[:trends],
          recommendations: generate_recommendations(patterns),
          visualizations: suggest_visualizations(data, patterns)
        }
        
        # Generate narrative summary using AI
        if @ai_service
          report[:narrative] = generate_narrative_summary(report)
        end
        
        report
      end
      
      private
      
      def determine_analysis_type(step)
        if step[:config][:analysis_type]
          step[:config][:analysis_type]
        elsif step[:config][:tool] == 'aggregate_artifact_data'
          'aggregation'
        elsif step[:config][:tool] == 'create_dynamic_visualization'
          'visualization'
        else
          'general'
        end
      end
      
      def analyze_and_execute_tool(step, inputs)
        tool_name = step[:config][:tool]
        tool_args = step[:config][:tool_args] || {}
        merged_inputs = tool_args.merge(inputs)
        
        Rails.logger.info "AnalystAgent #{@id}: Executing analytical tool: #{tool_name}"
        
        # Pre-execution analysis
        pre_analysis = analyze_inputs(merged_inputs, step)
        
        # Execute the tool with analytical context
        if @tool_catalog
          context = {
            user: @task_session&.user,
            entity: @task_session&.user&.entity,
            context: { 
              task_session_id: @task_session&.id, 
              analysis: true,
              pre_analysis: pre_analysis 
            }
          }
          
          with_resilience(tool_name) do
            result = @tool_catalog.execute_tool(tool_name, merged_inputs, context)
            
            # Post-execution analysis
            if result[:success]
              result[:pre_analysis] = pre_analysis
              result[:post_analysis] = analyze_results(result, step)
              result[:analytical_metadata] = {
                analyzed_by: @id,
                analysis_timestamp: Time.current,
                confidence_score: calculate_confidence_score(result)
              }
            end
            
            result
          end
        else
          {
            success: false,
            error: "Tool catalog not available for analysis"
          }
        end
      end
      
      def detect_trends(data, config)
        trends = []
        
        # Simple trend detection for time-series data
        if data.first.is_a?(Hash) && data.first.key?('created_at')
          # Group by time periods and detect growth/decline
          time_groups = data.group_by { |item| Date.parse(item['created_at']).beginning_of_month }
          if time_groups.keys.length > 1
            counts = time_groups.transform_values(&:count)
            if counts.values.last > counts.values.first
              trends << {
                type: 'growth',
                description: 'Increasing trend over time',
                confidence: 0.8
              }
            elsif counts.values.last < counts.values.first
              trends << {
                type: 'decline', 
                description: 'Decreasing trend over time',
                confidence: 0.8
              }
            end
          end
        end
        
        trends
      end
      
      def detect_anomalies(data, config)
        anomalies = []
        
        # Simple anomaly detection
        if data.is_a?(Array) && data.length > 2
          # Look for outliers in numeric fields
          numeric_fields = data.first.keys.select { |k| data.first[k].is_a?(Numeric) } if data.first.is_a?(Hash)
          
          numeric_fields&.each do |field|
            values = data.map { |item| item[field] }.compact
            if values.length > 2
              mean = values.sum.to_f / values.length
              std_dev = Math.sqrt(values.map { |v| (v - mean) ** 2 }.sum / values.length)
              
              outliers = values.select { |v| (v - mean).abs > 2 * std_dev }
              if outliers.any?
                anomalies << {
                  field: field,
                  type: 'statistical_outlier',
                  count: outliers.length,
                  description: "Found #{outliers.length} statistical outliers in #{field}"
                }
              end
            end
          end
        end
        
        anomalies
      end
      
      def find_correlations(data, fields)
        correlations = []
        
        # Simple correlation detection between specified fields
        if data.is_a?(Array) && data.length > 5 && fields.length >= 2
          fields.combination(2).each do |field1, field2|
            correlation = calculate_correlation(data, field1, field2)
            if correlation.abs > 0.5
              correlations << {
                fields: [field1, field2],
                strength: correlation,
                description: "#{correlation > 0 ? 'Positive' : 'Negative'} correlation between #{field1} and #{field2}"
              }
            end
          end
        end
        
        correlations
      end
      
      def generate_ai_insights(data, patterns)
        return [] unless @ai_service
        
        prompt = build_insights_prompt(data, patterns)
        
        begin
          response = @ai_service.complete(
            messages: [
              { role: 'system', content: 'You are a data analyst expert at generating insights.' },
              { role: 'user', content: prompt }
            ],
            max_tokens: 4000,
            temperature: 0.7
          )
          
          # Parse insights from response
          parse_insights_response(response)
        rescue => e
          Rails.logger.error "AI insights generation failed: #{e.message}"
          []
        end
      end
      
      def analyze_data_structure(data)
        return { type: 'empty', count: 0 } if data.nil? || (data.respond_to?(:empty?) && data.empty?)
        
        if data.is_a?(Array)
          {
            type: 'array',
            count: data.length,
            item_type: data.first.class.name.downcase,
            fields: data.first.is_a?(Hash) ? data.first.keys : [],
            sample: data.first(3)
          }
        elsif data.is_a?(Hash)
          {
            type: 'hash',
            keys: data.keys,
            nested_structures: data.values.map(&:class).uniq.map(&:name),
            sample: data
          }
        else
          {
            type: 'scalar',
            value_type: data.class.name.downcase,
            sample: data
          }
        end
      end
      
      def recommend_visualization_type(data_analysis)
        case data_analysis[:type]
        when 'array'
          if data_analysis[:count] > 20
            'table'
          elsif data_analysis[:fields]&.include?('created_at')
            'timeline'
          else
            'cards'
          end
        when 'hash'
          if data_analysis[:keys].length > 10
            'table'
          else
            'key_value'
          end
        else
          'text'
        end
      end
      
      def build_visualization_config(data_analysis, viz_type)
        case viz_type
        when 'timeline'
          {
            x_axis: 'created_at',
            y_axis: 'count',
            group_by: 'date'
          }
        when 'table'
          {
            columns: data_analysis[:fields] || data_analysis[:keys],
            sortable: true,
            filterable: true
          }
        else
          {}
        end
      end
      
      def calculate_correlation(data, field1, field2)
        # Simple Pearson correlation
        values1 = data.map { |item| item[field1] }.compact.select { |v| v.is_a?(Numeric) }
        values2 = data.map { |item| item[field2] }.compact.select { |v| v.is_a?(Numeric) }
        
        return 0 if values1.length != values2.length || values1.length < 2
        
        mean1 = values1.sum.to_f / values1.length
        mean2 = values2.sum.to_f / values2.length
        
        numerator = values1.zip(values2).map { |v1, v2| (v1 - mean1) * (v2 - mean2) }.sum
        denominator = Math.sqrt(values1.map { |v| (v - mean1) ** 2 }.sum * values2.map { |v| (v - mean2) ** 2 }.sum)
        
        denominator.zero? ? 0 : numerator / denominator
      end
      
      def sanitize_inputs(inputs)
        # Remove sensitive data from inputs for logging
        inputs.except(:password, :api_key, :secret)
      end
      
      def build_insights_prompt(data, patterns)
        <<~PROMPT
          Analyze this data and generate key insights:
          
          DATA SUMMARY:
          - Type: #{data.class.name}
          - Count: #{data.respond_to?(:length) ? data.length : 'N/A'}
          - Sample: #{data.is_a?(Array) ? data.first(2) : data}
          
          DETECTED PATTERNS:
          - Trends: #{patterns[:trends].map { |t| t[:description] }.join(', ')}
          - Anomalies: #{patterns[:anomalies].map { |a| a[:description] }.join(', ')}
          - Correlations: #{patterns[:correlations].map { |c| c[:description] }.join(', ')}
          
          Generate 3-5 actionable insights in JSON format:
          [
            {
              "insight": "description of insight",
              "confidence": 0.8,
              "actionable": true,
              "recommendation": "what to do about it"
            }
          ]
        PROMPT
      end
      
      def parse_insights_response(response)
        begin
          # Try to extract JSON from response
          json_match = response.match(/\[.*\]/m)
          if json_match
            JSON.parse(json_match[0])
          else
            []
          end
        rescue JSON::ParserError
          []
        end
      end
      
      def summarize_data(data)
        case data
        when Array
          {
            total_records: data.length,
            data_type: 'collection',
            fields: data.first.is_a?(Hash) ? data.first.keys : [],
            date_range: extract_date_range(data)
          }
        when Hash
          {
            total_fields: data.keys.length,
            data_type: 'object',
            keys: data.keys
          }
        else
          {
            data_type: 'scalar',
            value: data
          }
        end
      end
      
      def extract_key_findings(patterns)
        findings = []
        
        patterns[:trends].each do |trend|
          findings << {
            type: 'trend',
            description: trend[:description],
            confidence: trend[:confidence]
          }
        end
        
        patterns[:anomalies].each do |anomaly|
          findings << {
            type: 'anomaly',
            description: anomaly[:description],
            severity: anomaly[:count] > 5 ? 'high' : 'medium'
          }
        end
        
        findings
      end
      
      def generate_recommendations(patterns)
        recommendations = []
        
        # Generate recommendations based on patterns
        patterns[:trends].each do |trend|
          if trend[:type] == 'decline'
            recommendations << {
              priority: 'high',
              action: 'investigate_decline',
              description: "Investigate the declining trend in #{trend[:field] || 'data'}"
            }
          elsif trend[:type] == 'growth'
            recommendations << {
              priority: 'medium',
              action: 'capitalize_growth',
              description: "Consider capitalizing on the growth trend"
            }
          end
        end
        
        patterns[:anomalies].each do |anomaly|
          recommendations << {
            priority: 'medium',
            action: 'review_anomaly',
            description: "Review #{anomaly[:description]} for potential issues or opportunities"
          }
        end
        
        recommendations
      end
      
      def suggest_visualizations(data, patterns)
        suggestions = []
        
        # Suggest visualizations based on data and patterns
        if patterns[:trends].any?
          suggestions << {
            type: 'line_chart',
            title: 'Trend Analysis',
            description: 'Shows trends over time'
          }
        end
        
        if data.is_a?(Array) && data.length > 10
          suggestions << {
            type: 'table',
            title: 'Detailed Data View',
            description: 'Comprehensive data table'
          }
        end
        
        if patterns[:correlations].any?
          suggestions << {
            type: 'scatter_plot',
            title: 'Correlation Analysis',
            description: 'Shows relationships between variables'
          }
        end
        
        suggestions
      end
      
      def extract_date_range(data)
        return nil unless data.is_a?(Array) && data.first.is_a?(Hash)
        
        date_fields = ['created_at', 'updated_at', 'date', 'timestamp']
        date_field = date_fields.find { |field| data.first.key?(field) }
        
        return nil unless date_field
        
        dates = data.map { |item| Date.parse(item[date_field]) rescue nil }.compact
        return nil if dates.empty?
        
        {
          start: dates.min,
          end: dates.max,
          span_days: (dates.max - dates.min).to_i
        }
      end
      
      def calculate_confidence_score(result)
        score = 0.5 # Base confidence
        
        # Increase confidence based on data quality
        if result[:data] && result[:data].respond_to?(:length)
          score += [result[:data].length / 100.0, 0.3].min
        end
        
        # Increase confidence if no errors
        score += 0.2 if result[:success] && !result[:error]
        
        [score, 1.0].min
      end
      
      def generate_narrative_summary(report)
        prompt = <<~PROMPT
          Create a narrative summary of this analytical report:
          
          KEY FINDINGS:
          #{report[:key_findings].map { |f| "- #{f[:description]}" }.join("\n")}
          
          TRENDS:
          #{report[:trends].map { |t| "- #{t[:description]}" }.join("\n")}
          
          DATA SUMMARY:
          #{report[:data_summary]}
          
          Write a 2-3 sentence executive summary highlighting the most important insights.
        PROMPT
        
        begin
          @ai_service.complete(
            messages: [
              { role: 'system', content: 'You are an expert data analyst writing executive summaries.' },
              { role: 'user', content: prompt }
            ],
            max_tokens: 1000,
            temperature: 0.6
          )
        rescue => e
          Rails.logger.error "Narrative generation failed: #{e.message}"
          "Analysis completed with #{report[:key_findings].length} key findings."
        end
      end
      
      def analyze_inputs(inputs, step)
        {
          input_count: inputs.keys.length,
          has_required_fields: check_required_fields(inputs, step),
          data_quality_score: assess_data_quality(inputs),
          analysis_timestamp: Time.current
        }
      end
      
      def analyze_results(result, step)
        {
          result_size: result[:data].respond_to?(:length) ? result[:data].length : 1,
          success_indicators: extract_success_indicators(result),
          potential_issues: identify_potential_issues(result),
          analysis_timestamp: Time.current
        }
      end
      
      def check_required_fields(inputs, step)
        required = step[:config][:required_inputs] || []
        missing = required - inputs.keys.map(&:to_s)
        missing.empty?
      end
      
      def assess_data_quality(inputs)
        # Simple data quality assessment
        score = 1.0
        
        inputs.each do |key, value|
          if value.nil? || value.to_s.strip.empty?
            score -= 0.1
          end
        end
        
        [score, 0.0].max
      end
      
      def extract_success_indicators(result)
        indicators = []
        
        if result[:success]
          indicators << 'execution_successful'
        end
        
        if result[:data] && result[:data].respond_to?(:length) && result[:data].length > 0
          indicators << 'data_returned'
        end
        
        indicators
      end
      
      def identify_potential_issues(result)
        issues = []
        
        if result[:data] && result[:data].respond_to?(:empty?) && result[:data].empty?
          issues << 'empty_result_set'
        end
        
        if result[:error]
          issues << 'execution_error'
        end
        
        issues
      end
    end
  end
end
