class OAuthConfigurationsController < ApplicationController
  include Authorizable
  before_action :authorize_destroy!, only: [:destroy]

  def index
  end

  def show
  end

  def new
  end

  def create
  end

  def edit
  end

  def update
  end

  def destroy
  end
end
