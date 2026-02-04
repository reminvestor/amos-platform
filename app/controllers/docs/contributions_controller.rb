# frozen_string_literal: true

module Docs
  class ContributionsController < Docs::BaseController
    before_action :authenticate_user!
    
    def index
      @my_pages = DocPage.where(last_edited_by: current_user)
                         .order(updated_at: :desc)
                         .page(params[:page])
                         .per(20)
      @my_revisions = DocPageRevision.where(user: current_user)
                                     .order(created_at: :desc)
                                     .limit(20)
    rescue => e
      @my_pages = []
      @my_revisions = []
    end
  end
end
