module Api
  module V1
    class LandingPageSubmissionsController < Api::BaseController
      respond_to :json
      protect_from_forgery with: :null_session

      # Public endpoint - no authentication required for form submissions
      # Note: Api::BaseController already skips authentication

      def create
        begin
          Rails.logger.info("LANDING PAGE FORM SUBMISSION: Starting request processing")

          # Extract landing page from slug or ID
          landing_page = find_landing_page
          unless landing_page
            render json: {
              success: false,
              message: "Landing page not found"
            }, status: :not_found
            return
          end

          # Extract form data
          form_data = extract_form_data
          if form_data.empty?
            render json: {
              success: false,
              message: "No form data provided"
            }, status: :bad_request
            return
          end

          # Create submission record
          submission = create_submission(landing_page, form_data)

          if submission.persisted?
            Rails.logger.info("LANDING PAGE FORM SUBMISSION: Created submission #{submission.id}")

            render json: {
              success: true,
              message: "Thank you! Your submission has been received.",
              submission_id: submission.id
            }, status: :created
          else
            Rails.logger.error("LANDING PAGE FORM SUBMISSION: Failed to create submission - #{submission.errors.full_messages.join(', ')}")

            render json: {
              success: false,
              message: "There was an error processing your submission. Please try again.",
              errors: submission.errors.full_messages
            }, status: :unprocessable_entity
          end

        rescue => e
          Rails.logger.error("LANDING PAGE FORM SUBMISSION ERROR: #{e.class.name}: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))

          render json: {
            success: false,
            message: "An error occurred while processing your submission. Please try again."
          }, status: :internal_server_error
        end
      end

      # Show individual submission details
      def show
        # Scope to current user's landing pages first to prevent IDOR
        submission = LandingPageSubmission.joins(:landing_page)
                                          .where(landing_pages: { user_id: current_user.id })
                                          .find(params[:id])

        render json: {
          success: true,
          submission: submission_response(submission)
        }
      rescue ActiveRecord::RecordNotFound
        render json: {
          success: false,
          message: "Submission not found"
        }, status: :not_found
      end

      # Mark submission as processed
      def mark_processed
        submission = find_user_submission
        return unless submission

        submission.mark_as_processed!

        render json: {
          success: true,
          message: "Submission marked as processed",
          submission: submission_response(submission)
        }
      end

      # Mark submission as spam
      def spam
        submission = find_user_submission
        return unless submission

        submission.mark_as_spam!

        render json: {
          success: true,
          message: "Submission marked as spam",
          submission: submission_response(submission)
        }
      end

      # Export submissions as CSV
      def export
        landing_page_id = params[:landing_page_id]

        # Build query
        query = current_user.landing_pages
                           .joins(:landing_page_submissions)
                           .includes(landing_page_submissions: :contact)

        if landing_page_id.present?
          query = query.where(id: landing_page_id)
        end

        submissions = query.flat_map(&:landing_page_submissions)

        # Apply filters
        if params[:form_type].present?
          submissions = submissions.select { |s| s.form_type == params[:form_type] }
        end

        if params[:status].present?
          submissions = submissions.select { |s| s.status == params[:status] }
        end

        case params[:time_range]
        when "today"
          submissions = submissions.select { |s| s.submitted_at >= Date.current.beginning_of_day }
        when "week"
          submissions = submissions.select { |s| s.submitted_at >= 1.week.ago }
        when "month"
          submissions = submissions.select { |s| s.submitted_at >= 1.month.ago }
        end

        # Generate CSV
        csv_data = generate_submissions_csv(submissions)

        send_data csv_data,
                  filename: "form_submissions_#{Date.current.strftime('%Y%m%d')}.csv",
                  type: "text/csv"
      end

      # Authenticated endpoint for retrieving submissions
      def index
        landing_page = current_user.landing_pages.find(params[:landing_page_id])

        submissions = landing_page.landing_page_submissions
                                 .includes(:contact)
                                 .recent
                                 .limit(100)

        render json: {
          success: true,
          submissions: submissions.map { |s| submission_response(s) },
          total_count: landing_page.landing_page_submissions.count,
          conversion_rate: LandingPageSubmission.conversion_rate_for_page(landing_page.id)
        }
      rescue ActiveRecord::RecordNotFound
        render json: {
          success: false,
          message: "Landing page not found"
        }, status: :not_found
      end

      private

      def find_landing_page
        # Allow preview/test mode submissions for unpublished pages
        # This enables testing forms before publishing
        allow_unpublished = params[:preview] == "true" || params[:test] == "true"
        
        if params[:landing_page_slug].present?
          if allow_unpublished
            LandingPage.find_by(slug: params[:landing_page_slug])
          else
            LandingPage.published.find_by(slug: params[:landing_page_slug])
          end
        elsif params[:landing_page_id].present?
          if allow_unpublished
            LandingPage.find_by(id: params[:landing_page_id])
          else
            LandingPage.published.find_by(id: params[:landing_page_id])
          end
        else
          nil
        end
      end

      def extract_form_data
        # Get all form fields from params, excluding system fields
        excluded_keys = %w[
          controller action landing_page_id landing_page_slug
          authenticity_token commit utf8 _method
        ]

        form_data = params.except(*excluded_keys).to_unsafe_h

        # Handle nested form data if present
        if params[:form].present?
          form_data = form_data.merge(params[:form].to_unsafe_h)
        end

        # Clean up the data
        form_data.reject { |k, v| v.blank? }
      end

      def create_submission(landing_page, form_data)
        # Determine form type from data or default
        form_type = determine_form_type(form_data)

        # Extract UTM parameters
        utm_params = extract_utm_params

        # Create the submission
        landing_page.landing_page_submissions.create(
          form_type: form_type,
          submission_data: form_data,
          source_ip: request.remote_ip,
          user_agent: request.user_agent,
          session_id: request.session.id,
          referrer: request.referer,
          metadata: utm_params.merge(
            form_source: "dsl_generated",
            user_session: request.session.id
          )
        )
      end

      def determine_form_type(form_data)
        # Smart form type detection based on fields
        if form_data.key?("newsletter_signup") || form_data.key?("subscribe")
          "newsletter"
        elsif form_data.key?("demo_request") || form_data.key?("request_demo")
          "demo_request"
        elsif form_data.key?("quote_request") || form_data.key?("get_quote")
          "quote_request"
        elsif form_data.key?("consultation_booking") || form_data.key?("book_consultation")
          "consultation_booking"
        elsif form_data.key?("download") || form_data.key?("lead_magnet")
          "lead_magnet"
        elsif form_data.key?("event_registration") || form_data.key?("register")
          "event_registration"
        else
          "contact"  # Default form type
        end
      end

      def extract_utm_params
        {
          utm_source: params[:utm_source],
          utm_medium: params[:utm_medium],
          utm_campaign: params[:utm_campaign],
          utm_content: params[:utm_content],
          utm_term: params[:utm_term]
        }.compact
      end

      def find_user_submission
        # Scope to current user's landing pages first to prevent IDOR
        LandingPageSubmission.joins(:landing_page)
                             .where(landing_pages: { user_id: current_user.id })
                             .find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: {
          success: false,
          message: "Submission not found"
        }, status: :not_found
        nil
      end

      def generate_submissions_csv(submissions)
        require "csv"

        CSV.generate(headers: true) do |csv|
          # Headers
          csv << [
            "ID", "Landing Page", "Form Type", "Status", "Name", "Email", "Phone", "Company",
            "Message", "Submitted At", "Processed At", "Source IP", "Referrer",
            "UTM Source", "UTM Medium", "UTM Campaign"
          ]

          # Data rows
          submissions.each do |submission|
            csv << [
              submission.id,
              submission.landing_page.title,
              submission.form_type,
              submission.status,
              submission.full_name,
              submission.email,
              submission.phone,
              submission.company,
              submission.message,
              submission.submitted_at.strftime("%Y-%m-%d %H:%M:%S"),
              submission.processed_at&.strftime("%Y-%m-%d %H:%M:%S"),
              submission.source_ip,
              submission.referrer,
              submission.utm_source,
              submission.utm_medium,
              submission.utm_campaign
            ]
          end
        end
      end

      def submission_response(submission)
        {
          id: submission.id,
          form_type: submission.form_type,
          status: submission.status,
          submitted_at: submission.submitted_at,
          processed_at: submission.processed_at,
          contact_info: submission.contact_info,
          utm_params: submission.utm_params,
          source_ip: submission.source_ip,
          referrer: submission.referrer,
          submission_data: submission.submission_data,
          landing_page: {
            id: submission.landing_page.id,
            title: submission.landing_page.title,
            slug: submission.landing_page.slug
          }
        }
      end
    end
  end
end
