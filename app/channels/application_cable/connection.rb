module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      Rails.logger.info "ActionCable connection attempt from #{request.remote_ip}"
      self.current_user = find_verified_user
      Rails.logger.info "ActionCable connected successfully for user #{current_user.id} (#{current_user.email})"
    rescue => e
      Rails.logger.error "ActionCable connection failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      reject_unauthorized_connection
    end

    private

    def find_verified_user
      # Try to get user from Warden (Devise)
      if request.env['warden']&.user
        request.env['warden'].user
      else
        Rails.logger.warn "ActionCable connection rejected - no authenticated user found"
        reject_unauthorized_connection
      end
    end
  end
end 