class JobNotificationChannel < ApplicationCable::Channel
  def subscribed
    stream_from "job_notifications"
  end

  def unsubscribed
  end
end
