# frozen_string_literal: true

module Build
  class BaseController < ApplicationController
    layout 'build'

    # Build portal is publicly accessible
    skip_before_action :authenticate_user!, raise: false
    skip_before_action :check_token_balance, raise: false
    skip_before_action :check_onboarding_status, raise: false

    before_action :set_portal_context

    private

    def set_portal_context
      @portal = :build
      @portal_name = "Amos Build"
      @portal_description = "Contribute to Amos Labs and earn rewards"
    end

    def require_authentication!
      unless current_user
        redirect_to build_root_path, alert: "Please sign in to perform this action."
      end
    end

    # Override current_entity for build portal — not entity-scoped
    def current_entity
      current_user&.entity
    end
  end
end
