# frozen_string_literal: true

module Workflows
  module Executors
    # ═══════════════════════════════════════════════════════════════
    # ACTION EXECUTORS
    # These do things - send emails, create records, make HTTP calls
    # ═══════════════════════════════════════════════════════════════

    # EmailActionExecutor - Sends emails
    class EmailActionExecutor < BaseExecutor
      def execute
        log_info "Sending email"

        to = interpolate(get_value('to') || config[:to])
        subject = interpolate(config[:subject_template] || config[:subject] || 'Workflow Notification')
        body = interpolate(config[:body_template] || config[:body] || '')

        return failure("Email recipient is required") if to.blank?

        begin
          # Use existing email sending infrastructure
          if config[:template_id].present?
            # Template-based email
            template = EmailTemplate.find_by(id: config[:template_id], entity: entity)
            return failure("Email template not found") unless template
            
            # Render template with context
            rendered_subject = template.render_subject(inputs.merge(context))
            rendered_body = template.render_body(inputs.merge(context))
            
            send_email(to, rendered_subject, rendered_body, html: config[:html] != false)
          else
            # Direct email
            send_email(to, subject, body, html: config[:html] != false)
          end

          success(
            sent: true,
            to: to,
            subject: subject,
            sent_at: Time.current.iso8601
          )
        rescue => e
          log_error "Email send failed: #{e.message}"
          failure("Failed to send email: #{e.message}")
        end
      end

      private

      def send_email(to, subject, body, html: true)
        # Queue email for delivery
        WorkflowMailer.workflow_email(
          to: to,
          subject: subject,
          body: body,
          html: html,
          entity_id: entity.id
        ).deliver_later
      end
    end

    # CreateRecordExecutor - Creates records in app modules
    class CreateRecordExecutor < BaseExecutor
      def execute
        log_info "Creating record"

        app_module_id = config[:app_module_id]
        return failure("App module ID is required") if app_module_id.blank?

        app_module = AppModule.find_by(id: app_module_id, entity: entity)
        return failure("App module not found") unless app_module

        # Build record data from field mapping or direct input
        record_data = build_record_data(app_module)

        begin
          # Use the dynamic record service
          result = DynamicRecordService.new(app_module, user: user).create(record_data)

          if result[:success]
            success(
              record: result[:record],
              id: result[:record][:id],
              created: true
            )
          else
            failure("Failed to create record: #{result[:error]}")
          end
        rescue => e
          log_error "Record creation failed: #{e.message}"
          failure("Failed to create record: #{e.message}")
        end
      end

      private

      def build_record_data(app_module)
        data = {}

        if config[:field_mapping].present?
          # Map input fields to module fields
          config[:field_mapping].each do |target_field, source_path|
            value = resolve_path(source_path) || interpolate(source_path)
            data[target_field] = value if value.present?
          end
        end

        # Apply default values
        if config[:default_values].present?
          config[:default_values].each do |field, value|
            data[field] ||= interpolate(value)
          end
        end

        # Merge any direct data input
        if inputs[:data].present?
          data = inputs[:data].merge(data)
        end

        data
      end
    end

    # UpdateRecordExecutor - Updates records in app modules
    class UpdateRecordExecutor < BaseExecutor
      def execute
        log_info "Updating record"

        app_module_id = config[:app_module_id]
        record_id = get_value('record_id') || inputs[:id]

        return failure("App module ID is required") if app_module_id.blank?
        return failure("Record ID is required") if record_id.blank?

        app_module = AppModule.find_by(id: app_module_id, entity: entity)
        return failure("App module not found") unless app_module

        # Build update data
        update_data = build_update_data

        begin
          result = DynamicRecordService.new(app_module, user: user).update(record_id, update_data)

          if result[:success]
            success(
              record: result[:record],
              changes: update_data,
              updated: true
            )
          else
            failure("Failed to update record: #{result[:error]}")
          end
        rescue => e
          log_error "Record update failed: #{e.message}"
          failure("Failed to update record: #{e.message}")
        end
      end

      private

      def build_update_data
        data = {}

        if config[:field_mapping].present?
          config[:field_mapping].each do |target_field, source_path|
            value = resolve_path(source_path) || interpolate(source_path)
            data[target_field] = value if value.present?
          end
        end

        if inputs[:data].present?
          data = inputs[:data].merge(data)
        end

        data
      end
    end

    # HttpRequestExecutor - Makes HTTP requests
    class HttpRequestExecutor < BaseExecutor
      def execute
        log_info "Making HTTP request"

        method = config[:method]&.upcase || 'GET'
        url = interpolate(config[:url_template] || get_value('url'))
        
        return failure("URL is required") if url.blank?

        # Build headers
        headers = (config[:headers] || {}).transform_values { |v| interpolate(v) }
        headers['Content-Type'] ||= 'application/json'

        # Build body
        body = nil
        if %w[POST PUT PATCH].include?(method)
          body = if config[:body_template].present?
            interpolate(config[:body_template])
          elsif inputs[:body].present?
            inputs[:body].is_a?(Hash) ? inputs[:body].to_json : inputs[:body]
          end
        end

        timeout = config[:timeout_seconds] || 30

        begin
          response = make_request(method, url, headers, body, timeout)

          success(
            response: parse_response(response),
            status: response.code.to_i,
            headers: response.to_hash
          )
        rescue Net::OpenTimeout, Net::ReadTimeout
          failure("Request timed out after #{timeout} seconds")
        rescue => e
          log_error "HTTP request failed: #{e.message}"
          failure("HTTP request failed: #{e.message}")
        end
      end

      private

      def make_request(method, url, headers, body, timeout)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = timeout
        http.read_timeout = timeout

        request = case method
        when 'GET'
          Net::HTTP::Get.new(uri.request_uri)
        when 'POST'
          Net::HTTP::Post.new(uri.request_uri)
        when 'PUT'
          Net::HTTP::Put.new(uri.request_uri)
        when 'PATCH'
          Net::HTTP::Patch.new(uri.request_uri)
        when 'DELETE'
          Net::HTTP::Delete.new(uri.request_uri)
        else
          raise "Unsupported HTTP method: #{method}"
        end

        headers.each { |k, v| request[k] = v }
        request.body = body if body

        http.request(request)
      end

      def parse_response(response)
        body = response.body
        return nil if body.blank?

        begin
          JSON.parse(body)
        rescue JSON::ParserError
          body
        end
      end
    end

    # DelayExecutor - Pauses workflow execution
    class DelayExecutor < BaseExecutor
      def execute
        log_info "Processing delay"

        delay_type = config[:delay_type] || 'fixed'
        
        case delay_type
        when 'fixed'
          delay_minutes = config[:delay_minutes] || 0
          if delay_minutes > 0
            # Schedule continuation
            resume_at = Time.current + delay_minutes.minutes
            schedule_resume(resume_at)
            
            success(
              delayed: true,
              delay_minutes: delay_minutes,
              resume_at: resume_at.iso8601
            )
          else
            success(delayed: false, resumed_at: Time.current.iso8601)
          end
        when 'until_time'
          resume_at = Time.parse(config[:delay_until])
          schedule_resume(resume_at)
          
          success(
            delayed: true,
            resume_at: resume_at.iso8601
          )
        else
          success(delayed: false, resumed_at: Time.current.iso8601)
        end
      end

      private

      def schedule_resume(resume_at)
        Workflows::ResumeJob.set(wait_until: resume_at).perform_later(
          execution.id,
          step['step_id']
        )
      end
    end
  end
end
