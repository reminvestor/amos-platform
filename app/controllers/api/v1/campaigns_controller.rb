# frozen_string_literal: true

module Api
  module V1
    class CampaignsController < BaseController
      before_action :set_campaign, only: [:show, :update, :destroy, :pause, :resume]

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
        @campaign = current_entity.campaigns.build(campaign_params)
        @campaign.user = current_user

        if @campaign.save
          render json: campaign_json(@campaign), status: :created
        else
          render json: { errors: @campaign.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
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

      private

      def set_campaign
        @campaign = current_entity.campaigns.includes(:contact_groups, :email_deliveries).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { message: "Campaign not found" }, status: :not_found
      end

      def campaign_params
        params.permit(:name, :subject, :content, :status, :scheduled_at)
      end

      # Use mobile-friendly field names
      def campaign_json(campaign)
        {
          id: campaign.id,
          name: campaign.name,
          subject: campaign.subject,
          status: campaign.status,
          contact_count: campaign.respond_to?(:contact_count) ? campaign.contact_count : campaign.contact_groups.sum(&:contacts_count),
          sent_count: campaign.sent_count || 0,
          open_rate: campaign.open_rate,
          click_rate: campaign.click_rate,
          scheduled_at: campaign.scheduled_at,
          created_at: campaign.created_at,
          updated_at: campaign.updated_at
        }
      end

      def campaign_detail_json(campaign)
        campaign_json(campaign).merge(
          content: campaign.content,
          contact_groups: campaign.contact_groups.map { |g| { id: g.id, name: g.name } },
          deliveries_count: campaign.email_deliveries.count,
          opens_count: campaign.email_deliveries.where.not(opened_at: nil).count,
          clicks_count: campaign.email_deliveries.where.not(clicked_at: nil).count
        )
      end
    end
  end
end
