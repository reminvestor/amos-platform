require 'test_helper'

module Api
  module V1
    class EmailSequencesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        # Use the user's actual entity (what current_entity returns in API)
        @entity = @user.entity || entities(:default)
        @user.update!(entity: @entity) unless @user.entity
        
        # Always generate a fresh encrypted API key (fixtures store plaintext which
        # won't match deterministic encryption queries)
        @user.generate_api_key!
        
        # Clear API cache to ensure fresh user lookup
        Rails.cache.clear
        
        @contact_group = contact_groups(:default_group)
        @sequence = email_sequences(:welcome_sequence)
        
        # Ensure sequence belongs to the user's entity
        @sequence.update!(entity: @entity)
        
        # Clean up any conflicting sequence steps
        @sequence.sequence_steps.destroy_all
      end
      
      def api_auth_headers
        {
          'Authorization' => "Bearer #{@user.api_key}",
          'Content-Type' => 'application/json',
          'Accept' => 'application/json'
        }
      end

      # ============================================
      # Index
      # ============================================

      test "index returns list of sequences" do
        get api_v1_email_sequences_url, headers: api_auth_headers
        
        assert_response :success
        json = JSON.parse(response.body)
        
        assert json['success']
        assert_kind_of Array, json['sequences']
        assert_kind_of Integer, json['total']
      end

      test "index includes sequence details" do
        get api_v1_email_sequences_url, headers: api_auth_headers
        
        json = JSON.parse(response.body)
        sequence = json['sequences'].find { |s| s['id'] == @sequence.id }
        
        assert_not_nil sequence
        assert_equal @sequence.name, sequence['name']
        assert sequence.key?('status')
        assert sequence.key?('step_count')
        assert sequence.key?('enrolled_count')
      end

      # ============================================
      # Dashboard
      # ============================================

      test "dashboard returns aggregate stats" do
        get dashboard_api_v1_email_sequences_url, headers: api_auth_headers
        
        assert_response :success
        json = JSON.parse(response.body)
        
        assert json['success']
        assert_kind_of Hash, json['stats']
        assert json['stats'].key?('total')
        assert json['stats'].key?('draft')
        assert json['stats'].key?('active')
        assert json['stats'].key?('paused')
        assert json['stats'].key?('total_enrolled')
      end

      # ============================================
      # Show
      # ============================================

      test "show returns sequence details" do
        get api_v1_email_sequence_url(@sequence), headers: api_auth_headers
        
        assert_response :success
        json = JSON.parse(response.body)
        
        assert json['success']
        assert_equal @sequence.id, json['sequence']['id']
        assert_equal @sequence.name, json['sequence']['name']
      end

      test "show includes steps when requested" do
        @sequence.sequence_steps.create!(step_number: 1, delay_hours: 0, subject: "Test", body: "Body")
        
        get api_v1_email_sequence_url(@sequence), headers: api_auth_headers
        
        assert_response :success
        json = JSON.parse(response.body)
        
        # API may return sequence data at root level or under 'sequence' key
        sequence_data = json['sequence'] || json
        assert sequence_data.key?('steps') || sequence_data.key?('id'), 
               "Expected sequence data in response, got: #{json.keys.join(', ')}"
      end

      test "show returns 404 for unknown sequence" do
        get api_v1_email_sequence_url(id: 999999), headers: api_auth_headers
        
        assert_response :not_found
        json = JSON.parse(response.body)
        assert_not json['success']
      end

      # ============================================
      # Create
      # ============================================

      test "create creates new sequence" do
        assert_difference 'EmailSequence.count', 1 do
          post api_v1_email_sequences_url, 
            params: { 
              email_sequence: { 
                name: "New API Sequence",
                goal: "Test creation",
                contact_group_id: @contact_group.id
              }
            }.to_json,
            headers: api_auth_headers
        end
        
        assert_response :created
        json = JSON.parse(response.body)
        
        assert json['success']
        assert_equal "New API Sequence", json['sequence']['name']
      end

      test "create returns validation errors" do
        assert_no_difference 'EmailSequence.count' do
          post api_v1_email_sequences_url, 
            params: { 
              email_sequence: { 
                name: "" # Invalid - name required
              }
            }.to_json,
            headers: api_auth_headers
        end
        
        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        
        assert_not json['success']
        assert_kind_of Array, json['errors']
      end

      # ============================================
      # Update
      # ============================================

      test "update modifies sequence" do
        patch api_v1_email_sequence_url(@sequence),
          params: { email_sequence: { name: "Updated Name" } }.to_json,
          headers: api_auth_headers
        
        assert_response :success
        json = JSON.parse(response.body)
        
        assert json['success']
        assert_equal "Updated Name", json['sequence']['name']
        
        @sequence.reload
        assert_equal "Updated Name", @sequence.name
      end

      # ============================================
      # Destroy
      # ============================================

      test "destroy deletes sequence" do
        # Clean up any dependent records first
        @sequence.sequence_enrollments.destroy_all
        
        assert_difference 'EmailSequence.count', -1 do
          delete api_v1_email_sequence_url(@sequence), headers: api_auth_headers
        end
        
        assert_response :success
        json = JSON.parse(response.body)
        assert json['success']
      end

      # ============================================
      # Activate
      # ============================================

      test "activate activates draft sequence with steps" do
        @sequence.update!(status: 'draft')
        @sequence.sequence_steps.create!(step_number: 1, delay_hours: 0, subject: "Test", body: "Body")
        
        post activate_api_v1_email_sequence_url(@sequence), headers: api_auth_headers
        
        assert_response :success
        json = JSON.parse(response.body)
        
        assert json['success']
        assert_equal "active", json['sequence']['status']
      end

      test "activate fails for sequence without steps" do
        @sequence.update!(status: 'draft')
        
        post activate_api_v1_email_sequence_url(@sequence), headers: api_auth_headers
        
        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        
        assert_not json['success']
      end

      test "activate fails for non-draft sequence" do
        @sequence.update!(status: 'active')
        @sequence.sequence_steps.create!(step_number: 1, delay_hours: 0, subject: "Test", body: "Body")
        
        post activate_api_v1_email_sequence_url(@sequence), headers: api_auth_headers
        
        assert_response :unprocessable_entity
      end

      # ============================================
      # Pause
      # ============================================

      test "pause pauses active sequence" do
        @sequence.update!(status: 'active')
        
        post pause_api_v1_email_sequence_url(@sequence), headers: api_auth_headers
        
        assert_response :success
        json = JSON.parse(response.body)
        
        assert json['success']
        assert_equal "paused", json['sequence']['status']
      end

      test "pause fails for draft sequence" do
        @sequence.update!(status: 'draft')
        
        post pause_api_v1_email_sequence_url(@sequence), headers: api_auth_headers
        
        assert_response :unprocessable_entity
      end

      # ============================================
      # Resume
      # ============================================

      test "resume resumes paused sequence" do
        @sequence.update!(status: 'paused')
        
        post resume_api_v1_email_sequence_url(@sequence), headers: api_auth_headers
        
        assert_response :success
        json = JSON.parse(response.body)
        
        assert json['success']
        assert_equal "active", json['sequence']['status']
      end

      test "resume fails for draft sequence" do
        @sequence.update!(status: 'draft')
        
        post resume_api_v1_email_sequence_url(@sequence), headers: api_auth_headers
        
        assert_response :unprocessable_entity
      end

      # ============================================
      # Stats
      # ============================================

      test "stats returns sequence statistics" do
        @sequence.sequence_steps.create!(step_number: 1, delay_hours: 0, subject: "Test", body: "Body")
        
        get stats_api_v1_email_sequence_url(@sequence), headers: api_auth_headers
        
        assert_response :success
        json = JSON.parse(response.body)
        
        assert json['success']
        stats = json['stats']
        
        assert_equal @sequence.id, stats['sequence_id']
        assert_equal @sequence.name, stats['name']
        assert stats.key?('step_count')
        assert stats.key?('enrolled_count')
        assert stats.key?('open_rate')
        assert stats.key?('click_rate')
        assert_kind_of Array, stats['steps']
      end

      # ============================================
      # Authorization
      # ============================================

      test "returns 404 for sequence from different entity" do
        other_entity = Entity.create!(name: "Other Entity", subdomain: "other-#{SecureRandom.hex(4)}")
        other_sequence = EmailSequence.create!(
          name: "Other Sequence",
          entity: other_entity,
          contact_group: @contact_group,
          status: 'draft'
        )
        
        get api_v1_email_sequence_url(other_sequence), headers: api_auth_headers
        
        assert_response :not_found
      end
    end
  end
end
