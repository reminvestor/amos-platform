# frozen_string_literal: true

module Api
  module V1
    class EmailTemplatesController < BaseController
      before_action :set_email_template, only: [:show, :update, :destroy]

      def index
        @t = current_entity.email_templates.order(created_at: :desc).page(params[:page] || 1).per(20)
        render json: { data: @t.map { |x| tj(x) }, pagination: pagination_json(@t) }
      end

      def show
        render json: td(@email_template)
      end

      def create
        @email_template = current_entity.email_templates.build(tp)
        @email_template.user = current_user
        @email_template.save ? render(json: tj(@email_template), status: :created) : render(json: { errors: @email_template.errors.full_messages }, status: :unprocessable_entity)
      end

      def update
        @email_template.update(tp) ? render(json: tj(@email_template)) : render(json: { errors: @email_template.errors.full_messages }, status: :unprocessable_entity)
      end

      def destroy
        @email_template.destroy
        head :no_content
      end

      private

      def set_email_template
        @email_template = current_entity.email_templates.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { message: "Email template not found" }, status: :not_found
      end

      def tp
        params.permit(:name, :subject, :body)
      end

      def tj(t)
        { id: t.id, name: t.name, subject: t.subject, created_at: t.created_at, updated_at: t.updated_at }
      end

      def td(t)
        tj(t).merge(body: t.body, campaigns_count: t.campaigns.count)
      end
    end
  end
end
