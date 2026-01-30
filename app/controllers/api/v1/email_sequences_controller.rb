# frozen_string_literal: true

module Api
  module V1
    class EmailSequencesController < Api::V1::BaseController
      before_action :set_email_sequence, only: [:show, :update, :destroy, :activate, :pause, :resume, :stats]

      # GET /api/v1/email_sequences
      def index
        @sequences = current_entity.email_sequences
          .includes(:sequence_steps, :contact_group)
          .order(created_at: :desc)

        render json: {
          success: true,
          sequences: @sequences.map { |s| serialize_sequence(s) },
          total: @sequences.count
        }
      end

      # GET /api/v1/email_sequences/dashboard
      def dashboard
        sequences = current_entity.email_sequences
        
        render json: {
          success: true,
          stats: {
            total: sequences.count,
            draft: sequences.draft.count,
            active: sequences.active.count,
            paused: sequences.paused.count,
            completed: sequences.completed.count,
            total_enrolled: sequences.sum(:enrolled_count),
            total_active_enrollments: sequences.sum(:active_count),
            total_completed_enrollments: sequences.sum(:completed_count)
          }
        }
      end

      # GET /api/v1/email_sequences/:id
      def show
        render json: {
          success: true,
          sequence: serialize_sequence(@sequence, include_steps: true, include_enrollments: true)
        }
      end

      # POST /api/v1/email_sequences
      def create
        @sequence = current_entity.email_sequences.new(email_sequence_params)

        if @sequence.save
          render json: {
            success: true,
            sequence: serialize_sequence(@sequence),
            message: "Email sequence created successfully"
          }, status: :created
        else
          render json: {
            success: false,
            errors: @sequence.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/email_sequences/:id
      def update
        if @sequence.update(email_sequence_params)
          render json: {
            success: true,
            sequence: serialize_sequence(@sequence),
            message: "Email sequence updated successfully"
          }
        else
          render json: {
            success: false,
            errors: @sequence.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/email_sequences/:id
      def destroy
        @sequence.destroy
        render json: {
          success: true,
          message: "Email sequence deleted successfully"
        }
      end

      # POST /api/v1/email_sequences/:id/activate
      def activate
        if @sequence.activate!
          render json: {
            success: true,
            sequence: serialize_sequence(@sequence),
            message: "Sequence activated! Emails will start sending based on the schedule."
          }
        else
          render json: {
            success: false,
            message: "Cannot activate sequence. Ensure it has at least one step and is in draft status."
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/email_sequences/:id/pause
      def pause
        if @sequence.pause!
          render json: {
            success: true,
            sequence: serialize_sequence(@sequence),
            message: "Sequence paused. No new emails will be sent."
          }
        else
          render json: {
            success: false,
            message: "Cannot pause this sequence."
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/email_sequences/:id/resume
      def resume
        if @sequence.resume!
          render json: {
            success: true,
            sequence: serialize_sequence(@sequence),
            message: "Sequence resumed! Emails will continue sending."
          }
        else
          render json: {
            success: false,
            message: "Cannot resume this sequence."
          }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/email_sequences/:id/stats
      def stats
        deliveries = @sequence.sequence_email_deliveries if @sequence.respond_to?(:sequence_email_deliveries)
        
        render json: {
          success: true,
          stats: {
            sequence_id: @sequence.id,
            name: @sequence.name,
            status: @sequence.status,
            step_count: @sequence.step_count,
            enrolled_count: @sequence.enrolled_count,
            active_count: @sequence.active_count,
            completed_count: @sequence.completed_count,
            completion_rate: @sequence.completion_rate,
            total_sent: @sequence.total_sent,
            total_opened: @sequence.total_opened,
            total_clicked: @sequence.total_clicked,
            open_rate: @sequence.open_rate,
            click_rate: @sequence.click_rate,
            steps: @sequence.sequence_steps.ordered.map do |step|
              {
                step_number: step.step_number,
                subject: step.effective_subject,
                delay_hours: step.delay_hours,
                sent_count: step.sent_count,
                opened_count: step.opened_count,
                clicked_count: step.clicked_count,
                open_rate: step.open_rate,
                click_rate: step.click_rate
              }
            end
          }
        }
      end

      private

      def set_email_sequence
        @sequence = current_entity.email_sequences.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: "Email sequence not found" }, status: :not_found
      end

      def email_sequence_params
        params.require(:email_sequence).permit(
          :name, :goal, :status, :contact_group_id, :metadata
        )
      end

      def serialize_sequence(sequence, include_steps: false, include_enrollments: false)
        data = {
          id: sequence.id,
          name: sequence.name,
          goal: sequence.goal,
          status: sequence.status,
          contact_group_id: sequence.contact_group_id,
          contact_group_name: sequence.contact_group&.name,
          step_count: sequence.step_count,
          enrolled_count: sequence.enrolled_count,
          active_count: sequence.active_count,
          completed_count: sequence.completed_count,
          completion_rate: sequence.completion_rate,
          open_rate: sequence.open_rate,
          click_rate: sequence.click_rate,
          created_at: sequence.created_at.iso8601,
          updated_at: sequence.updated_at.iso8601
        }

        if include_steps
          data[:steps] = sequence.sequence_steps.ordered.map do |step|
            {
              id: step.id,
              step_number: step.step_number,
              subject: step.effective_subject,
              body_preview: step.effective_body&.truncate(100),
              delay_hours: step.delay_hours,
              delay_in_days: step.delay_in_days,
              email_template_id: step.email_template_id,
              sent_count: step.sent_count,
              opened_count: step.opened_count,
              clicked_count: step.clicked_count,
              open_rate: step.open_rate,
              click_rate: step.click_rate
            }
          end
        end

        if include_enrollments
          data[:recent_enrollments] = sequence.sequence_enrollments.limit(10).map do |enrollment|
            {
              id: enrollment.id,
              contact_id: enrollment.contact_id,
              contact_email: enrollment.contact&.email,
              status: enrollment.status,
              current_step_number: enrollment.current_step_number,
              progress_percentage: enrollment.progress_percentage,
              enrolled_at: enrollment.enrolled_at&.iso8601,
              next_send_at: enrollment.next_send_at&.iso8601
            }
          end
        end

        data
      end
    end
  end
end
