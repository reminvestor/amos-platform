# frozen_string_literal: true

module Api
  module V1
    class LandingPagesController < BaseController
      before_action :set_landing_page, only: [:show, :update, :destroy, :publish, :unpublish]

      def index
        @landing_pages = current_entity.landing_pages
                                       .includes(:landing_page_submissions)
                                       .order(created_at: :desc)
                                       .page(params[:page] || 1)
                                       .per(params[:per_page] || 20)

        if params[:search].present?
          @landing_pages = @landing_pages.where("title ILIKE ?", "%#{params[:search]}%")
        end

        if params[:status].present?
          @landing_pages = @landing_pages.where(status: params[:status])
        end

        render json: {
          data: @landing_pages.map { |lp| landing_page_json(lp) },
          pagination: pagination_json(@landing_pages)
        }
      end

      def show
        render json: landing_page_detail_json(@landing_page)
      end

      def create
        @landing_page = current_entity.landing_pages.build(landing_page_params)
        @landing_page.user = current_user

        if @landing_page.save
          render json: landing_page_json(@landing_page), status: :created
        else
          render json: { errors: @landing_page.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @landing_page.update(landing_page_params)
          render json: landing_page_json(@landing_page)
        else
          render json: { errors: @landing_page.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @landing_page.destroy
        head :no_content
      end

      def publish
        if @landing_page.update(status: "published")
          render json: landing_page_json(@landing_page)
        else
          render json: { errors: @landing_page.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def unpublish
        if @landing_page.update(status: "draft")
          render json: landing_page_json(@landing_page)
        else
          render json: { errors: @landing_page.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_landing_page
        @landing_page = current_entity.landing_pages.includes(:landing_page_submissions).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { message: "Landing page not found" }, status: :not_found
      end

      def landing_page_params
        params.permit(:title, :slug, :content, :status, :meta_title, :meta_description)
      end

      # Use mobile-friendly field names
      def landing_page_json(landing_page)
        {
          id: landing_page.id,
          title: landing_page.title,
          slug: landing_page.slug,
          status: landing_page.status,
          view_count: landing_page.metadata&.dig("views_count") || 0,
          submission_count: landing_page.landing_page_submissions&.count || 0,
          unread_submissions_count: landing_page.landing_page_submissions&.where(status: 'pending')&.count || 0,
          published_at: landing_page.status == "published" ? landing_page.updated_at : nil,
          created_at: landing_page.created_at,
          updated_at: landing_page.updated_at
        }
      end

      def landing_page_detail_json(landing_page)
        landing_page_json(landing_page).merge(
          content: landing_page.html_content,
          description: landing_page.description,
          meta_title: landing_page.metadata&.dig("meta_title"),
          meta_description: landing_page.metadata&.dig("meta_description")
        )
      end
    end
  end
end
