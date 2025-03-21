class AiContentController < ApplicationController
  before_action :authenticate_user!
  
  def new
    @email_templates = current_user.email_templates
    @contact_groups = current_user.contact_groups
  end
  
  def generate
    service = AiContentService.new
    
    generation_params = {
      audience: params[:audience],
      purpose: params[:purpose],
      tone: params[:tone],
      product: params[:product],
      length: params[:length],
      specific_points: params[:specific_points].to_s.split("\n").reject(&:blank?)
    }
    
    @generated_content = service.generate_email_content(generation_params)
    
    # If template_id provided, update that template
    if params[:template_id].present? && !params[:template_id].empty?
      template = current_user.email_templates.find_by(id: params[:template_id])
      if template
        template.update(body: @generated_content)
        flash[:notice] = "Email template updated with AI-generated content"
        redirect_to email_template_path(template)
        return
      end
    end
    
    # Otherwise, create a new template if requested
    if params[:create_template] == "1"
      template = current_user.email_templates.create(
        name: params[:template_name].presence || "AI Generated Template",
        subject: extract_subject(@generated_content),
        body: @generated_content
      )
      flash[:notice] = "New email template created with AI-generated content"
      redirect_to email_template_path(template)
      return
    end
    
    # If not saving to a template, just render the result
    render :result
  end
  
  def improve
    @template = current_user.email_templates.find(params[:template_id])
    
    # Mock stats for now, would come from actual analytics in production
    stats = {
      open_rate: params[:open_rate] || 15,
      click_rate: params[:click_rate] || 2.5
    }
    
    service = AiContentService.new
    @improved_content = service.improve_content(
      @template.body,
      stats,
      params[:audience] || "general subscribers"
    )
    
    if params[:update_template] == "1"
      @template.update(body: @improved_content)
      flash[:notice] = "Template updated with improved content"
      redirect_to email_template_path(@template)
    else
      render :improve_result
    end
  end
  
  def analyze_campaign
    @campaign = current_user.campaigns.find(params[:campaign_id])
    service = AiContentService.new
    @analysis = service.analyze_campaign_results(@campaign)
    
    render :analysis_result
  end
  
  private
  
  def extract_subject(content)
    # Try to extract subject line from HTML content
    # This is a simple version; could be improved with regex
    if content.include?("<subject>") && content.include?("</subject>")
      content.match(/<subject>(.*?)<\/subject>/)[1]
    elsif content.downcase.include?("subject:") 
      content.match(/subject:(.*?)($|\n)/i)[1].strip
    else
      "AI Generated Email"
    end
  rescue
    "AI Generated Email"
  end
end 