# frozen_string_literal: true

module Benchmarks
  # ============================================
  # HuggingFace Dataset Downloader
  # Downloads and caches real benchmark datasets
  # ============================================
  class HuggingfaceDatasets
    CACHE_DIR = Rails.root.join('tmp', 'benchmarks', 'datasets')
    
    # Dataset configurations
    # Note: Some datasets require HuggingFace authentication (gated)
    # We focus on publicly available datasets
    DATASETS = {
      gsm8k: {
        repo: 'openai/gsm8k',
        subset: 'main',
        split: 'test',
        question_field: 'question',
        answer_field: 'answer',
        metadata_fields: [],
        sample_size: 200,
        description: 'Grade school math word problems (1319 test questions)',
        public: true
      },
      mmlu: {
        repo: 'cais/mmlu',
        subset: 'all',
        split: 'test',
        question_field: 'question',
        answer_field: 'answer',
        metadata_fields: ['subject', 'choices'],
        sample_size: 200,
        description: 'Massive Multitask Language Understanding (14,042 test questions)',
        public: true,
        # MMLU answers are indices (0-3), need to map to choices
        answer_processor: ->(answer, row) {
          choices = row['choices'] || row[:choices]
          if choices && answer.is_a?(Integer) && answer < choices.size
            choices[answer]
          else
            answer
          end
        }
      },
      arc_challenge: {
        repo: 'allenai/ai2_arc',
        subset: 'ARC-Challenge',
        split: 'test',
        question_field: 'question',
        answer_field: 'answerKey',
        metadata_fields: ['choices'],
        sample_size: 100,
        description: 'AI2 Reasoning Challenge - hard science questions',
        public: true
      },
      truthful_qa: {
        repo: 'truthful_qa',
        subset: 'generation',
        split: 'validation',
        question_field: 'question',
        answer_field: 'best_answer',
        metadata_fields: ['category', 'correct_answers'],
        sample_size: 100,
        description: 'TruthfulQA - tests for hallucination',
        public: true
      },
      hellaswag: {
        repo: 'Rowan/hellaswag',
        subset: 'default',
        split: 'validation',
        question_field: 'ctx',
        answer_field: 'label',
        metadata_fields: ['endings', 'activity_label'],
        sample_size: 100,
        description: 'HellaSwag - commonsense reasoning',
        public: true
      },
      winogrande: {
        repo: 'winogrande',
        subset: 'winogrande_xl',
        split: 'validation',
        question_field: 'sentence',
        answer_field: 'answer',
        metadata_fields: ['option1', 'option2'],
        sample_size: 100,
        description: 'WinoGrande - commonsense reasoning',
        public: true
      }
    }.freeze

    class << self
      # Download a dataset from HuggingFace
      def download(dataset_key, force: false)
        config = DATASETS[dataset_key.to_sym]
        raise ArgumentError, "Unknown dataset: #{dataset_key}" unless config

        cache_file = cache_path(dataset_key)
        
        # Return cached if exists and not forcing
        if File.exist?(cache_file) && !force
          Rails.logger.info "[Benchmark] Using cached dataset: #{dataset_key}"
          return load_cached(dataset_key)
        end

        Rails.logger.info "[Benchmark] Downloading dataset: #{dataset_key} from HuggingFace"
        
        # Download via HuggingFace API
        data = fetch_from_huggingface(config)
        
        # Process and cache
        processed = process_dataset(data, config)
        save_cache(dataset_key, processed)
        
        processed
      end

      # Get questions for a dataset (downloads if needed)
      def get_questions(dataset_key, limit: nil)
        data = download(dataset_key)
        limit ? data.first(limit) : data
      end

      # Get a random sample from a dataset
      def sample(dataset_key, count: 50)
        data = download(dataset_key)
        data.sample(count)
      end

      # List available datasets
      def available
        DATASETS.map do |key, config|
          {
            key: key,
            description: config[:description],
            sample_size: config[:sample_size],
            cached: File.exist?(cache_path(key))
          }
        end
      end

      # Check if dataset is cached
      def cached?(dataset_key)
        File.exist?(cache_path(dataset_key))
      end

      # Clear cache for a dataset
      def clear_cache(dataset_key = nil)
        if dataset_key
          FileUtils.rm_f(cache_path(dataset_key))
        else
          FileUtils.rm_rf(CACHE_DIR)
        end
      end

      private

      def cache_path(dataset_key)
        FileUtils.mkdir_p(CACHE_DIR)
        CACHE_DIR.join("#{dataset_key}.json")
      end

      def load_cached(dataset_key)
        JSON.parse(File.read(cache_path(dataset_key)), symbolize_names: true)
      end

      def save_cache(dataset_key, data)
        File.write(cache_path(dataset_key), data.to_json)
      end

      def fetch_from_huggingface(config)
        require 'net/http'
        require 'json'

        all_rows = []
        target_count = config[:sample_size]
        batch_size = 100  # HuggingFace API max is 100 per request
        offset = 0

        while all_rows.size < target_count
          remaining = target_count - all_rows.size
          fetch_count = [batch_size, remaining].min

          uri = URI("https://datasets-server.huggingface.co/rows")
          uri.query = URI.encode_www_form(
            dataset: config[:repo],
            config: config[:subset],
            split: config[:split],
            offset: offset,
            length: fetch_count
          )

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.read_timeout = 60

          request = Net::HTTP::Get.new(uri)
          request['Accept'] = 'application/json'

          response = http.request(request)

          if response.code == '200'
            data = JSON.parse(response.body)
            rows = data['rows'] || []
            break if rows.empty?  # No more data
            
            all_rows.concat(rows)
            offset += rows.size
            
            Rails.logger.info "[Benchmark] Fetched #{all_rows.size}/#{target_count} rows from #{config[:repo]}"
          else
            Rails.logger.error "[Benchmark] HuggingFace API error: #{response.code} - #{response.body}"
            break
          end
          
          # Small delay between requests to be nice to the API
          sleep(0.2) if all_rows.size < target_count
        end

        { 'rows' => all_rows }
      rescue => e
        Rails.logger.error "[Benchmark] Error fetching from HuggingFace: #{e.message}"
        Rails.logger.error e.backtrace.first(3).join("\n")
        # Return empty array on failure - we'll use fallback data
        { 'rows' => [] }
      end

      def process_dataset(raw_data, config)
        rows = raw_data['rows'] || raw_data[:rows] || []
        
        rows.map.with_index do |row, idx|
          # Handle both string and symbol keys
          data = row['row'] || row[:row] || row
          
          # Extract question and answer - try both string and symbol keys
          q_field = config[:question_field]
          a_field = config[:answer_field]
          
          question = data[q_field] || data[q_field.to_s] || data[q_field.to_sym]
          answer = data[a_field] || data[a_field.to_s] || data[a_field.to_sym]
          
          # Apply custom answer processor if defined
          if config[:answer_processor]
            answer = config[:answer_processor].call(answer, data)
          end
          
          # For GSM8K, extract just the numeric answer
          if config[:repo] == 'openai/gsm8k' && answer
            # GSM8K answers are like "#### 42" - extract the number
            answer = answer.to_s.split('####').last&.strip || answer
          end
          
          # For MMLU with choices, format the question properly
          if config[:repo] == 'cais/mmlu'
            choices = data['choices'] || data[:choices]
            if choices.is_a?(Array)
              formatted_choices = choices.each_with_index.map { |c, i| "#{('A'.ord + i).chr}) #{c}" }.join("\n")
              question = "#{question}\n\n#{formatted_choices}"
              # Convert numeric answer to letter
              if answer.is_a?(Integer)
                answer = ('A'.ord + answer).chr
              end
            end
          end

          # Extract metadata
          metadata = {}
          config[:metadata_fields].each do |field|
            metadata[field.to_sym] = data[field] || data[field.to_sym]
          end

          {
            id: "#{config[:repo].split('/').last}_#{idx}",
            question: question,
            answer: answer,
            metadata: metadata,
            source: config[:repo]
          }
        end.compact.reject { |q| q[:question].blank? }
      end
    end
  end
end

