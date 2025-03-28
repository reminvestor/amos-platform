class SocialPostsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_social_post, only: [:show, :edit, :update, :destroy, :publish]

  def index
    @social_posts = current_user.social_posts.order(created_at: :desc)
  end

  def show
  end

  def new
    @social_post = current_user.social_posts.build
  end

  def create
    @social_post = current_user.social_posts.build(social_post_params)
    
    if @social_post.save
      if @social_post.scheduled?
        SocialMedia::PublishPostJob.set(wait_until: @social_post.scheduled_at).perform_later(@social_post.id)
      else
        SocialMedia::PublishPostJob.perform_later(@social_post.id)
      end
      
      redirect_to @social_post, notice: 'Post was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @social_post.update(social_post_params)
      if @social_post.scheduled?
        SocialMedia::PublishPostJob.set(wait_until: @social_post.scheduled_at).perform_later(@social_post.id)
      else
        SocialMedia::PublishPostJob.perform_later(@social_post.id)
      end
      
      redirect_to @social_post, notice: 'Post was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @social_post.destroy
    redirect_to social_posts_url, notice: 'Post was successfully deleted.'
  end

  def publish
    if @social_post.draft?
      @social_post.update(status: 'scheduled', scheduled_at: Time.current)
      SocialMedia::PublishPostJob.perform_later(@social_post.id)
      redirect_to @social_post, notice: 'Post is being published.'
    else
      redirect_to @social_post, alert: 'Only draft posts can be published.'
    end
  end

  private

  def set_social_post
    @social_post = current_user.social_posts.find(params[:id])
  end

  def social_post_params
    params.require(:social_post).permit(:title, :content, :platform, :status, :scheduled_at, :image_url)
  end
end 