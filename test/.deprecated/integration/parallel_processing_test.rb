require "test_helper"

class ParallelProcessingTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one) # Assuming you have user fixtures
    sign_in @user
    @entity = @user.entity
  end
  
  test "complex request triggers parallel processing" do
    message = "Analyze my campaigns and schedule meetings with top performers"
    
    # Spy on orchestrator creation
    orchestrator_called = false
    ParallelTaskOrchestrator.stub :new, ->(*args) {
      orchestrator_called = true
      orchestrator = ParallelTaskOrchestrator.new(*args)
      
      # Mock the process_request to return test tasks
      orchestrator.stub :process_request, ->(*_) {
        [
          TaskSession.create!(
            user: @user,
            task_type: 'analysis',
            status: 'active',
            metadata: { description: 'Analyze campaigns' }
          ),
          TaskSession.create!(
            user: @user,
            task_type: 'background',
            status: 'active',
            metadata: { description: 'Schedule meetings' }
          )
        ]
      } do
        return orchestrator
      end
    } do
      post scout_chat_stream_path, 
           params: { message: message },
           headers: { 'Accept' => 'text/event-stream' }
      
      assert orchestrator_called, "ParallelTaskOrchestrator should be used for complex requests"
      assert_response :success
    end
  end
  
  test "simple request uses standard processing" do
    message = "What time is it?"
    
    orchestrator_called = false
    ParallelTaskOrchestrator.stub :new, ->(*args) {
      orchestrator_called = true
      ParallelTaskOrchestrator.new(*args)
    } do
      post scout_chat_stream_path,
           params: { message: message },
           headers: { 'Accept' => 'text/event-stream' }
      
      assert_not orchestrator_called, "Simple requests should not use parallel processing"
      assert_response :success
    end
  end
  
  test "voice mode triggers immediate response" do
    VoiceSession.create!(
      entity: @entity,
      session_id: 'test-session',
      status: 'active'
    )
    
    immediate_response_sent = false
    
    VoiceImmediateProcessor.stub :new, ->(*args) {
      processor = VoiceImmediateProcessor.new(*args)
      processor.stub :process!, -> {
        immediate_response_sent = true
        "I'll help you with that right away."
      } do
        return processor
      end
    } do
      post scout_chat_stream_path,
           params: { 
             message: "Analyze my campaigns",
             voice_mode: 'true'
           },
           headers: { 'Accept' => 'text/event-stream' }
      
      assert immediate_response_sent, "Voice mode should send immediate response"
    end
  end
  
  test "task dependencies are enforced" do
    # Create tasks with dependencies
    task1 = TaskSession.create!(
      user: @user,
      task_type: 'analysis',
      status: 'active',
      metadata: { description: 'Fetch data' }
    )
    
    task2 = TaskSession.create!(
      user: @user,
      task_type: 'analysis',
      status: 'active',
      metadata: { description: 'Process data' }
    )
    
    # Create dependency
    TaskDependency.create!(
      task_session: task2,
      depends_on_task: task1,
      relationship_type: 'blocks'
    )
    
    # Task 2 should not be ready
    assert_not task2.ready_for_execution?
    
    # Complete task 1
    task1.update!(status: 'completed')
    
    # Now task 2 should be ready
    assert task2.ready_for_execution?
  end
  
  test "admin can monitor parallel tasks" do
    # Create some test tasks
    3.times do |i|
      TaskSession.create!(
        user: @user,
        parent_conversation_id: "conv-#{i}",
        task_type: ['voice_immediate', 'analysis', 'background'].sample,
        status: ['active', 'completed', 'failed'].sample,
        progress: rand(0..100),
        metadata: { description: "Test task #{i}" }
      )
    end
    
    get admin_parallel_tasks_path
    assert_response :success
    
    # Check that stats are calculated
    assert_select '.stat-value', minimum: 4 # Total, Active, Success Rate, Avg Duration
  end
  
  test "SSE stream includes parallel task updates" do
    # This is a more complex test that would require WebSocket testing tools
    # For now, we'll test the controller methods directly
    
    controller = ScoutController.new
    controller.instance_variable_set(:@session_id, 'test-session')
    
    # Mock stream_update to capture output
    updates = []
    controller.stub :stream_update, ->(data) { updates << data } do
      tasks = [
        TaskSession.new(id: 1, task_type: 'analysis', metadata: { description: 'Test' })
      ]
      
      controller.send(:aggregate_and_stream_results, tasks) do |event, data|
        # Callback would be called during execution
      end
      
      # Should have sent initial parallel execution start
      assert updates.any? { |u| u[:type] == 'parallel_execution_start' }
    end
  end
end
