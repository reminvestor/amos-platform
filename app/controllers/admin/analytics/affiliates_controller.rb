class Admin::Analytics::AffiliatesController < Admin::BaseController
  def index
    @date_range = params[:date_range] || '30days'
    @analytics = AffiliateAnalyticsService.new(@date_range).generate_report

    respond_to do |format|
      format.html
      format.json { render json: @analytics }
    end
  end
end
