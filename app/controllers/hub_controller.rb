# frozen_string_literal: true

# HubController
#
# Controller for the Collaborative Intelligence Hub.
# The central communication hub where humans and AI agents collaborate.
#
class HubController < ApplicationController
  before_action :authenticate_user!
  before_action :set_entity
  before_action :set_thread, only: [:show_thread, :send_message, :mark_read]

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
    message = @thread.add_message(
      sender: current_user,
      content: params[:content],
      message_type: params[:message_type] || 'text',
      reply_to_id: params[:reply_to_id],
      attachments: params[:attachments] || []
    )

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
    participant = find_participant(params[:participant_type], params[:participant_id])
    
    unless participant
      return render json: { success: false, error: 'Participant not found' }, status: :not_found
    end

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

  private

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
      icon: channel.icon,
      is_private: channel.is_private,
      member_count: channel.member_count,
      agent_count: channel.agents.count,
      unread: 0, # TODO: calculate
      last_activity_at: channel.last_activity_at&.iso8601
    }
  end

  def dm_json(thread)
    other_participant = thread.participants.reject { |p| p == current_user }.first
    
    {
      id: thread.id,
      display_name: thread.display_name(for_participant: current_user),
      participant: {
        id: other_participant&.id,
        type: other_participant&.class&.name,
        name: other_participant&.respond_to?(:name) ? other_participant.name : nil,
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
