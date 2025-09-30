module Agents
  module Communication
    class AgentMessage
      include ActiveModel::Model
      include ActiveModel::Serialization
      
      attr_accessor :id, :sender_id, :recipient_id, :message_type, 
                    :content, :task_session_id, :priority, :timestamp,
                    :parent_message_id, :metadata
      
      validates :sender_id, presence: true
      validates :recipient_id, presence: true
      validates :message_type, presence: true
      validates :content, presence: true
      
      def initialize(attributes = {})
        super
        @id ||= SecureRandom.uuid
        @timestamp ||= Time.current
        @priority ||= :normal
        @metadata ||= {}
      end
      
      # Save message to database for audit trail
      def save!
        return false unless valid?
        
        # Store in Redis for fast access
        redis_key = "agent_messages:#{id}"
        ($redis || Redis.new).setex(
          redis_key,
          7.days.to_i,
          to_json
        )
        
        # Also store in database for permanent record if task session exists
        if task_session_id
          create_task_event
        end
        
        true
      end
      
      # Create a reply to this message
      def create_reply(content, message_type = 'reply')
        self.class.new(
          sender_id: recipient_id,
          recipient_id: sender_id,
          message_type: message_type,
          content: content,
          task_session_id: task_session_id,
          parent_message_id: id
        )
      end
      
      # Check if message requires response
      def requires_response?
        %w[help_request question coordination query].include?(message_type)
      end
      
      # Check if message is urgent
      def urgent?
        priority == :high || 
        message_type.include?('error') ||
        message_type.include?('failure')
      end
      
      # Get conversation thread
      def conversation_thread
        thread = [self]
        
        # Get parent messages
        current = self
        while current.parent_message_id
          parent = self.class.find(current.parent_message_id)
          break unless parent
          thread.unshift(parent)
          current = parent
        end
        
        # Get child messages
        children = self.class.find_replies(id)
        thread.concat(children)
        
        thread
      end
      
      # Serialize to JSON
      def to_json(*args)
        {
          id: id,
          sender_id: sender_id,
          recipient_id: recipient_id,
          message_type: message_type,
          content: content,
          task_session_id: task_session_id,
          priority: priority,
          timestamp: timestamp,
          parent_message_id: parent_message_id,
          metadata: metadata
        }.to_json(*args)
      end
      
      # Class methods
      class << self
        # Find a message by ID
        def find(message_id)
          redis_key = "agent_messages:#{message_id}"
          data = ($redis || Redis.new).get(redis_key)
          return nil unless data
          
          new(JSON.parse(data, symbolize_names: true))
        rescue => e
          Rails.logger.error "Failed to find message #{message_id}: #{e.message}"
          nil
        end
        
        # Find replies to a message
        def find_replies(parent_message_id)
          pattern = "agent_messages:*"
          keys = ($redis || Redis.new).keys(pattern)
          
          replies = []
          keys.each do |key|
            data = ($redis || Redis.new).get(key)
            next unless data
            
            message_data = JSON.parse(data, symbolize_names: true)
            if message_data[:parent_message_id] == parent_message_id
              replies << new(message_data)
            end
          end
          
          replies.sort_by(&:timestamp)
        rescue => e
          Rails.logger.error "Failed to find replies: #{e.message}"
          []
        end
        
        # Create and deliver a message
        def create_and_deliver!(attributes)
          message = new(attributes)
          
          if message.save!
            MessageBroker.deliver(
              from: message.sender_id,
              to: message.recipient_id,
              content: {
                type: message.message_type,
                data: message.content,
                message_id: message.id
              },
              priority: message.priority
            )
            
            message
          else
            raise "Invalid message: #{message.errors.full_messages.join(', ')}"
          end
        end
      end
      
      private
      
      def create_task_event
        task_session = TaskSession.find_by(id: task_session_id)
        return unless task_session
        
        task_session.add_event('agent_message', {
          message_id: id,
          sender_id: sender_id,
          recipient_id: recipient_id,
          message_type: message_type,
          content_summary: content.to_s.truncate(100),
          priority: priority
        })
      rescue => e
        Rails.logger.error "Failed to create task event for message: #{e.message}"
      end
    end
  end
end
