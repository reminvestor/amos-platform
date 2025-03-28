class MarketingController < ApplicationController
  skip_before_action :authenticate_user!
  layout 'marketing'
  
  def index
  end
  
  def features
  end
  
  def pricing
  end
  
  def about
  end
  
  def contact
  end
end
