class TouchApiKeyJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    user.touch_api_key!
  end
end
