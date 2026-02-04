# frozen_string_literal: true

module Docs
  class ContributorsController < Docs::BaseController
    def index
      @contributors = User.joins(:doc_pages_edited)
                          .select('users.*, COUNT(doc_pages.id) as contribution_count')
                          .group('users.id')
                          .order('contribution_count DESC')
                          .limit(50)
    rescue => e
      Rails.logger.error "Contributors error: #{e.message}"
      @contributors = []
    end
    
    def show
      @contributor = User.find(params[:id])
      @recent_contributions = DocPage.where(last_edited_by: @contributor)
                                     .order(updated_at: :desc)
                                     .limit(20)
    rescue ActiveRecord::RecordNotFound
      redirect_to docs_contributors_path, alert: "Contributor not found."
    end
  end
end
