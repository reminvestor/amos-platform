# frozen_string_literal: true

# HubController
#
# Controller for the Collaborative Intelligence Hub.
# The central communication hub where humans and AI agents collaborate.
#
class HubController < ApplicationController
  # Skip parent's authenticate_user! since we handle auth ourselves (supports mobile API)
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :check_token_balance, raise: false
  skip_before_action :check_onboarding_status, raise: false

  before_action :authenticate_user_or_api!
  before_action :set_entity
  before_action :set_thread, only: [:show_thread, :send_message, :mark_read, :fresh_start]

  # GET /hub
  # Main Hub view - shows channels, DMs, and activity
  def index
    @channels = @entity.team_channels.active.ordered
    @dm_threads = current_user.hub_threads
                              .where(entity: @entity, thread_type: HubThread::DM)
                              .active
                              .recent
                              .limit(20)
    
    @work_streams = HubThread.joins(:hub_participants)
                             .where(hub_participants: { participant: current_user })
                             .where(entity: @entity, thread_type: HubThread::WORK_STREAM)
                             .active
                             .recent
                             .limit(10)

    @unread_counts = calculate_unread_counts
    @presence_summary = HubPresence.entity_summary(@entity)
    
    # Default to general channel or first unread
    @active_thread = find_default_thread
  end

  # GET /hub/thread/:id
  def show_thread
    @messages = @thread.messages_for_participant(current_user)
                       .includes(:sender, :reply_to)
                       .limit(100)
    
    @participants = @thread.hub_participants.active.includes(:participant)
    
    # Mark as read
    participant = @thread.hub_participants.find_by(participant: current_user)
    participant&.mark_read!

    respond_to do |format|
      format.html { render partial: 'hub/thread', locals: { thread: @thread, messages: @messages } }
      format.json { render json: thread_json(@thread, @messages) }
    end
  end

  # POST /hub/thread/:id/messages
  def send_message
    # Extract canvas context if provided (for agent awareness)
    canvas_context = params[:canvas_context]&.to_unsafe_h
    
    message = @thread.add_message(
      sender: current_user,
      content: params[:content],
      message_type: params[:message_type] || 'text',
      reply_to_id: params[:reply_to_id],
      attachments: params[:attachments] || [],
      metadata: { canvas_context: canvas_context }.compact
    )
    
    # Store canvas context in thread for agent access
    if canvas_context.present?
      Rails.logger.info "🎨 [Hub] Canvas context provided: #{canvas_context}"
      # Store in message metadata for agent to access
      message.update(metadata: (message.metadata || {}).merge(canvas_context: canvas_context))
    end

    respond_to do |format|
      format.json { render json: { success: true, message: message.as_broadcast_json } }
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
    end
  end

  # POST /hub/thread/:id/mark_read
  def mark_read
    participant = @thread.hub_participants.find_by(participant: current_user)
    
    if params[:message_id]
      message = @thread.hub_messages.find(params[:message_id])
      participant&.mark_read_up_to!(message)
    else
      participant&.mark_read!
    end

    respond_to do |format|
      format.json { render json: { success: true, unread_count: participant&.unread_count || 0 } }
    end
  end

  # POST /hub/thread/:id/fresh_start
  # Clears working context for this thread but preserves memory
  # Works like Amos's fresh_start - updates context_access_from so old messages aren't shown
  def fresh_start
    participant = @thread.hub_participants.find_by(participant: current_user)
    
    unless participant
      return render json: { success: false, error: 'Not a participant' }, status: :forbidden
    end
    
    # Update context_access_from to now - messages before this won't be shown
    fresh_start_time = Time.current
    participant.update!(context_access_from: fresh_start_time)
    
    Rails.logger.info "🔄 [Hub] Fresh start for thread #{@thread.id}, user #{current_user.id} at #{fresh_start_time}"
    
    # Clear any running agent executions for this thread
    if @thread.thread_type == 'dm'
      agent_participant = @thread.hub_participants.where(participant_type: 'AgentPlugin').first
      if agent_participant&.participant
        # Cancel any running executions for this agent in this thread context
        AgentPluginExecution.where(
          agent_plugin: agent_participant.participant,
          user: current_user,
          status: ['running', 'waiting_for_input']
        ).where("input_context->>'hub_thread_id' = ?", @thread.id.to_s).each do |exec|
          exec.update!(status: 'cancelled')
          Rails.logger.info "🔄 [Hub] Cancelled execution #{exec.id} during fresh start"
        end
      end
    end
    
    respond_to do |format|
      format.json { 
        render json: { 
          success: true, 
          fresh_start_at: fresh_start_time.iso8601,
          message: "Fresh start! Memory preserved, context cleared."
        } 
      }
    end
  end

  # GET /hub/channels
  def channels
    @channels = @entity.team_channels.active.ordered.includes(:hub_threads)
    
    respond_to do |format|
      format.json { render json: @channels.map { |c| channel_json(c) } }
    end
  end

  # GET /hub/channel/:id
  def show_channel
    @channel = @entity.team_channels.find(params[:id])
    @thread = @channel.main_thread
    
    redirect_to hub_thread_path(@thread)
  end

  # POST /hub/channels
  def create_channel
    @channel = @entity.team_channels.create!(channel_params)

    respond_to do |format|
      format.json { render json: { success: true, channel: channel_json(@channel) } }
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
    end
  end

  # DELETE /hub/channels/:id
  def delete_channel
    @channel = @entity.team_channels.find(params[:id])

    # Don't allow deleting the default/general channel
    if @channel.channel_type == 'general' && @entity.team_channels.where(channel_type: 'general').count == 1
      return render json: { success: false, error: 'Cannot delete the default channel' }, status: :unprocessable_entity
    end

    @channel.destroy!

    respond_to do |format|
      format.json { render json: { success: true, message: 'Channel deleted' } }
    end
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: 'Channel not found' }, status: :not_found
  rescue => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  # GET /hub/channels/:id/messages
  def channel_messages
    @channel = @entity.team_channels.find(params[:id])
    @thread = @channel.main_thread || @channel.create_default_thread
    
    # Ensure user is a participant
    unless @thread.hub_participants.exists?(participant_type: 'User', participant_id: current_user.id)
      @thread.hub_participants.create!(
        participant: current_user,
        role: 'member',
        joined_at: Time.current
      )
    end
    
    @messages = @thread.hub_messages
                       .includes(:sender)
                       .order(created_at: :asc)
                       .limit(100)
    
    respond_to do |format|
      format.json do
        render json: {
          channel: channel_json(@channel),
          thread_id: @thread.id,
          messages: @messages.map { |m| message_json(m) }
        }
      end
    end
  end

  # POST /hub/channels/:id/messages
  def send_channel_message
    @channel = @entity.team_channels.find(params[:id])
    @thread = @channel.main_thread || @channel.create_default_thread

    # Ensure user is a participant (must happen before message creation due to validation)
    unless @thread.hub_participants.exists?(participant_type: 'User', participant_id: current_user.id)
      @thread.hub_participants.create!(
        participant: current_user,
        role: 'member',
        joined_at: Time.current
      )
    end

    message = @thread.hub_messages.create!(
      sender: current_user,
      content: params[:content],
      message_type: params[:message_type] || 'text'
    )
    
    # Update thread activity
    @thread.touch(:last_activity_at)
    @thread.increment!(:message_count)
    
    # Broadcast to channel subscribers
    HubChannel.broadcast_to_thread(@thread.id, {
      type: 'new_message',
      message: message_json(message)
    })
    
    respond_to do |format|
      format.json { render json: { success: true, message: message_json(message) } }
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
    end
  end

  # GET /hub/dms
  def dms
    @dm_threads = current_user.hub_threads
                              .where(entity: @entity, thread_type: HubThread::DM)
                              .active
                              .recent
                              .includes(:hub_participants)
    
    respond_to do |format|
      format.json { render json: @dm_threads.map { |t| dm_json(t) } }
    end
  end

  # POST /hub/dms
  # Start a new DM with a user or agent
  def create_dm
    Rails.logger.info "[Hub] create_dm: type=#{params[:participant_type]}, id=#{params[:participant_id]}"
    participant = find_participant(params[:participant_type], params[:participant_id])

    unless participant
      Rails.logger.warn "[Hub] create_dm: Participant not found - type=#{params[:participant_type]}, id=#{params[:participant_id]}, entity_id=#{@entity.id}"
      Rails.logger.warn "[Hub] Available users in entity: #{@entity.users.pluck(:id).join(', ')}"
      return render json: { success: false, error: 'Participant not found' }, status: :not_found
    end

    Rails.logger.info "[Hub] create_dm: Found participant #{participant.class.name}##{participant.id}"

    thread = HubThread.find_or_create_dm(
      entity: @entity,
      participants: [current_user, participant]
    )

    # Send initial message if provided
    if params[:message].present?
      thread.add_message(
        sender: current_user,
        content: params[:message],
        message_type: 'text'
      )
    end

    respond_to do |format|
      format.json { render json: { success: true, thread: dm_json(thread) } }
    end
  end

  # GET /hub/agents
  # List available agents for the Hub
  def agents
    @agents = AgentPlugin.active.for_entity(@entity).includes(:hub_presence)
    
    respond_to do |format|
      format.json do
        render json: @agents.map { |a| agent_json(a) }
      end
    end
  end

  # GET /hub/activity
  # Agent activity feed
  def activity
    @active_agents = HubPresence.for_entity(@entity)
                                .agents
                                .online
                                .includes(:participant, :active_execution)
    
    @recent_work = AgentWorkItem.for_entity(@entity)
                                .recent
                                .limit(20)
                                .includes(:agent_plugin)

    respond_to do |format|
      format.html { render partial: 'hub/activity_feed' }
      format.json do
        render json: {
          active_agents: @active_agents.map { |p| p.as_broadcast_json },
          recent_work: @recent_work.map { |w| work_item_json(w) }
        }
      end
    end
  end

  # GET /hub/presence
  def presence
    @presences = HubPresence.for_entity(@entity).includes(:participant)
    
    respond_to do |format|
      format.json { render json: HubPresence.entity_summary(@entity) }
    end
  end

  # POST /hub/presence
  def update_presence
    presence = HubPresence.for_participant(current_user)
    
    case params[:status]
    when 'online'
      presence.go_online!(custom_status: params[:message], emoji: params[:emoji])
    when 'away'
      presence.go_away!
    when 'busy'
      presence.update!(status: 'busy', status_message: params[:message])
    when 'offline'
      presence.go_offline!
    end

    render json: { success: true, presence: presence.as_broadcast_json }
  end

  # POST /hub/heartbeat
  def heartbeat
    presence = HubPresence.for_participant(current_user)
    presence.heartbeat!
    
    render json: { success: true }
  end

  # POST /hub/messages/:id/react
  def add_reaction
    message = HubMessage.find(params[:id])
    
    unless message.hub_thread.participant?(current_user)
      return render json: { success: false, error: 'Not authorized' }, status: :forbidden
    end

    message.add_reaction(current_user, params[:emoji])
    render json: { success: true, reactions: message.reaction_summary }
  end

  # DELETE /hub/messages/:id/react
  def remove_reaction
    message = HubMessage.find(params[:id])
    
    unless message.hub_thread.participant?(current_user)
      return render json: { success: false, error: 'Not authorized' }, status: :forbidden
    end

    message.remove_reaction(current_user, params[:emoji])
    render json: { success: true, reactions: message.reaction_summary }
  end

  # POST /hub/messages/:id/respond
  # Respond to a message that needs a response (agent question)
  def respond_to_message
    message = HubMessage.find(params[:id])
    
    unless message.hub_thread.participant?(current_user)
      return render json: { success: false, error: 'Not authorized' }, status: :forbidden
    end

    unless message.needs_response?
      return render json: { success: false, error: 'Message does not need a response' }, status: :unprocessable_entity
    end

    response = message.respond!(params[:content], by: current_user)
    render json: { success: true, message: response.as_broadcast_json }
  end

  # POST /hub/messages/:id/handoff_action
  # Handle handoff actions (approve, review, discuss)
  def handoff_action
    message = HubMessage.find(params[:id])
    
    unless message.hub_thread.participant?(current_user) && message.is_handoff?
      return render json: { success: false, error: 'Not authorized or not a handoff' }, status: :forbidden
    end

    case params[:action_id]
    when 'approve'
      message.accept_handoff!(current_user)
      render json: { success: true, status: 'accepted' }
    when 'complete'
      message.complete_handoff!(current_user, feedback: params[:feedback])
      render json: { success: true, status: 'completed' }
    else
      render json: { success: false, error: 'Unknown action' }, status: :unprocessable_entity
    end
  end

  # GET /hub/giphy/search
  # Search Giphy for GIFs
  def giphy_search
    query = params[:q] || 'happy'
    limit = (params[:limit] || 20).to_i
    
    # Check for Giphy API key (credentials or environment variable)
    api_key = Rails.application.credentials.dig(:giphy, :api_key) || ENV['GIPHY_API_KEY']
    
    unless api_key.present?
      # No API key configured - return helpful message
      return render json: { 
        success: false, 
        error: 'Giphy API key not configured',
        message: 'To use GIFs, set GIPHY_API_KEY environment variable or add to Rails credentials. Get a free key at https://developers.giphy.com/',
        setup_required: true
      }
    end
    
    Rails.logger.info "🖼️ Giphy search: query='#{query}', using key from: #{ENV['GIPHY_API_KEY'].present? ? 'ENV' : 'credentials'}"
    
    url = "https://api.giphy.com/v1/gifs/search?api_key=#{api_key}&q=#{URI.encode_www_form_component(query)}&limit=#{limit}&rating=pg-13"
    
    require 'net/http'
    require 'json'
    
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 5
    
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    
    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      
      if data['data'].empty?
        return render json: { 
          success: true, 
          gifs: [],
          message: 'No GIFs found. Try a different search term!'
        }
      end
      
      gifs = data['data'].map do |gif|
        {
          id: gif['id'],
          url: gif['images']['fixed_height']['url'],
          preview_url: gif['images']['fixed_height_still']['url'],
          title: gif['title'],
          width: gif['images']['fixed_height']['width'].to_i,
          height: gif['images']['fixed_height']['height'].to_i
        }
      end
      
      render json: { success: true, gifs: gifs }
    else
      Rails.logger.error "Giphy API returned: #{response.code} - #{response.body}"
      error_data = JSON.parse(response.body) rescue {}
      
      # Check if it's a 403 BANNED response
      if response.code == '403' || error_data.dig('meta', 'msg') == 'BANNED'
        render json: { 
          success: false, 
          error: 'Giphy API key is invalid or banned. Please configure a valid API key.',
          setup_required: true,
          help_url: 'https://developers.giphy.com/'
        }
      else
        render json: { 
          success: false, 
          error: "Giphy search failed: #{response.code}"
        }, status: :service_unavailable
      end
    end
  rescue => e
    Rails.logger.error "Giphy search error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    render json: { 
      success: false, 
      error: "Network error: #{e.message}",
      message: 'Unable to connect to Giphy. Please check your internet connection.'
    }, status: :internal_server_error
  end

  # GET /hub/thread/:id/participants
  # Get participants for mention autocomplete
  def thread_participants
    thread = HubThread.find(params[:id])
    
    unless thread.participant?(current_user)
      return render json: { success: false, error: 'Not authorized' }, status: :forbidden
    end
    
    participants = thread.user_participants.map do |user|
      {
        id: user.id,
        name: user.full_name,
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email,
        role: thread.hub_participants.find_by(participant: user)&.role
      }
    end
    
    render json: { success: true, participants: participants }
  end

  # GET /hub/channels/:id/participants
  # Get channel participants for mention autocomplete
  def channel_participants
    channel = @entity.team_channels.find(params[:id])
    thread = channel.main_thread
    
    unless thread&.participant?(current_user)
      return render json: { success: false, error: 'Not authorized' }, status: :forbidden
    end
    
    participants = thread.user_participants.map do |user|
      {
        id: user.id,
        name: user.full_name,
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email,
        role: thread.hub_participants.find_by(participant: user)&.role
      }
    end
    
    render json: { success: true, participants: participants }
  end

  private

  # Support both web session auth (Devise) and mobile API auth (Bearer token)
  def authenticate_user_or_api!
    token = request.headers["Authorization"]&.gsub(/^Bearer /, "")

    if token.present?
      # Mobile API request with Bearer token
      @current_user = User.find_by(api_key: token)
      unless @current_user
        render json: { error: "Invalid token" }, status: :unauthorized
        return
      end
    else
      # Web request - use Devise session auth
      authenticate_user!
    end
  end

  def set_entity
    @entity = current_user.entity || current_user.entities.first
  end

  def current_entity
    @entity
  end
  helper_method :current_entity

  def set_thread
    @thread = HubThread.find(params[:id])
    
    unless @thread.participant?(current_user)
      respond_to do |format|
        format.html { redirect_to hub_path, alert: 'Not authorized to view this thread' }
        format.json { render json: { error: 'Not authorized' }, status: :forbidden }
      end
    end
  end

  def channel_params
    params.require(:channel).permit(:name, :description, :channel_type, :is_private, :purpose)
  end

  def find_participant(type, id)
    case type
    when 'User'
      @entity.users.find_by(id: id)
    when 'AgentPlugin'
      AgentPlugin.for_entity(@entity).find_by(id: id)
    end
  end

  def find_default_thread
    # Check for unread threads first
    unread_thread = current_user.hub_participations
                                .joins(:hub_thread)
                                .where(hub_threads: { entity: @entity })
                                .with_unread
                                .first&.hub_thread
    
    return unread_thread if unread_thread

    # Fall back to general channel
    @entity.team_channels.default_for(@entity)&.main_thread
  end

  def calculate_unread_counts
    {
      channels: current_user.hub_participations
                           .joins(hub_thread: :team_channel)
                           .where(hub_threads: { entity: @entity })
                           .sum(:unread_count),
      dms: current_user.hub_participations
                       .joins(:hub_thread)
                       .where(hub_threads: { entity: @entity, thread_type: HubThread::DM })
                       .sum(:unread_count),
      total: current_user.hub_participations
                         .joins(:hub_thread)
                         .where(hub_threads: { entity: @entity })
                         .sum(:unread_count)
    }
  end

  def thread_json(thread, messages)
    {
      id: thread.id,
      thread_type: thread.thread_type,
      subject: thread.subject,
      display_name: thread.display_name(for_participant: current_user),
      status: thread.status,
      participants: thread.hub_participants.active.map(&:as_json_for_list),
      messages: messages.map(&:as_broadcast_json),
      last_activity_at: thread.last_activity_at&.iso8601
    }
  end

  def channel_json(channel)
    {
      id: channel.id,
      name: channel.name,
      description: channel.description,
      channel_type: channel.channel_type,
      icon: channel.try(:icon),
      is_private: channel.is_private,
      member_count: channel.member_count,
      agent_count: channel.try(:agents)&.count || 0,
      unread: 0, # TODO: calculate
      last_activity_at: channel.last_activity_at&.iso8601
    }
  end

  def message_json(message)
    {
      id: message.id,
      content: message.content,
      message_type: message.message_type,
      sender_id: message.sender_id,
      sender_type: message.sender_type,
      sender_name: message.sender_name,
      created_at: message.created_at.iso8601,
      edited: message.edited?,
      reactions: message.reactions || {}
    }
  end

  def dm_json(thread)
    other_participant = thread.participants.reject { |p| p == current_user }.first

    # Get participant name - User has full_name, AgentPlugin has name
    participant_name = if other_participant.respond_to?(:full_name)
                         other_participant.full_name
                       elsif other_participant.respond_to?(:name)
                         other_participant.name
                       end

    {
      id: thread.id,
      display_name: thread.display_name(for_participant: current_user),
      participant: {
        id: other_participant&.id,
        type: other_participant&.class&.name,
        name: participant_name,
        is_agent: other_participant.is_a?(AgentPlugin)
      },
      unread_count: thread.hub_participants.find_by(participant: current_user)&.unread_count || 0,
      last_activity_at: thread.last_activity_at&.iso8601
    }
  end

  def agent_json(agent)
    presence = agent.hub_presence
    
    {
      id: agent.id,
      name: agent.name,
      slug: agent.slug,
      role: agent.role,
      icon: agent.respond_to?(:icon) ? agent.icon : '🤖',
      status: presence&.status || 'offline',
      current_activity: presence&.current_activity,
      activity_progress: presence&.activity_progress
    }
  end

  def work_item_json(item)
    {
      id: item.id,
      title: item.title,
      summary: item.summary,
      work_type: item.work_type,
      icon: item.icon,
      agent_name: item.agent_name,
      priority: item.priority,
      requires_action: item.requires_action,
      created_at: item.created_at.iso8601
    }
  end
end
