class BusinessProfilesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_business_profile

  def edit
    # Show the edit form
  end

  def update
    respond_to do |format|
      if @business_profile.update(business_profile_params)
        format.html { redirect_to edit_business_profile_path, notice: "Business profile was successfully updated." }
        format.json { render json: { success: true, message: "Business profile updated successfully" }, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @business_profile.errors }, status: :unprocessable_entity }
      end
    end
  end

  def add_knowledge
    section_name = params[:section_name]
    content = params[:content]

    if section_name.present? && content.present?
      @business_profile.add_knowledge_section(section_name, content)
      redirect_to edit_business_profile_path, notice: "Knowledge base was successfully updated."
    else
      redirect_to edit_business_profile_path, alert: "Section name and content are required."
    end
  end

  private

  def set_business_profile
    @business_profile = current_user.ensure_business_profile
  end

  def business_profile_params
    params.require(:business_profile).permit(
      :name, :industry, :description, :founded_year,
      :website, :values, :target_audience, :tone_of_voice
    )
  end
end
