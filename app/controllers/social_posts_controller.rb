class SocialPostsController < ApplicationController
  include Authorizable
  before_action :authenticate_user!
  before_action :set_social_post, only: [ :show, :edit, :update, :destroy, :publish ]
  before_action :authorize_destroy!, only: [:destroy]

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
      elsif params[:publish_now] == "true"
        SocialMedia::PublishPostJob.perform_later(@social_post.id)
      end

      post_to_connected_accounts(@social_post) if params[:post_to_accounts].present?

      redirect_to @social_post, notice: "Post was successfully created."
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
      elsif params[:publish_now] == "true"
        SocialMedia::PublishPostJob.perform_later(@social_post.id)
      end

      post_to_connected_accounts(@social_post) if params[:post_to_accounts].present?

      redirect_to @social_post, notice: "Post was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @social_post.destroy
    redirect_to social_posts_url, notice: "Post was successfully deleted."
  end

  def publish
    if @social_post.draft?
      @social_post.update(status: "scheduled", scheduled_at: Time.current)
      SocialMedia::PublishPostJob.perform_later(@social_post.id)
      redirect_to @social_post, notice: "Post is being published."
    else
      redirect_to @social_post, alert: "Only draft posts can be published."
    end
  end

  def generate_content
    platform = params[:platform]
    purpose = params[:purpose]

    if platform.blank?
      render json: { error: "Platform is required" }, status: :unprocessable_entity
      return
    end

    business_profile = current_user.ensure_business_profile
    openai_service = OpenaiService.new

    generated_content = openai_service.generate_social_post(
      business_profile,
      platform,
      purpose
    )

    render json: { content: generated_content }
  rescue => e
    Rails.logger.error("Error generating content: #{e.message}")
    render json: { error: "Error generating content. Please try again." }, status: :unprocessable_entity
  end

  private

  def set_social_post
    @social_post = current_user.social_posts.find(params[:id])
  end

  def social_post_params
    params.require(:social_post).permit(:title, :content, :platform, :status, :scheduled_at, :image_url)
  end

  def post_to_connected_accounts(post)
    account_ids = params[:post_to_accounts].map(&:to_i)

    current_user.social_media_accounts.where(id: account_ids).each do |account|
      SocialMedia::PostToAccountJob.perform_later(post.id, account.id)
    end
  end
end
