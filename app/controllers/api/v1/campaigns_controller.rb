# frozen_string_literal: true

module Api
  module V1
    class CampaignsController < BaseController
      before_action :set_campaign, only: [:show, :update, :destroy, :pause, :resume, :send_now, :schedule, :send_test, :stop]

      def index
        @campaigns = current_entity.campaigns
                                   .includes(:contact_groups)
                                   .order(created_at: :desc)
                                   .page(params[:page] || 1)
                                   .per(params[:per_page] || 20)

        if params[:search].present?
          @campaigns = @campaigns.where("name ILIKE ?", "%#{params[:search]}%")
        end

        if params[:status].present?
          @campaigns = @campaigns.where(status: params[:status])
        end

        render json: {
          data: @campaigns.map { |c| campaign_json(c) },
          pagination: pagination_json(@campaigns)
        }
      end

      def show
        render json: campaign_detail_json(@campaign)
      end

      def create
        @campaign = current_entity.campaigns.build(core_campaign_params)
        @campaign.user = current_user

        # Create email template if subject or content provided
        if params[:subject].present?
          template = current_entity.email_templates.build(
            user: current_user,
            name: "Template for #{params[:name]}",
            subject: params[:subject],
            body: params[:content] || "<p>Email content goes here</p>"
          )

          if template.save
            @campaign.email_template = template
          else
            render json: { errors: template.errors.full_messages }, status: :unprocessable_entity
            return
          end
        end

        if @campaign.save
          render json: campaign_json(@campaign), status: :created
        else
          render json: { errors: @campaign.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        # Update email template if subject or content provided
        if params[:subject].present? || params[:content].present?
          if @campaign.email_template.present?
            template_updates = {}
            template_updates[:subject] = params[:subject] if params[:subject].present?
            template_updates[:body] = params[:content] if params[:content].present?
            @campaign.email_template.update(template_updates)
          elsif params[:subject].present?
            # Create new template if none exists
            template = current_entity.email_templates.create(
              user: current_user,
              name: "Template for #{@campaign.name}",
              subject: params[:subject],
              body: params[:content] || "<p>Email content goes here</p>"
            )
            @campaign.email_template = template
          end
        end

        if @campaign.update(campaign_params)
          render json: campaign_json(@campaign)
        else
          render json: { errors: @campaign.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @campaign.destroy
        head :no_content
      end

      def pause
        unless @campaign.status == "in_progress"
          render json: { message: "Only in-progress campaigns can be paused" }, status: :unprocessable_entity
          return
        end

        if @campaign.update(status: "paused")
          render json: campaign_json(@campaign)
        else
          render json: { errors: @campaign.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def resume
        unless @campaign.status == "paused"
          render json: { message: "Only paused campaigns can be resumed" }, status: :unprocessable_entity
          return
        end

        if @campaign.update(status: "in_progress")
          render json: campaign_json(@campaign)
        else
          render json: { errors: @campaign.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def send_now
        unless @campaign.status == "draft" || @campaign.status == "scheduled"
          render json: { message: "Only draft or scheduled campaigns can be sent" }, status: :unprocessable_entity
          return
        end

        if @campaign.email_template.blank?
          render json: { message: "Cannot send campaign: No email template selected" }, status: :unprocessable_entity
          return
        end

        if @campaign.contact_groups.empty?
          render json: { message: "Cannot send campaign: No contact groups selected" }, status: :unprocessable_entity
          return
        end

        begin
          service = CampaignService.new(@campaign)
          service.start_campaign
          render json: campaign_json(@campaign.reload).merge(message: "Campaign started successfully!")
        rescue => e
          Rails.logger.error("Campaign send error: #{e.message}")
          render json: { message: "Error sending campaign: #{e.message}" }, status: :unprocessable_entity
        end
      end

      def schedule
        unless @campaign.status == "draft"
          render json: { message: "Only draft campaigns can be scheduled" }, status: :unprocessable_entity
          return
        end

        scheduled_time = params[:scheduled_at].present? ? DateTime.parse(params[:scheduled_at]) : nil

        unless scheduled_time
          render json: { message: "scheduled_at is required" }, status: :unprocessable_entity
          return
        end

        if scheduled_time < Time.current
          render json: { message: "Scheduled time must be in the future" }, status: :unprocessable_entity
          return
        end

        begin
          service = CampaignService.new(@campaign)
          service.schedule_campaign(scheduled_time)
          render json: campaign_json(@campaign.reload).merge(
            message: "Campaign scheduled for #{scheduled_time.strftime('%b %d, %Y at %I:%M %p')}"
          )
        rescue => e
          Rails.logger.error("Campaign scheduling error: #{e.message}")
          render json: { message: "Error scheduling campaign: #{e.message}" }, status: :unprocessable_entity
        end
      end

      def send_test
        email = params[:email]

        unless email.present?
          render json: { message: "Test email address is required" }, status: :unprocessable_entity
          return
        end

        unless @campaign.email_template.present?
          render json: { message: "Cannot send test: No email template selected" }, status: :unprocessable_entity
          return
        end

        begin
          CampaignMailer.test_campaign_email(@campaign, email).deliver_now
          render json: { message: "Test email sent to #{email}" }
        rescue => e
          Rails.logger.error("Test email error: #{e.message}")
          render json: { message: "Error sending test email: #{e.message}" }, status: :unprocessable_entity
        end
      end

      def stop
        unless ["in_progress", "scheduled"].include?(@campaign.status)
          render json: { message: "Only in-progress or scheduled campaigns can be stopped" }, status: :unprocessable_entity
          return
        end

        begin
          service = CampaignService.new(@campaign)
          service.stop_campaign
          render json: campaign_json(@campaign.reload).merge(message: "Campaign stopped")
        rescue => e
          Rails.logger.error("Campaign stop error: #{e.message}")
          render json: { message: "Error stopping campaign: #{e.message}" }, status: :unprocessable_entity
        end
      end

      private

      def set_campaign
        @campaign = current_entity.campaigns.includes(:contact_groups, :email_deliveries).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { message: "Campaign not found" }, status: :not_found
      end

      def campaign_params
        params.permit(:name, :description, :status, :scheduled_at)
      end

      def core_campaign_params
        params.permit(:name, :description, :status, :scheduled_at)
      end

      # Use mobile-friendly field names
      def campaign_json(campaign)
        deliveries = campaign.respond_to?(:email_deliveries) ? campaign.email_deliveries : []
        deliveries_count = deliveries.respond_to?(:count) ? deliveries.count : 0
        opens_count = deliveries.respond_to?(:where) ? deliveries.where.not(opened_at: nil).count : 0
        clicks_count = deliveries.respond_to?(:where) ? deliveries.where.not(clicked_at: nil).count : 0

        {
          id: campaign.id,
          name: campaign.name,
          subject: campaign.email_template&.subject || campaign.name,
          status: campaign.status,
          contact_count: campaign.contact_groups.sum { |g| g.contacts.count },
          sent_count: deliveries_count,
          open_rate: deliveries_count > 0 ? (opens_count.to_f / deliveries_count * 100).round(1) : nil,
          click_rate: deliveries_count > 0 ? (clicks_count.to_f / deliveries_count * 100).round(1) : nil,
          scheduled_at: campaign.scheduled_at,
          created_at: campaign.created_at,
          updated_at: campaign.updated_at
        }
      end

      def campaign_detail_json(campaign)
        deliveries = campaign.respond_to?(:email_deliveries) ? campaign.email_deliveries : []
        campaign_json(campaign).merge(
          content: campaign.email_template&.body,
          description: campaign.description,
          contact_groups: campaign.contact_groups.map { |g| { id: g.id, name: g.name } },
          deliveries_count: deliveries.respond_to?(:count) ? deliveries.count : 0,
          opens_count: deliveries.respond_to?(:where) ? deliveries.where.not(opened_at: nil).count : 0,
          clicks_count: deliveries.respond_to?(:where) ? deliveries.where.not(clicked_at: nil).count : 0
        )
      end
    end
  end
end
