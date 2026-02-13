class AgentPluginsController < ApplicationController
  include Authorizable
  before_action :authenticate_user!
  layout 'customer_admin'
  before_action :set_agent, only: [:show, :edit, :update, :destroy]
  before_action :authorize_destroy!, only: [:destroy]

  def index
    @my_agents = AgentPlugin.where(entity: current_entity).order(created_at: :desc)
    @system_agents = AgentPlugin.system_wide.active
    
    # Count custom skills (imported SKILL.md files)
    @skills_count = @my_agents.select { |a| a.configuration&.dig('skill_format') == 'claude_skill_md' }.count
    
    # Load built-in skills from SkillLibraryService
    @builtin_skills = begin
      SkillLibraryService::INTEGRATION_SKILLS.to_a
    rescue NameError, StandardError => e
      Rails.logger.warn "[AgentPlugins] Could not load built-in skills: #{e.message}"
      []
    end
    
    @builtin_skills_count = @builtin_skills.size
  end

  def show
  end

  def new
    @agent = AgentPlugin.new
  end

  def create
    @agent = AgentPlugin.new(agent_params)
    @agent.entity = current_entity
    @agent.status = 'draft'
    
    if @agent.save
      redirect_to agent_plugin_path(@agent), notice: 'Agent created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @agent.update(agent_params)
      respond_to do |format|
        format.html { redirect_to agent_plugin_path(@agent), notice: 'Agent updated successfully.' }
        format.json { render json: { success: true, status: @agent.status } }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @agent.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @agent.destroy
    respond_to do |format|
      format.html { redirect_to agent_plugins_path, notice: 'Agent deleted successfully.' }
      format.json { render json: { success: true } }
    end
  end

  # Import a Claude SKILL.md file
  def import
    # Show the import form
  end

  def import_skill
    importer = SkillFileImporterService.new(entity: current_entity, user: current_user)
    
    result = if params[:skill_url].present?
      importer.import_from_url(params[:skill_url])
    elsif params[:skill_content].present?
      importer.import_from_content(params[:skill_content], source: 'paste')
    elsif params[:skill_file].present?
      content = params[:skill_file].read
      importer.import_from_content(content, source: params[:skill_file].original_filename)
    else
      SkillFileImporterService::Result.new(success: false, errors: ['Please provide a skill file, URL, or paste content'])
    end

    if result.success
      redirect_to agent_plugin_path(result.agent_plugin), notice: "Skill '#{result.agent_plugin.name}' imported successfully! Review the configuration and activate when ready."
    else
      flash.now[:alert] = result.errors.join(', ')
      render :import, status: :unprocessable_entity
    end
  end

  private

  def set_agent
    @agent = AgentPlugin.where(entity: current_entity).find(params[:id])
  end

  def agent_params
    params.require(:agent_plugin).permit(:name, :description, :role, :system_prompt, :status)
  end
end

