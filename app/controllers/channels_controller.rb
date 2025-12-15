# ChannelsController
#
# Manages team channels for Team Space collaboration
#
class ChannelsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_channel, only: [:show, :edit, :update, :destroy, :archive, :unarchive]
  layout 'customer_admin'

  def index
    @channels = current_entity.team_channels.active.ordered
    @archived_channels = current_entity.team_channels.archived.ordered
  end

  def show
    # In the future, this will show channel messages
  end

  def new
    @channel = current_entity.team_channels.build
  end

  def create
    @channel = current_entity.team_channels.build(channel_params)

    if @channel.save
      redirect_to channels_path, notice: 'Channel created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @channel.update(channel_params)
      redirect_to channels_path, notice: 'Channel updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @channel.is_default?
      redirect_to channels_path, alert: 'Cannot delete default channel.'
    else
      @channel.destroy
      redirect_to channels_path, notice: 'Channel deleted successfully.'
    end
  end

  def archive
    @channel.archive!
    redirect_to channels_path, notice: 'Channel archived.'
  end

  def unarchive
    @channel.unarchive!
    redirect_to channels_path, notice: 'Channel restored.'
  end

  private

  def set_channel
    @channel = current_entity.team_channels.find(params[:id])
  end

  def channel_params
    params.require(:team_channel).permit(:name, :description, :channel_type)
  end

  def current_entity
    @current_entity ||= current_user.entity
  end
end
