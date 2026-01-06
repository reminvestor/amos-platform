# frozen_string_literal: true

module PlatformEvolution
  # LogMonitorService - Watches application logs for errors and creates tickets
  #
  # This service:
  # 1. Reads and parses Rails log files
  # 2. Detects error patterns and exceptions
  # 3. Deduplicates similar errors
  # 4. Creates support tickets for new issues
  # 5. Tracks error frequency and trends
  #
  class LogMonitorService
    attr_reader :entity, :log_path, :processed_count, :tickets_created

    # Error patterns to detect
    ERROR_PATTERNS = [
      /(\w+Error): (.+)/,
      /(\w+Exception): (.+)/,
      /FATAL -- : (.+)/,
      /ERROR -- : (.+)/,
      /undefined method `(.+)' for/,
      /uninitialized constant (\w+)/,
      /PG::(\w+): ERROR/,
      /ActiveRecord::(\w+)/
    ].freeze

    # Patterns to ignore (noise or expected during development)
    IGNORE_PATTERNS = [
      /ActionController::RoutingError/,
      /ActionController::InvalidAuthenticityToken/,
      /Net::OpenTimeout/,
      /Rack::Timeout::RequestTimeoutException/,
      # Development/migration noise
      /ActiveRecord::PendingMigrationError/,
      /Migrations are pending/,
      /pending migration/i,
      /ActiveRecord::NoDatabaseError/,
      /database.*does not exist/i,
      # Asset pipeline noise
      /Sprockets::FileNotFound/,
      /ActionController::UnknownFormat/,
      # Common transient errors
      /ActiveRecord::ConnectionNotEstablished/,
      /PG::ConnectionBad/,
      /Redis::CannotConnectError/,
      # Test/development specific
      /Webpacker::Manifest::MissingEntryError/,
      /LoadError.*cannot load such file/
    ].freeze

    def initialize(entity, options = {})
      @entity = entity
      @log_path = options[:log_path] || Rails.root.join('log', "#{Rails.env}.log")
      @processed_count = 0
      @tickets_created = 0
      @error_threshold = options[:error_threshold] || 3  # Create ticket after N occurrences
      @time_window = options[:time_window] || 1.hour     # Within this time window
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MAIN MONITORING LOOP
    # ═══════════════════════════════════════════════════════════════════════════

    def monitor_once
      Rails.logger.info "[LogMonitor] Starting log scan for entity #{entity.id}"

      errors = scan_recent_errors
      grouped = group_by_signature(errors)
      
      grouped.each do |signature, error_group|
        process_error_group(signature, error_group)
      end

      {
        processed: @processed_count,
        tickets_created: @tickets_created,
        unique_errors: grouped.count
      }
    end

    def scan_recent_errors
      errors = []
      
      # Read from database (ErrorLogEntry) first
      recent_entries = ErrorLogEntry.unprocessed.today.limit(1000)
      errors.concat(recent_entries.map(&:to_context))

      # Also check Rails logger if available
      if File.exist?(@log_path)
        file_errors = parse_log_file(@log_path)
        errors.concat(file_errors)
      end

      errors
    end

    def parse_log_file(path, since: 1.hour.ago)
      errors = []
      current_error = nil
      
      File.foreach(path) do |line|
        # Try to extract timestamp
        timestamp = extract_timestamp(line)
        next if timestamp && timestamp < since

        # Check if this is an error line
        if error_match = match_error_pattern(line)
          # Save previous error if exists
          if current_error
            errors << current_error unless should_ignore?(current_error[:error_class])
          end

          current_error = {
            error_class: error_match[:class],
            error_message: error_match[:message],
            stack_trace: '',
            occurred_at: timestamp || Time.current
          }
        elsif current_error && line.match?(/^\s+/)
          # This is a stack trace line
          current_error[:stack_trace] += line
        else
          # End of stack trace
          if current_error
            errors << current_error unless should_ignore?(current_error[:error_class])
            current_error = nil
          end
        end

        @processed_count += 1
      end

      # Don't forget the last error
      if current_error
        errors << current_error unless should_ignore?(current_error[:error_class])
      end

      errors
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # ERROR PROCESSING
    # ═══════════════════════════════════════════════════════════════════════════

    def group_by_signature(errors)
      errors.group_by do |error|
        generate_signature(
          error[:error_class],
          error[:error_message],
          error[:stack_trace]
        )
      end
    end

    def process_error_group(signature, errors)
      count = errors.length
      
      # Check if we already have a ticket for this signature
      existing_ticket = SupportTicket.where(
        entity: entity,
        error_signature: signature
      ).open_tickets.first

      if existing_ticket
        # Update the ticket with new occurrence count
        Rails.logger.info "[LogMonitor] Error already tracked: #{signature} (#{count} new occurrences)"
        return
      end

      # Check if this exceeds threshold
      if count >= @error_threshold
        create_ticket_from_errors(signature, errors)
      else
        Rails.logger.debug "[LogMonitor] Error below threshold: #{signature} (#{count}/#{@error_threshold})"
      end

      # Mark entries as processed
      ErrorLogEntry.where(error_signature: signature).unprocessed.update_all(processed: true)
    end

    def create_ticket_from_errors(signature, errors)
      first_error = errors.first
      
      # Extract file and line from stack trace
      error_file, error_line = extract_source_location(first_error[:stack_trace])
      
      ticket = SupportTicket.create!(
        entity: entity,
        title: "#{first_error[:error_class]}: #{first_error[:error_message].to_s.truncate(100)}",
        description: build_ticket_description(errors),
        source: 'log_monitor',
        priority: determine_priority(first_error, errors.count),
        category: 'bug',
        error_class: first_error[:error_class],
        error_message: first_error[:error_message],
        stack_trace: first_error[:stack_trace],
        error_file: error_file,
        error_line: error_line,
        error_signature: signature,
        error_context: {
          occurrence_count: errors.count,
          first_seen: errors.min_by { |e| e[:occurred_at] }[:occurred_at],
          last_seen: errors.max_by { |e| e[:occurred_at] }[:occurred_at]
        }
      )

      @tickets_created += 1
      Rails.logger.info "[LogMonitor] Created ticket #{ticket.ticket_number} for #{signature}"

      # Link any ErrorLogEntry records to this ticket
      ErrorLogEntry.where(error_signature: signature).update_all(
        support_ticket_id: ticket.id,
        ticket_created: true,
        processed: true
      )

      # Auto-start debugging for all tickets from log monitor
      # Bugs should be investigated automatically
      PlatformEvolution::DebugAgentJob.perform_later(ticket.id)

      ticket
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    def match_error_pattern(line)
      ERROR_PATTERNS.each do |pattern|
        if match = line.match(pattern)
          return {
            class: match[1] || 'Error',
            message: match[2] || match[1] || line.strip
          }
        end
      end
      nil
    end

    def should_ignore?(error_class)
      return false if error_class.blank?
      
      IGNORE_PATTERNS.any? { |pattern| error_class.match?(pattern) }
    end

    def extract_timestamp(line)
      # Match Rails log format: "I, [2024-01-01T12:00:00.000000 #12345]"
      if match = line.match(/\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+)/)
        Time.parse(match[1]) rescue nil
      end
    end

    def generate_signature(error_class, error_message, stack_trace)
      first_app_frame = stack_trace.to_s.lines.find { |l| l.include?('app/') || l.include?('lib/') }
      normalized_message = error_message.to_s.gsub(/\d+/, 'N').gsub(/'[^']*'/, "'...'")
      content = "#{error_class}|#{normalized_message}|#{first_app_frame}"
      Digest::SHA256.hexdigest(content)[0..16]
    end

    def extract_source_location(stack_trace)
      return [nil, nil] if stack_trace.blank?
      
      # Find first app/ or lib/ frame in stack trace
      stack_trace.to_s.lines.each do |line|
        next unless line.include?('app/') || line.include?('lib/')
        
        # Match file:line format
        match = line.match(/([a-zA-Z0-9_\/\-\.]+):(\d+)/)
        if match
          file = match[1].gsub(Rails.root.to_s + '/', '')
          line_num = match[2].to_i
          return [file, line_num]
        end
      end
      
      [nil, nil]
    end

    def determine_priority(error, count)
      # Critical errors
      return 'critical' if error[:error_class].to_s.match?(/Security|Auth|Payment|Data/)
      return 'critical' if count >= 50
      
      # High priority
      return 'high' if error[:error_class].to_s.match?(/Database|Connection|Timeout/)
      return 'high' if count >= 20
      
      # Medium priority
      return 'medium' if count >= 5
      
      'low'
    end

    def build_ticket_description(errors)
      first = errors.first
      count = errors.count
      
      # Use plain text format since simple_format doesn't render markdown
      <<~DESC
        AUTOMATICALLY DETECTED ERROR

        Error Class: #{first[:error_class]}
        Message: #{first[:error_message]}
        Occurrences: #{count} in the last hour

        TIMELINE
        • First occurrence: #{errors.min_by { |e| e[:occurred_at] }[:occurred_at]}
        • Last occurrence: #{errors.max_by { |e| e[:occurred_at] }[:occurred_at]}

        This ticket was automatically created by the Platform Evolution Engine.
        Stack trace is available in the Error Information section below.
      DESC
    end
  end
end

