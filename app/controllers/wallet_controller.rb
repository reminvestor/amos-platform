# frozen_string_literal: true

class WalletController < ApplicationController
  before_action :authenticate_user!

  def index
    # View handles all the display via JavaScript API calls
  end
end
