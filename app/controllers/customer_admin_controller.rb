class CustomerAdminController < ApplicationController
  before_action :authenticate_user!
  layout 'customer_admin'
  
  private
  
  def set_current_admin
    # For compatibility with views that expect @current_admin
    @current_admin = current_user
  end
end
