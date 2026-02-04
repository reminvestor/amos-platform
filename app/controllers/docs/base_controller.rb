# frozen_string_literal: true

module Docs
  class BaseController < ApplicationController
    layout 'docs'
    
    # Docs portal is publicly accessible for reading
    skip_before_action :authenticate_user!, raise: false
    
    before_action :set_portal_context
    
    private
    
    def set_portal_context
      @portal = :docs
      @portal_name = "AMOS Docs"
      @portal_description = "Community-maintained documentation"
    end
    
    # Only editors can modify docs
    def require_editor!
      unless can_edit?
        redirect_to docs_root_path, alert: "You need to be logged in to edit documentation."
      end
    end
    
    def can_edit?
      return false unless user_signed_in?
      # Anyone logged in can edit (wiki-style)
      # Could add reputation requirements later
      true
    end
    helper_method :can_edit?
    
    def current_contributor
      return nil unless user_signed_in?
      @current_contributor ||= {
        id: current_user.id,
        name: current_user.full_name || current_user.email.split('@').first,
        contributions: DocPage.where(last_edited_by: current_user).count
      }
    end
    helper_method :current_contributor
  end
end
