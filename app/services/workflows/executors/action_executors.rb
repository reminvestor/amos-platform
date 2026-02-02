# frozen_string_literal: true

module Workflows
  module Executors
    # ═══════════════════════════════════════════════════════════════
    # ACTION EXECUTORS
    # These do things - send emails, create records, make HTTP calls
    # ═══════════════════════════════════════════════════════════════
    module ActionExecutors
      # Module wrapper for Zeitwerk compatibility
      # Individual executor classes are defined below
    end

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

    # EnrollInSequenceExecutor - Enrolls contacts in email sequences
    class EnrollInSequenceExecutor < BaseExecutor
      def execute
        log_info "Enrolling contact in email sequence"

        sequence_id = get_value('email_sequence_id') || config[:email_sequence_id]
        contact_id = get_value('contact_id') || inputs[:contact_id]

        return failure("Email sequence ID is required") if sequence_id.blank?
        return failure("Contact ID is required") if contact_id.blank?

        # Find sequence and contact
        sequence = entity.email_sequences.find_by(id: sequence_id)
        return failure("Email sequence not found: #{sequence_id}") unless sequence

        contact = entity.contacts.find_by(id: contact_id)
        return failure("Contact not found: #{contact_id}") unless contact

        # Check if already enrolled
        existing = sequence.sequence_enrollments.find_by(contact_id: contact.id)
        if existing
          return success(
            enrolled: false,
            already_enrolled: true,
            enrollment_id: existing.id,
            enrollment_status: existing.status,
            message: "Contact is already enrolled in this sequence"
          )
        end

        begin
          # Create enrollment
          enrollment = sequence.sequence_enrollments.create!(
            contact: contact,
            entity: entity,
            status: sequence.status == 'active' ? 'active' : 'pending',
            current_step_number: 0
          )

          # If sequence is active, set up first email timing
          if sequence.status == 'active'
            first_step = sequence.sequence_steps.ordered.first
            if first_step
              enrollment.update!(
                current_step_number: first_step.step_number,
                started_at: Time.current,
                next_send_at: Time.current + first_step.delay_hours.hours
              )
            end
          end

          # Update sequence counts
          sequence.update_enrollment_counts

          success(
            enrolled: true,
            enrollment_id: enrollment.id,
            enrollment_status: enrollment.status,
            sequence_name: sequence.name,
            contact_email: contact.email
          )
        rescue ActiveRecord::RecordInvalid => e
          failure("Failed to enroll contact: #{e.message}")
        rescue => e
          log_error "Enrollment failed: #{e.message}"
          failure("Failed to enroll contact: #{e.message}")
        end
      end
    end

    # UnenrollFromSequenceExecutor - Removes contacts from email sequences
    class UnenrollFromSequenceExecutor < BaseExecutor
      def execute
        log_info "Unenrolling contact from email sequence"

        sequence_id = get_value('email_sequence_id') || config[:email_sequence_id]
        contact_id = get_value('contact_id') || inputs[:contact_id]
        reason = config[:reason] || 'workflow_triggered'

        return failure("Email sequence ID is required") if sequence_id.blank?
        return failure("Contact ID is required") if contact_id.blank?

        # Find enrollment
        enrollment = SequenceEnrollment.joins(:email_sequence)
          .where(email_sequences: { entity_id: entity.id, id: sequence_id })
          .find_by(contact_id: contact_id)

        unless enrollment
          return success(
            unenrolled: false,
            not_enrolled: true,
            message: "Contact was not enrolled in this sequence"
          )
        end

        begin
          enrollment.cancel!
          enrollment.email_sequence.update_enrollment_counts

          success(
            unenrolled: true,
            enrollment_id: enrollment.id,
            previous_status: enrollment.status_before_last_save,
            reason: reason
          )
        rescue => e
          log_error "Unenrollment failed: #{e.message}"
          failure("Failed to unenroll contact: #{e.message}")
        end
      end
    end
  end
end
