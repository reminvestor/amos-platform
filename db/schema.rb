# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_11_12_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "vector"

  create_table "ab_test_variants", force: :cascade do |t|
    t.bigint "ab_test_id", null: false
    t.string "name", null: false
    t.float "traffic_percentage", default: 50.0, null: false
    t.jsonb "configuration", default: {}
    t.integer "impressions", default: 0
    t.integer "conversions", default: 0
    t.float "conversion_rate", default: 0.0
    t.boolean "is_winner", default: false
    t.boolean "is_control", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ab_test_id", "conversion_rate"], name: "index_ab_test_variants_on_ab_test_id_and_conversion_rate"
    t.index ["ab_test_id"], name: "index_ab_test_variants_on_ab_test_id"
    t.index ["is_winner"], name: "index_ab_test_variants_on_is_winner"
  end

  create_table "ab_tests", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "testable_type", null: false
    t.bigint "testable_id", null: false
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.text "hypothesis"
    t.string "metric", default: "conversion_rate"
    t.float "confidence_level", default: 0.95
    t.integer "minimum_sample_size", default: 100
    t.datetime "started_at"
    t.datetime "ended_at"
    t.jsonb "results"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "status"], name: "index_ab_tests_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_ab_tests_on_entity_id"
    t.index ["started_at"], name: "index_ab_tests_on_started_at"
    t.index ["testable_type", "testable_id"], name: "index_ab_tests_on_testable"
    t.index ["testable_type", "testable_id"], name: "index_ab_tests_on_testable_type_and_testable_id"
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_activities", force: :cascade do |t|
    t.bigint "admin_user_id", null: false
    t.string "action"
    t.string "resource_type"
    t.string "resource_id"
    t.text "details"
    t.string "ip_address"
    t.text "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_admin_activities_on_admin_user_id"
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.string "first_name"
    t.string "last_name"
    t.integer "role", default: 0, null: false
    t.datetime "last_login_at"
    t.integer "login_count", default: 0, null: false
    t.integer "failed_login_attempts", default: 0, null: false
    t.datetime "locked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
  end

  create_table "affiliate_clicks", force: :cascade do |t|
    t.bigint "affiliate_id", null: false
    t.string "referral_code"
    t.string "ip_address"
    t.text "user_agent"
    t.string "referrer"
    t.datetime "landed_at"
    t.string "session_id"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["affiliate_id", "landed_at"], name: "index_affiliate_clicks_on_affiliate_id_and_landed_at"
    t.index ["affiliate_id"], name: "index_affiliate_clicks_on_affiliate_id"
    t.index ["ip_address"], name: "index_affiliate_clicks_on_ip_address"
    t.index ["landed_at"], name: "index_affiliate_clicks_on_landed_at"
    t.index ["referral_code"], name: "index_affiliate_clicks_on_referral_code"
  end

  create_table "affiliate_tiers", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "commission_rate", precision: 5, scale: 4, null: false
    t.integer "min_referrals", default: 0, null: false
    t.jsonb "benefits", default: {}
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_affiliate_tiers_on_is_active"
    t.index ["min_referrals"], name: "index_affiliate_tiers_on_min_referrals"
    t.index ["name"], name: "index_affiliate_tiers_on_name", unique: true
  end

  create_table "affiliates", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "affiliate_code", null: false
    t.integer "status", default: 0, null: false
    t.decimal "commission_rate", precision: 5, scale: 4, default: "0.2", null: false
    t.string "payment_email"
    t.text "application_notes"
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.string "tier", default: "bronze", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["affiliate_code"], name: "index_affiliates_on_affiliate_code", unique: true
    t.index ["approved_by_id"], name: "index_affiliates_on_approved_by_id"
    t.index ["status"], name: "index_affiliates_on_status"
    t.index ["tier"], name: "index_affiliates_on_tier"
    t.index ["user_id"], name: "index_affiliates_on_user_id"
  end

  create_table "agent_activities", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.string "agent_name"
    t.string "activity_type"
    t.jsonb "input_data"
    t.jsonb "output_data"
    t.integer "processing_time_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_agent_activities_on_conversation_id"
  end

  create_table "agent_executions", force: :cascade do |t|
    t.bigint "pipeline_execution_id", null: false
    t.string "agent_id", null: false
    t.integer "status", default: 0, null: false
    t.string "workspace_path"
    t.jsonb "inputs", default: {}
    t.jsonb "outputs", default: {}
    t.text "logs"
    t.text "error_message"
    t.integer "tokens_used", default: 0
    t.decimal "cost", precision: 10, scale: 4, default: "0.0"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_agent_executions_on_agent_id"
    t.index ["pipeline_execution_id", "agent_id"], name: "index_agent_executions_on_pipeline_execution_id_and_agent_id"
    t.index ["pipeline_execution_id", "status"], name: "index_agent_executions_on_pipeline_execution_id_and_status"
    t.index ["pipeline_execution_id"], name: "index_agent_executions_on_pipeline_execution_id"
    t.index ["started_at"], name: "index_agent_executions_on_started_at"
    t.index ["status"], name: "index_agent_executions_on_status"
  end

  create_table "agent_lightning_configs", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.boolean "enabled", default: true
    t.string "mode", default: "observing", null: false
    t.string "training_strategy", default: "prompt_optimization", null: false
    t.integer "retrain_frequency_hours", default: 24, null: false
    t.datetime "last_training_at"
    t.integer "trace_retention_days", default: 90, null: false
    t.integer "min_traces_for_training", default: 100, null: false
    t.jsonb "optimization_targets", default: {}, null: false
    t.jsonb "learning_parameters", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_agent_lightning_configs_on_entity_id", unique: true
  end

  create_table "agent_lightning_optimizations", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "agent_training_job_id"
    t.string "optimization_id", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "before_prompts", default: {}, null: false
    t.jsonb "after_prompts", default: {}, null: false
    t.decimal "improvement_percentage", precision: 5, scale: 2, default: "0.0"
    t.integer "templates_updated", default: 0
    t.jsonb "templates_modified", default: [], null: false
    t.jsonb "context_types_optimized", default: [], null: false
    t.integer "prompts_optimized", default: 0
    t.datetime "applied_at"
    t.datetime "rolled_back_at"
    t.integer "rollback_count", default: 0
    t.jsonb "metadata", default: {}, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_training_job_id"], name: "index_agent_lightning_optimizations_on_agent_training_job_id"
    t.index ["entity_id", "created_at"], name: "idx_on_entity_id_created_at_1d14b8f4ff"
    t.index ["entity_id"], name: "index_agent_lightning_optimizations_on_entity_id"
    t.index ["optimization_id"], name: "index_agent_lightning_optimizations_on_optimization_id", unique: true
    t.index ["status", "created_at"], name: "index_agent_lightning_optimizations_on_status_and_created_at"
    t.index ["status"], name: "index_agent_lightning_optimizations_on_status"
  end

  create_table "agent_lightning_traces", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.bigint "workflow_execution_id"
    t.bigint "task_session_id"
    t.string "trace_id", null: false
    t.string "trace_type", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "input_data", default: {}, null: false
    t.jsonb "output_data", default: {}, null: false
    t.jsonb "intermediate_steps", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "token_count"
    t.decimal "cost_estimate", precision: 10, scale: 6
    t.integer "duration_ms"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.decimal "reward_signal", precision: 10, scale: 6
    t.string "reward_source"
    t.text "reward_explanation"
    t.integer "template_version"
    t.string "model_used"
    t.boolean "included_in_training", default: false
    t.datetime "training_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_agent_lightning_traces_on_created_at"
    t.index ["entity_id", "trace_type", "status"], name: "idx_on_entity_id_trace_type_status_0da9c597e6"
    t.index ["entity_id"], name: "index_agent_lightning_traces_on_entity_id"
    t.index ["status", "included_in_training"], name: "idx_on_status_included_in_training_06ffceb35c"
    t.index ["task_session_id"], name: "index_agent_lightning_traces_on_task_session_id"
    t.index ["trace_id"], name: "index_agent_lightning_traces_on_trace_id", unique: true
    t.index ["user_id"], name: "index_agent_lightning_traces_on_user_id"
    t.index ["workflow_execution_id"], name: "index_agent_lightning_traces_on_workflow_execution_id"
  end

  create_table "agent_lightning_webhook_logs", force: :cascade do |t|
    t.bigint "agent_lightning_webhook_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.datetime "completed_at"
    t.integer "response_code"
    t.text "response_body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_lightning_webhook_id"], name: "idx_on_agent_lightning_webhook_id_07468d8cc5"
    t.index ["created_at"], name: "index_agent_lightning_webhook_logs_on_created_at"
    t.index ["event_type"], name: "index_agent_lightning_webhook_logs_on_event_type"
    t.index ["status"], name: "index_agent_lightning_webhook_logs_on_status"
  end

  create_table "agent_lightning_webhooks", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "event_type", null: false
    t.string "url", null: false
    t.jsonb "headers", default: {}, null: false
    t.boolean "active", default: true
    t.integer "total_calls", default: 0
    t.integer "successful_calls", default: 0
    t.integer "failed_calls", default: 0
    t.datetime "last_triggered_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_agent_lightning_webhooks_on_active"
    t.index ["entity_id", "event_type"], name: "index_agent_lightning_webhooks_on_entity_id_and_event_type", unique: true
    t.index ["entity_id"], name: "index_agent_lightning_webhooks_on_entity_id"
    t.index ["event_type"], name: "index_agent_lightning_webhooks_on_event_type"
  end

  create_table "agent_llm_calls", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "agent_lightning_trace_id"
    t.string "call_id", null: false
    t.string "model", null: false
    t.string "agent_role", null: false
    t.jsonb "system_prompt", default: {}, null: false
    t.jsonb "user_messages", default: [], null: false
    t.jsonb "response_content", default: {}, null: false
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.integer "total_tokens", default: 0, null: false
    t.integer "latency_ms", default: 0, null: false
    t.decimal "cost", precision: 10, scale: 8
    t.string "status", null: false
    t.text "error_message"
    t.jsonb "parsed_actions"
    t.boolean "actions_executed_successfully"
    t.decimal "success_score", precision: 10, scale: 6
    t.datetime "called_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_lightning_trace_id"], name: "index_agent_llm_calls_on_agent_lightning_trace_id"
    t.index ["call_id"], name: "index_agent_llm_calls_on_call_id", unique: true
    t.index ["called_at"], name: "index_agent_llm_calls_on_called_at"
    t.index ["entity_id", "agent_role", "status"], name: "index_agent_llm_calls_on_entity_id_and_agent_role_and_status"
    t.index ["entity_id"], name: "index_agent_llm_calls_on_entity_id"
  end

  create_table "agent_messages", force: :cascade do |t|
    t.string "sender_id", null: false
    t.string "recipient_id", null: false
    t.string "message_type", null: false
    t.jsonb "content", null: false
    t.bigint "task_session_id"
    t.string "priority", default: "normal"
    t.string "parent_message_id"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_type"], name: "index_agent_messages_on_message_type"
    t.index ["parent_message_id"], name: "index_agent_messages_on_parent_message_id"
    t.index ["recipient_id"], name: "index_agent_messages_on_recipient_id"
    t.index ["sender_id"], name: "index_agent_messages_on_sender_id"
    t.index ["task_session_id", "created_at"], name: "index_agent_messages_on_task_session_id_and_created_at"
    t.index ["task_session_id"], name: "index_agent_messages_on_task_session_id"
  end

  create_table "agent_phase_executions", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "workflow_execution_id"
    t.bigint "agent_lightning_trace_id"
    t.string "phase_id", null: false
    t.string "phase_type", null: false
    t.string "status", null: false
    t.integer "attempts", default: 1, null: false
    t.integer "duration_ms", default: 0, null: false
    t.jsonb "phase_input", default: {}, null: false
    t.jsonb "phase_output", default: {}, null: false
    t.boolean "met_success_criteria"
    t.decimal "phase_success_score", precision: 10, scale: 6
    t.text "failure_reason"
    t.integer "max_retries", default: 3, null: false
    t.jsonb "retry_history", default: [], null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_lightning_trace_id"], name: "index_agent_phase_executions_on_agent_lightning_trace_id"
    t.index ["entity_id", "workflow_execution_id", "phase_id"], name: "idx_on_entity_id_workflow_execution_id_phase_id_b263fb0f73"
    t.index ["entity_id"], name: "index_agent_phase_executions_on_entity_id"
    t.index ["started_at"], name: "index_agent_phase_executions_on_started_at"
    t.index ["workflow_execution_id"], name: "index_agent_phase_executions_on_workflow_execution_id"
  end

  create_table "agent_rewards", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "agent_lightning_trace_id", null: false
    t.bigint "user_id"
    t.string "reward_type", null: false
    t.decimal "reward_value", precision: 10, scale: 6, null: false
    t.text "reason"
    t.jsonb "metadata", default: {}, null: false
    t.string "source", null: false
    t.datetime "assigned_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_lightning_trace_id"], name: "index_agent_rewards_on_agent_lightning_trace_id"
    t.index ["entity_id", "agent_lightning_trace_id"], name: "index_agent_rewards_on_entity_id_and_agent_lightning_trace_id"
    t.index ["entity_id"], name: "index_agent_rewards_on_entity_id"
    t.index ["reward_type", "assigned_at"], name: "index_agent_rewards_on_reward_type_and_assigned_at"
    t.index ["user_id"], name: "index_agent_rewards_on_user_id"
  end

  create_table "agent_tool_executions", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "agent_lightning_trace_id"
    t.bigint "agent_llm_call_id"
    t.string "execution_id", null: false
    t.string "tool_name", null: false
    t.string "tool_category", null: false
    t.jsonb "input_arguments", default: {}, null: false
    t.jsonb "output_result", default: {}, null: false
    t.string "status", null: false
    t.integer "execution_time_ms", default: 0, null: false
    t.text "error_message"
    t.boolean "result_met_expectations"
    t.decimal "execution_quality_score", precision: 10, scale: 6
    t.integer "sequence_number", default: 0, null: false
    t.integer "parent_tool_execution_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_lightning_trace_id"], name: "index_agent_tool_executions_on_agent_lightning_trace_id"
    t.index ["agent_llm_call_id"], name: "index_agent_tool_executions_on_agent_llm_call_id"
    t.index ["entity_id", "tool_name", "status"], name: "idx_on_entity_id_tool_name_status_997c991bff"
    t.index ["entity_id"], name: "index_agent_tool_executions_on_entity_id"
    t.index ["execution_id"], name: "index_agent_tool_executions_on_execution_id", unique: true
    t.index ["started_at"], name: "index_agent_tool_executions_on_started_at"
  end

  create_table "agent_training_jobs", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "job_id", null: false
    t.string "job_type", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "training_config", default: {}, null: false
    t.jsonb "model_config", default: {}, null: false
    t.integer "traces_used", default: 0, null: false
    t.integer "total_traces_available", default: 0, null: false
    t.jsonb "training_results", default: {}, null: false
    t.decimal "improvement_score", precision: 10, scale: 6
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "scheduled_for"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "status"], name: "index_agent_training_jobs_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_agent_training_jobs_on_entity_id"
    t.index ["job_id"], name: "index_agent_training_jobs_on_job_id", unique: true
    t.index ["scheduled_for"], name: "index_agent_training_jobs_on_scheduled_for"
  end

  create_table "ai_usage_logs", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.bigint "scout_message_id"
    t.string "model", null: false
    t.integer "input_tokens", default: 0
    t.integer "output_tokens", default: 0
    t.integer "total_tokens", default: 0
    t.decimal "cost_cents", precision: 10, scale: 4, default: "0.0"
    t.integer "duration_ms"
    t.string "request_type", default: "chat"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_ai_usage_logs_on_created_at"
    t.index ["entity_id", "created_at"], name: "index_ai_usage_logs_on_entity_id_and_created_at"
    t.index ["entity_id"], name: "index_ai_usage_logs_on_entity_id"
    t.index ["model"], name: "index_ai_usage_logs_on_model"
    t.index ["request_type"], name: "index_ai_usage_logs_on_request_type"
    t.index ["scout_message_id"], name: "index_ai_usage_logs_on_scout_message_id"
    t.index ["user_id", "created_at"], name: "index_ai_usage_logs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_ai_usage_logs_on_user_id"
  end

  create_table "amos_jobs", force: :cascade do |t|
    t.string "job_id", null: false
    t.string "agent_type", null: false
    t.string "session_id", null: false
    t.string "status", default: "queued", null: false
    t.string "status_message"
    t.integer "progress", default: 0
    t.jsonb "input_data", default: {}
    t.jsonb "result_data", default: {}
    t.jsonb "error_data", default: {}
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_type"], name: "index_amos_jobs_on_agent_type"
    t.index ["created_at"], name: "index_amos_jobs_on_created_at"
    t.index ["job_id"], name: "index_amos_jobs_on_job_id", unique: true
    t.index ["session_id", "status"], name: "index_amos_jobs_on_session_id_and_status"
    t.index ["session_id"], name: "index_amos_jobs_on_session_id"
    t.index ["status"], name: "index_amos_jobs_on_status"
  end

  create_table "analytics_connections", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "name"
    t.integer "connection_type"
    t.integer "status"
    t.text "credentials"
    t.jsonb "config"
    t.datetime "last_health_check"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_analytics_connections_on_entity_id"
  end

  create_table "analytics_query_logs", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.bigint "metric_definition_id", null: false
    t.string "metric_name"
    t.string "query_hash"
    t.jsonb "query_params"
    t.text "compiled_query"
    t.integer "rows_returned"
    t.integer "execution_time_ms"
    t.boolean "success"
    t.text "error_message"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_analytics_query_logs_on_entity_id"
    t.index ["metric_definition_id"], name: "index_analytics_query_logs_on_metric_definition_id"
    t.index ["user_id"], name: "index_analytics_query_logs_on_user_id"
  end

  create_table "artifacts", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "source", default: "integration", null: false
    t.bigint "connection_id"
    t.string "operation_id"
    t.jsonb "schema", default: {}, null: false
    t.jsonb "sample", default: [], null: false
    t.integer "row_count"
    t.string "storage_ref"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id"], name: "index_artifacts_on_connection_id"
    t.index ["entity_id"], name: "index_artifacts_on_entity_id"
    t.index ["operation_id"], name: "index_artifacts_on_operation_id"
    t.index ["storage_ref"], name: "index_artifacts_on_storage_ref"
    t.index ["user_id"], name: "index_artifacts_on_user_id"
  end

  create_table "auth_configs", force: :cascade do |t|
    t.bigint "oauth_configuration_id", null: false
    t.string "auth_key", null: false
    t.string "auth_value"
    t.string "auth_placement", default: "header", null: false
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["oauth_configuration_id", "position"], name: "index_auth_configs_on_oauth_configuration_id_and_position"
    t.index ["oauth_configuration_id"], name: "index_auth_configs_on_oauth_configuration_id"
  end

  create_table "business_insights", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "insight_type"
    t.jsonb "content"
    t.float "confidence_score"
    t.bigint "source_conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_business_insights_on_entity_id"
    t.index ["source_conversation_id"], name: "index_business_insights_on_source_conversation_id"
  end

  create_table "business_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name"
    t.string "industry"
    t.text "description"
    t.integer "founded_year"
    t.string "website"
    t.text "values"
    t.text "target_audience"
    t.text "tone_of_voice"
    t.jsonb "knowledge_base"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id"
    t.jsonb "style_guidelines", default: {}, null: false
    t.index ["entity_id"], name: "index_business_profiles_on_entity_id"
    t.index ["style_guidelines"], name: "index_business_profiles_on_style_guidelines", using: :gin
    t.index ["user_id"], name: "index_business_profiles_on_user_id"
  end

  create_table "campaign_groups", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "contact_group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_campaign_groups_on_campaign_id"
    t.index ["contact_group_id"], name: "index_campaign_groups_on_contact_group_id"
  end

  create_table "campaigns", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.string "status"
    t.datetime "scheduled_at"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "email_template_id"
    t.bigint "entity_id", null: false
    t.text "ai_analysis"
    t.datetime "last_analyzed_at"
    t.string "mailgun_tag"
    t.jsonb "mailgun_stats"
    t.integer "opted_out_contacts_count", default: 0, null: false
    t.index ["email_template_id"], name: "index_campaigns_on_email_template_id"
    t.index ["entity_id", "status"], name: "index_campaigns_on_entity_status"
    t.index ["entity_id"], name: "index_campaigns_on_entity_id"
    t.index ["user_id"], name: "index_campaigns_on_user_id"
  end

  create_table "commissions", force: :cascade do |t|
    t.bigint "affiliate_id", null: false
    t.bigint "referral_id", null: false
    t.bigint "entity_id", null: false
    t.string "commission_type"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", default: "USD", null: false
    t.integer "status", default: 0, null: false
    t.bigint "subscription_event_id"
    t.datetime "earned_at"
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["affiliate_id", "status"], name: "index_commissions_on_affiliate_id_and_status"
    t.index ["affiliate_id"], name: "index_commissions_on_affiliate_id"
    t.index ["approved_by_id"], name: "index_commissions_on_approved_by_id"
    t.index ["commission_type"], name: "index_commissions_on_commission_type"
    t.index ["earned_at"], name: "index_commissions_on_earned_at"
    t.index ["entity_id"], name: "index_commissions_on_entity_id"
    t.index ["referral_id"], name: "index_commissions_on_referral_id"
    t.index ["status", "approved_at"], name: "index_commissions_on_status_and_approved_at"
    t.index ["subscription_event_id"], name: "index_commissions_on_subscription_event_id"
  end

  create_table "connections", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "integration_id", null: false
    t.string "name"
    t.integer "status"
    t.jsonb "settings"
    t.jsonb "allowed_operations"
    t.string "rate_limit_tier"
    t.integer "daily_write_budget"
    t.jsonb "scopes_granted"
    t.jsonb "scopes_requested"
    t.datetime "last_health_check"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_connections_on_entity_id"
    t.index ["integration_id"], name: "index_connections_on_integration_id"
  end

  create_table "contact_groups", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id", null: false
    t.index ["entity_id"], name: "index_contact_groups_on_entity_id"
    t.index ["user_id"], name: "index_contact_groups_on_user_id"
  end

  create_table "contact_groups_contacts", force: :cascade do |t|
    t.bigint "contact_id", null: false
    t.bigint "contact_group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_group_id"], name: "index_contact_groups_contacts_on_contact_group_id"
    t.index ["contact_id", "contact_group_id"], name: "index_contacts_groups_uniqueness", unique: true
    t.index ["contact_id"], name: "index_contact_groups_contacts_on_contact_id"
  end

  create_table "contacts", force: :cascade do |t|
    t.string "email"
    t.string "first_name"
    t.string "last_name"
    t.string "status"
    t.string "tags"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "metadata"
    t.bigint "entity_id", null: false
    t.boolean "opted_out", default: false
    t.datetime "opted_out_at"
    t.boolean "lead", default: true, null: false
    t.index ["entity_id", "lead"], name: "index_contacts_on_entity_lead"
    t.index ["entity_id", "status"], name: "index_contacts_on_entity_status"
    t.index ["entity_id"], name: "index_contacts_on_entity_id"
    t.index ["lead"], name: "index_contacts_on_lead"
    t.index ["opted_out"], name: "index_contacts_on_opted_out"
    t.index ["user_id"], name: "index_contacts_on_user_id"
  end

  create_table "conversation_embeddings", force: :cascade do |t|
    t.bigint "scout_message_id"
    t.bigint "entity_id", null: false
    t.text "content"
    t.vector "embedding", limit: 1536
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_conversation_embeddings_on_embedding", opclass: :vector_cosine_ops, using: :ivfflat
    t.index ["entity_id", "created_at"], name: "index_conversation_embeddings_on_entity_id_and_created_at"
    t.index ["entity_id"], name: "index_conversation_embeddings_on_entity_id"
    t.index ["scout_message_id"], name: "index_conversation_embeddings_on_scout_message_id"
  end

  create_table "crawler_conversations", force: :cascade do |t|
    t.bigint "crawler_job_id", null: false
    t.string "role"
    t.text "content"
    t.datetime "timestamp"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["crawler_job_id"], name: "index_crawler_conversations_on_crawler_job_id"
  end

  create_table "crawler_job_logs", force: :cascade do |t|
    t.bigint "crawler_job_id", null: false
    t.text "message"
    t.string "log_level"
    t.datetime "timestamp"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["crawler_job_id"], name: "index_crawler_job_logs_on_crawler_job_id"
  end

  create_table "crawler_jobs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.text "description"
    t.text "generated_code"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "error_message"
    t.text "fix_explanation"
    t.string "conversation_stage"
    t.text "target_urls"
    t.text "test_results"
    t.integer "improvement_attempts"
    t.index ["entity_id"], name: "index_crawler_jobs_on_entity_id"
    t.index ["user_id"], name: "index_crawler_jobs_on_user_id"
  end

  create_table "custom_models", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "model_id", null: false
    t.string "bedrock_model_id"
    t.jsonb "config", default: {}, null: false
    t.string "status", default: "pending"
    t.jsonb "training_metrics", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bedrock_model_id"], name: "index_custom_models_on_bedrock_model_id"
    t.index ["entity_id", "model_id"], name: "index_custom_models_on_entity_id_and_model_id", unique: true
    t.index ["entity_id"], name: "index_custom_models_on_entity_id"
    t.index ["status"], name: "index_custom_models_on_status"
    t.index ["user_id"], name: "index_custom_models_on_user_id"
  end

  create_table "custom_plugins", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "plugin_type", null: false
    t.string "plugin_id", null: false
    t.jsonb "spec", default: {}, null: false
    t.text "code"
    t.string "status", default: "pending"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "plugin_type", "plugin_id"], name: "idx_custom_plugins_unique", unique: true
    t.index ["entity_id"], name: "index_custom_plugins_on_entity_id"
    t.index ["plugin_type"], name: "index_custom_plugins_on_plugin_type"
    t.index ["status"], name: "index_custom_plugins_on_status"
    t.index ["user_id"], name: "index_custom_plugins_on_user_id"
  end

  create_table "data_contracts", force: :cascade do |t|
    t.string "name"
    t.string "version"
    t.string "entity_type"
    t.jsonb "schema_definition"
    t.jsonb "privacy_rules"
    t.string "freshness_slo"
    t.boolean "is_active"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "document_analytics", force: :cascade do |t|
    t.bigint "rag_document_id", null: false
    t.date "date", null: false
    t.integer "view_count", default: 0
    t.integer "query_count", default: 0
    t.float "relevance_score_avg"
    t.integer "chunk_retrieval_count", default: 0
    t.integer "unique_users", default: 0
    t.integer "download_count", default: 0
    t.jsonb "search_queries", default: []
    t.jsonb "user_breakdown", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date", "view_count"], name: "index_document_analytics_on_date_and_view_count"
    t.index ["date"], name: "index_document_analytics_on_date"
    t.index ["rag_document_id", "date"], name: "index_document_analytics_on_rag_document_id_and_date", unique: true
    t.index ["rag_document_id"], name: "index_document_analytics_on_rag_document_id"
  end

  create_table "document_annotations", force: :cascade do |t|
    t.bigint "rag_document_id", null: false
    t.bigint "user_id", null: false
    t.integer "page_number"
    t.jsonb "position"
    t.text "content", null: false
    t.string "annotation_type"
    t.string "color"
    t.boolean "resolved", default: false
    t.bigint "resolved_by_id"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["rag_document_id", "page_number"], name: "index_document_annotations_on_rag_document_id_and_page_number"
    t.index ["rag_document_id"], name: "index_document_annotations_on_rag_document_id"
    t.index ["resolved_by_id"], name: "index_document_annotations_on_resolved_by_id"
    t.index ["user_id", "created_at"], name: "index_document_annotations_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_document_annotations_on_user_id"
  end

  create_table "document_chunks", force: :cascade do |t|
    t.bigint "knowledge_document_id", null: false
    t.text "content", null: false
    t.integer "chunk_index"
    t.vector "embedding", limit: 1536
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_document_chunks_on_embedding", opclass: :vector_cosine_ops, using: :ivfflat
    t.index ["knowledge_document_id", "chunk_index"], name: "index_document_chunks_on_knowledge_document_id_and_chunk_index"
    t.index ["knowledge_document_id"], name: "index_document_chunks_on_knowledge_document_id"
  end

  create_table "document_relationships", force: :cascade do |t|
    t.bigint "source_document_id", null: false
    t.bigint "target_document_id", null: false
    t.string "relationship_type", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["relationship_type"], name: "index_document_relationships_on_relationship_type"
    t.index ["source_document_id", "target_document_id", "relationship_type"], name: "idx_doc_relationship_unique", unique: true
    t.index ["source_document_id"], name: "index_document_relationships_on_source_document_id"
    t.index ["target_document_id"], name: "index_document_relationships_on_target_document_id"
  end

  create_table "document_subject_assignments", force: :cascade do |t|
    t.bigint "rag_document_id", null: false
    t.bigint "document_subject_id", null: false
    t.bigint "assigned_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_by_id"], name: "index_document_subject_assignments_on_assigned_by_id"
    t.index ["document_subject_id"], name: "index_document_subject_assignments_on_document_subject_id"
    t.index ["rag_document_id", "document_subject_id"], name: "idx_doc_subject_unique", unique: true
    t.index ["rag_document_id"], name: "index_document_subject_assignments_on_rag_document_id"
  end

  create_table "document_subjects", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "name", null: false
    t.text "description"
    t.bigint "parent_id"
    t.string "color", limit: 7
    t.string "icon", limit: 50
    t.jsonb "metadata", default: {}
    t.jsonb "rules", default: {}
    t.boolean "is_smart_folder", default: false
    t.integer "position", default: 0
    t.integer "documents_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "name", "parent_id"], name: "index_document_subjects_on_entity_id_and_name_and_parent_id", unique: true
    t.index ["entity_id", "position"], name: "index_document_subjects_on_entity_id_and_position"
    t.index ["entity_id"], name: "index_document_subjects_on_entity_id"
    t.index ["is_smart_folder"], name: "index_document_subjects_on_is_smart_folder"
    t.index ["parent_id"], name: "index_document_subjects_on_parent_id"
  end

  create_table "document_tag_assignments", force: :cascade do |t|
    t.bigint "rag_document_id", null: false
    t.bigint "document_tag_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_tag_id"], name: "index_document_tag_assignments_on_document_tag_id"
    t.index ["rag_document_id", "document_tag_id"], name: "idx_doc_tag_unique", unique: true
    t.index ["rag_document_id"], name: "index_document_tag_assignments_on_rag_document_id"
  end

  create_table "document_tags", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "name", limit: 100, null: false
    t.string "category", limit: 50
    t.string "color", limit: 7
    t.integer "usage_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "category"], name: "index_document_tags_on_entity_id_and_category"
    t.index ["entity_id", "name", "category"], name: "index_document_tags_on_entity_id_and_name_and_category", unique: true
    t.index ["entity_id"], name: "index_document_tags_on_entity_id"
    t.index ["usage_count"], name: "index_document_tags_on_usage_count"
  end

  create_table "dripped_campaigns", force: :cascade do |t|
    t.bigint "original_campaign_id", null: false
    t.bigint "follow_up_campaign_id", null: false
    t.integer "delay_days", default: 3, null: false
    t.string "condition"
    t.string "condition_value"
    t.boolean "active", default: true, null: false
    t.datetime "scheduled_at"
    t.integer "sequence_position", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["follow_up_campaign_id"], name: "index_dripped_campaigns_on_follow_up_campaign_id"
    t.index ["original_campaign_id", "sequence_position"], name: "idx_dripped_campaigns_on_original_campaign_and_position", unique: true
    t.index ["original_campaign_id"], name: "index_dripped_campaigns_on_original_campaign_id"
  end

  create_table "email_deliveries", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "contact_id", null: false
    t.string "status"
    t.datetime "sent_at"
    t.datetime "opened_at"
    t.datetime "clicked_at"
    t.bigint "email_template_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "error_message"
    t.string "mailgun_message_id"
    t.string "mailgun_status"
    t.text "notes"
    t.string "unsubscribe_token"
    t.index ["campaign_id", "id"], name: "index_email_deliveries_on_campaign_id_and_id"
    t.index ["campaign_id", "status", "sent_at"], name: "index_email_deliveries_on_campaign_status_sent"
    t.index ["campaign_id", "status"], name: "index_email_deliveries_on_campaign_id_and_status"
    t.index ["campaign_id"], name: "index_email_deliveries_on_campaign_id"
    t.index ["contact_id"], name: "index_email_deliveries_on_contact_id"
    t.index ["email_template_id"], name: "index_email_deliveries_on_email_template_id"
    t.index ["status"], name: "index_email_deliveries_on_status"
    t.index ["unsubscribe_token"], name: "index_email_deliveries_on_unsubscribe_token", unique: true
  end

  create_table "email_sequences", force: :cascade do |t|
    t.string "name", null: false
    t.text "goal"
    t.string "status", default: "draft", null: false
    t.bigint "contact_group_id", null: false
    t.bigint "entity_id", null: false
    t.integer "enrolled_count", default: 0
    t.integer "completed_count", default: 0
    t.integer "active_count", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_group_id"], name: "index_email_sequences_on_contact_group_id"
    t.index ["entity_id", "status"], name: "index_email_sequences_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_email_sequences_on_entity_id"
    t.index ["status"], name: "index_email_sequences_on_status"
  end

  create_table "email_templates", force: :cascade do |t|
    t.string "name"
    t.string "subject"
    t.text "body"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id", null: false
    t.index ["entity_id"], name: "index_email_templates_on_entity_id"
    t.index ["user_id"], name: "index_email_templates_on_user_id"
  end

  create_table "entities", force: :cascade do |t|
    t.string "name"
    t.string "subdomain"
    t.string "slug"
    t.string "status", default: "active"
    t.jsonb "settings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "platform_tier", default: "standard"
    t.integer "custom_plugin_limit", default: 5
    t.integer "custom_model_limit", default: 1
    t.boolean "marketplace_vendor", default: false
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.string "subscription_status"
    t.datetime "trial_ends_at"
    t.datetime "current_period_end"
    t.integer "token_usage", default: 0
    t.integer "token_limit"
    t.string "plan_tier"
    t.string "bedrock_kb_id"
    t.string "bedrock_data_source_id"
    t.string "opensearch_collection_arn"
    t.boolean "use_bedrock_kb", default: false
    t.string "preferred_ocr_provider", default: "auto"
    t.boolean "track_ocr_metrics", default: false
    t.boolean "notify_on_ocr_failure", default: false
    t.jsonb "aws_config", default: {}
    t.jsonb "cost_thresholds", default: {}
    t.string "billing_tier", default: "standard"
    t.jsonb "usage_limits", default: {}
    t.boolean "overage_charges_enabled", default: false
    t.decimal "prepaid_credits", precision: 10, scale: 2, default: "0.0"
    t.jsonb "aws_monthly_costs", default: {}
    t.decimal "aws_cost_limit_usd", precision: 10, scale: 2
    t.decimal "aws_cost_alert_threshold", precision: 10, scale: 2
    t.datetime "last_cost_alert_sent_at"
    t.string "bedrock_knowledge_base_id"
    t.string "bedrock_kb_status"
    t.string "bedrock_last_ingestion_job_id"
    t.index ["bedrock_kb_id"], name: "index_entities_on_bedrock_kb_id"
    t.index ["bedrock_kb_status"], name: "index_entities_on_bedrock_kb_status"
    t.index ["bedrock_knowledge_base_id"], name: "index_entities_on_bedrock_knowledge_base_id"
    t.index ["bedrock_last_ingestion_job_id"], name: "index_entities_on_bedrock_last_ingestion_job_id"
    t.index ["slug"], name: "index_entities_on_slug", unique: true
    t.index ["stripe_customer_id"], name: "index_entities_on_stripe_customer_id"
    t.index ["stripe_subscription_id"], name: "index_entities_on_stripe_subscription_id"
    t.index ["subdomain"], name: "index_entities_on_subdomain", unique: true
    t.index ["subscription_status"], name: "index_entities_on_subscription_status"
    t.index ["use_bedrock_kb"], name: "index_entities_on_use_bedrock_kb"
  end

  create_table "entity_cost_reports", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "report_period"
    t.date "period_start"
    t.date "period_end"
    t.decimal "textract_cost_usd", precision: 10, scale: 2, default: "0.0"
    t.decimal "comprehend_cost_usd", precision: 10, scale: 2, default: "0.0"
    t.decimal "bedrock_cost_usd", precision: 10, scale: 2, default: "0.0"
    t.decimal "s3_cost_usd", precision: 10, scale: 2, default: "0.0"
    t.decimal "total_cost_usd", precision: 10, scale: 2, default: "0.0"
    t.integer "documents_processed", default: 0
    t.integer "pages_processed", default: 0
    t.integer "api_calls_total", default: 0
    t.bigint "bytes_processed", default: 0
    t.jsonb "service_usage", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "report_period"], name: "index_entity_cost_reports_on_entity_id_and_report_period", unique: true
    t.index ["entity_id"], name: "index_entity_cost_reports_on_entity_id"
    t.index ["report_period"], name: "index_entity_cost_reports_on_report_period"
    t.index ["total_cost_usd"], name: "index_entity_cost_reports_on_total_cost_usd"
  end

  create_table "entity_cost_summaries", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.date "summary_date", null: false
    t.decimal "ai_chat_cost", precision: 10, scale: 2, default: "0.0"
    t.decimal "email_cost", precision: 10, scale: 2, default: "0.0"
    t.decimal "sms_cost", precision: 10, scale: 2, default: "0.0"
    t.decimal "storage_cost", precision: 10, scale: 2, default: "0.0"
    t.decimal "compute_cost", precision: 10, scale: 2, default: "0.0"
    t.decimal "bandwidth_cost", precision: 10, scale: 2, default: "0.0"
    t.decimal "integration_cost", precision: 10, scale: 2, default: "0.0"
    t.decimal "other_costs", precision: 10, scale: 2, default: "0.0"
    t.decimal "total_cost", precision: 10, scale: 2, default: "0.0"
    t.integer "ai_conversations", default: 0
    t.integer "emails_sent", default: 0
    t.integer "documents_processed", default: 0
    t.integer "api_calls", default: 0
    t.integer "landing_page_views", default: 0
    t.integer "background_jobs", default: 0
    t.float "avg_response_time_ms"
    t.float "error_rate"
    t.integer "support_tickets", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "summary_date"], name: "index_entity_cost_summaries_on_entity_id_and_summary_date", unique: true
    t.index ["entity_id", "total_cost"], name: "index_entity_cost_summaries_on_entity_id_and_total_cost"
    t.index ["entity_id"], name: "index_entity_cost_summaries_on_entity_id"
    t.index ["summary_date"], name: "index_entity_cost_summaries_on_summary_date"
  end

  create_table "entity_usage_metrics", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "category", null: false
    t.string "service", null: false
    t.string "usage_type"
    t.decimal "quantity", precision: 20, scale: 6
    t.decimal "rate", precision: 10, scale: 8
    t.decimal "calculated_cost_usd", precision: 10, scale: 6
    t.jsonb "metadata", default: {}
    t.datetime "tracked_at", null: false
    t.string "tracked_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_entity_usage_metrics_on_category"
    t.index ["entity_id", "category", "service", "tracked_at"], name: "idx_entity_metrics_full"
    t.index ["entity_id", "category", "tracked_at"], name: "idx_on_entity_id_category_tracked_at_262cde385d"
    t.index ["entity_id", "tracked_at"], name: "index_entity_usage_metrics_on_entity_id_and_tracked_at"
    t.index ["entity_id"], name: "index_entity_usage_metrics_on_entity_id"
    t.index ["tracked_at"], name: "index_entity_usage_metrics_on_tracked_at"
  end

  create_table "entity_users", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "member"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "user_id"], name: "index_entity_users_on_entity_id_and_user_id", unique: true
    t.index ["entity_id"], name: "index_entity_users_on_entity_id"
    t.index ["user_id"], name: "index_entity_users_on_user_id"
  end

  create_table "image_assets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "title"
    t.text "description"
    t.string "source", default: "upload", null: false
    t.string "tags", default: [], array: true
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_image_assets_on_entity_id"
    t.index ["tags"], name: "index_image_assets_on_tags", using: :gin
    t.index ["user_id"], name: "index_image_assets_on_user_id"
  end

  create_table "integration_credentials", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.string "name"
    t.text "credentials"
    t.string "auth_method"
    t.string "auth_field_name"
    t.string "token_type"
    t.datetime "expires_at"
    t.datetime "rotates_at"
    t.datetime "rotated_at"
    t.datetime "last_refresh_at"
    t.text "last_refresh_error"
    t.integer "status"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id"], name: "index_integration_credentials_on_connection_id"
  end

  create_table "integration_embeddings", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "integration_id", null: false
    t.string "resource_type"
    t.string "resource_id"
    t.text "content"
    t.vector "embedding", limit: 1536
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_integration_embeddings_on_embedding", opclass: :vector_cosine_ops, using: :ivfflat
    t.index ["entity_id", "integration_id", "resource_type"], name: "idx_on_entity_id_integration_id_resource_type_3cebcacba6"
    t.index ["entity_id"], name: "index_integration_embeddings_on_entity_id"
    t.index ["integration_id"], name: "index_integration_embeddings_on_integration_id"
  end

  create_table "integration_logs", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.bigint "user_id", null: false
    t.bigint "scout_message_id"
    t.bigint "integration_operation_id", null: false
    t.string "correlation_id"
    t.string "operation_id"
    t.string "endpoint"
    t.string "http_method"
    t.jsonb "request_headers"
    t.jsonb "request_body"
    t.integer "response_status"
    t.jsonb "response_headers"
    t.binary "response_body_encrypted"
    t.integer "duration_ms"
    t.integer "rate_limit_remaining"
    t.datetime "rate_limit_reset_at"
    t.text "error_message"
    t.integer "retry_count"
    t.string "idempotency_key"
    t.boolean "dry_run"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "created_at"], name: "index_integration_logs_on_connection_created"
    t.index ["connection_id"], name: "index_integration_logs_on_connection_id"
    t.index ["correlation_id"], name: "index_integration_logs_on_correlation_id"
    t.index ["integration_operation_id"], name: "index_integration_logs_on_integration_operation_id"
    t.index ["response_status"], name: "index_integration_logs_on_response_status"
    t.index ["scout_message_id"], name: "index_integration_logs_on_scout_message_id"
    t.index ["user_id"], name: "index_integration_logs_on_user_id"
  end

  create_table "integration_operations", force: :cascade do |t|
    t.bigint "integration_id", null: false
    t.string "operation_id"
    t.string "name"
    t.text "description"
    t.string "http_method"
    t.string "path_template"
    t.jsonb "request_schema"
    t.jsonb "response_schema"
    t.integer "pagination_strategy"
    t.boolean "is_idempotent"
    t.boolean "requires_confirmation"
    t.integer "max_limit"
    t.text "documentation"
    t.jsonb "examples"
    t.string "version"
    t.datetime "deprecated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_enabled", default: true, null: false
    t.index ["integration_id"], name: "index_integration_operations_on_integration_id"
    t.index ["is_enabled"], name: "index_integration_operations_on_is_enabled"
    t.index ["operation_id"], name: "index_integration_operations_on_operation_id"
  end

  create_table "integrations", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.string "category"
    t.integer "auth_type"
    t.jsonb "auth_config"
    t.string "api_base_url"
    t.jsonb "allowed_hosts"
    t.string "documentation_url"
    t.string "icon_url"
    t.text "description"
    t.boolean "is_active"
    t.boolean "is_verified"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_integrations_on_name", unique: true
    t.index ["slug"], name: "index_integrations_on_slug", unique: true
  end

  create_table "knowledge_documents", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "title", null: false
    t.text "content", null: false
    t.string "source_type"
    t.string "source_url"
    t.jsonb "metadata", default: {}
    t.vector "embedding", limit: 1536
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_knowledge_documents_on_embedding", opclass: :vector_cosine_ops, using: :ivfflat
    t.index ["entity_id", "created_at"], name: "index_knowledge_documents_on_entity_id_and_created_at"
    t.index ["entity_id"], name: "index_knowledge_documents_on_entity_id"
  end

  create_table "landing_page_chat_messages", force: :cascade do |t|
    t.bigint "landing_page_id", null: false
    t.text "content"
    t.string "role"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["landing_page_id"], name: "index_landing_page_chat_messages_on_landing_page_id"
    t.index ["user_id"], name: "index_landing_page_chat_messages_on_user_id"
  end

  create_table "landing_page_submissions", force: :cascade do |t|
    t.bigint "landing_page_id", null: false
    t.bigint "contact_id"
    t.string "form_type", null: false
    t.jsonb "submission_data", default: {}, null: false
    t.string "source_ip"
    t.text "user_agent"
    t.datetime "submitted_at", null: false
    t.datetime "processed_at"
    t.string "status", default: "pending", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "session_id"
    t.string "referrer"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_id", "submitted_at"], name: "index_landing_page_submissions_on_contact_id_and_submitted_at"
    t.index ["contact_id"], name: "index_landing_page_submissions_on_contact_id"
    t.index ["form_type"], name: "index_landing_page_submissions_on_form_type"
    t.index ["landing_page_id", "submitted_at"], name: "idx_on_landing_page_id_submitted_at_86b17f44bd"
    t.index ["landing_page_id"], name: "index_landing_page_submissions_on_landing_page_id"
    t.index ["session_id"], name: "index_landing_page_submissions_on_session_id"
    t.index ["status"], name: "index_landing_page_submissions_on_status"
    t.index ["submitted_at"], name: "index_landing_page_submissions_on_submitted_at"
  end

  create_table "landing_page_versions", force: :cascade do |t|
    t.bigint "landing_page_id", null: false
    t.jsonb "content"
    t.string "headline"
    t.text "subheadline"
    t.string "cta_text"
    t.string "cta_url"
    t.string "primary_color"
    t.string "secondary_color"
    t.string "font_family"
    t.boolean "ai_applied"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["landing_page_id"], name: "index_landing_page_versions_on_landing_page_id"
  end

  create_table "landing_pages", force: :cascade do |t|
    t.string "title", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "status", default: "draft"
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "campaign_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "html_content"
    t.jsonb "metadata", default: {}, null: false
    t.index ["campaign_id"], name: "index_landing_pages_on_campaign_id"
    t.index ["entity_id", "status"], name: "index_landing_pages_on_entity_status"
    t.index ["entity_id"], name: "index_landing_pages_on_entity_id"
    t.index ["metadata"], name: "index_landing_pages_on_metadata", using: :gin
    t.index ["slug"], name: "index_landing_pages_on_slug", unique: true
    t.index ["user_id"], name: "index_landing_pages_on_user_id"
  end

  create_table "mcp_connections", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "system_type", null: false
    t.string "name", null: false
    t.text "encrypted_config"
    t.integer "status", default: 0, null: false
    t.jsonb "metadata", default: {}
    t.datetime "last_sync_at"
    t.datetime "last_health_check_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "system_type"], name: "index_mcp_connections_on_entity_id_and_system_type"
    t.index ["entity_id"], name: "index_mcp_connections_on_entity_id"
    t.index ["last_sync_at"], name: "index_mcp_connections_on_last_sync_at"
    t.index ["status"], name: "index_mcp_connections_on_status"
  end

  create_table "metric_definitions", force: :cascade do |t|
    t.string "name"
    t.string "version"
    t.text "description"
    t.text "expression"
    t.string "source"
    t.string "time_column"
    t.string "grain_default"
    t.jsonb "dimensions"
    t.jsonb "filters_default"
    t.jsonb "quality_rules"
    t.string "owner"
    t.string "category"
    t.boolean "is_active"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "model_permissions", force: :cascade do |t|
    t.bigint "custom_model_id", null: false
    t.bigint "entity_id", null: false
    t.string "permission_type", null: false
    t.integer "usage_limit"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["custom_model_id", "entity_id", "permission_type"], name: "idx_model_perms", unique: true
    t.index ["custom_model_id"], name: "index_model_permissions_on_custom_model_id"
    t.index ["entity_id"], name: "index_model_permissions_on_entity_id"
  end

  create_table "o_auth_configurations", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "integration_id", null: false
    t.string "client_id", null: false
    t.string "client_secret", null: false
    t.string "redirect_uri", null: false
    t.text "scopes"
    t.string "authorize_url", null: false
    t.string "token_url", null: false
    t.text "credentials"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_o_auth_configurations_on_client_id"
    t.index ["entity_id", "integration_id"], name: "index_oauth_configs_on_entity_integration", unique: true
    t.index ["entity_id"], name: "index_o_auth_configurations_on_entity_id"
    t.index ["integration_id"], name: "index_o_auth_configurations_on_integration_id"
  end

  create_table "oauth_configurations", force: :cascade do |t|
    t.bigint "integration_id", null: false
    t.string "client_id"
    t.string "client_secret"
    t.string "redirect_uri"
    t.text "scopes"
    t.jsonb "credentials", default: {}
    t.jsonb "metadata", default: {}
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "authorize_url"
    t.string "token_url"
    t.jsonb "callback_params", default: [], null: false
    t.text "test_endpoint"
    t.index ["callback_params"], name: "index_oauth_configurations_on_callback_params", using: :gin
    t.index ["integration_id"], name: "index_oauth_configurations_on_integration_id", unique: true
  end

  create_table "observability_events", force: :cascade do |t|
    t.string "event_type", null: false
    t.bigint "entity_id"
    t.bigint "user_id"
    t.string "resource_type"
    t.bigint "resource_id"
    t.jsonb "metadata", default: {}
    t.integer "duration_ms"
    t.string "status"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_observability_events_on_created_at"
    t.index ["entity_id", "created_at"], name: "index_observability_events_on_entity_id_and_created_at"
    t.index ["entity_id"], name: "index_observability_events_on_entity_id"
    t.index ["event_type"], name: "index_observability_events_on_event_type"
    t.index ["resource_type", "resource_id"], name: "index_observability_events_on_resource_type_and_resource_id"
    t.index ["status"], name: "index_observability_events_on_status"
    t.index ["user_id"], name: "index_observability_events_on_user_id"
  end

  create_table "ocr_metrics", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "rag_document_id"
    t.string "provider"
    t.string "operation_type"
    t.string "file_path"
    t.integer "file_size_bytes"
    t.integer "page_count"
    t.integer "processing_time_ms"
    t.boolean "fallback_used", default: false
    t.string "fallback_reason"
    t.decimal "estimated_cost_usd", precision: 10, scale: 6
    t.string "pricing_tier"
    t.jsonb "cost_breakdown"
    t.string "aws_request_id"
    t.integer "api_calls_count", default: 1
    t.integer "characters_processed"
    t.integer "tables_extracted"
    t.integer "forms_extracted"
    t.float "average_confidence"
    t.string "status"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_ocr_metrics_on_created_at"
    t.index ["entity_id", "created_at"], name: "index_ocr_metrics_on_entity_id_and_created_at"
    t.index ["entity_id", "provider", "created_at"], name: "index_ocr_metrics_on_entity_id_and_provider_and_created_at"
    t.index ["entity_id"], name: "index_ocr_metrics_on_entity_id"
    t.index ["provider"], name: "index_ocr_metrics_on_provider"
    t.index ["rag_document_id"], name: "index_ocr_metrics_on_rag_document_id"
  end

  create_table "payouts", force: :cascade do |t|
    t.bigint "affiliate_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", default: "USD", null: false
    t.string "payment_method"
    t.string "payment_reference"
    t.integer "status", default: 0, null: false
    t.date "payout_date"
    t.text "notes"
    t.integer "commission_ids", default: [], array: true
    t.bigint "processed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["affiliate_id", "status"], name: "index_payouts_on_affiliate_id_and_status"
    t.index ["affiliate_id"], name: "index_payouts_on_affiliate_id"
    t.index ["payout_date"], name: "index_payouts_on_payout_date"
    t.index ["processed_by_id"], name: "index_payouts_on_processed_by_id"
    t.index ["status"], name: "index_payouts_on_status"
  end

  create_table "pipeline_artifacts", force: :cascade do |t|
    t.bigint "pipeline_execution_id", null: false
    t.bigint "agent_execution_id"
    t.string "artifact_type", null: false
    t.string "file_name", null: false
    t.text "content"
    t.string "storage_path"
    t.integer "file_size", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_execution_id"], name: "index_pipeline_artifacts_on_agent_execution_id"
    t.index ["artifact_type"], name: "index_pipeline_artifacts_on_artifact_type"
    t.index ["pipeline_execution_id", "artifact_type"], name: "idx_on_pipeline_execution_id_artifact_type_b27a739ffc"
    t.index ["pipeline_execution_id"], name: "index_pipeline_artifacts_on_pipeline_execution_id"
  end

  create_table "pipeline_events", force: :cascade do |t|
    t.bigint "pipeline_execution_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload", default: {}
    t.string "source", null: false
    t.boolean "processed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_pipeline_events_on_event_type"
    t.index ["pipeline_execution_id", "event_type"], name: "index_pipeline_events_on_pipeline_execution_id_and_event_type"
    t.index ["pipeline_execution_id"], name: "index_pipeline_events_on_pipeline_execution_id"
    t.index ["processed", "created_at"], name: "index_pipeline_events_on_processed_and_created_at"
    t.index ["processed"], name: "index_pipeline_events_on_processed"
    t.index ["source"], name: "index_pipeline_events_on_source"
  end

  create_table "pipeline_executions", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "mcp_connection_id", null: false
    t.string "ticket_id", null: false
    t.string "ticket_system", null: false
    t.string "ticket_url"
    t.string "ticket_title", null: false
    t.text "ticket_description"
    t.integer "priority", default: 2
    t.jsonb "ticket_metadata", default: {}
    t.bigint "git_connection_id"
    t.string "repository"
    t.string "branch_name"
    t.string "pr_id"
    t.string "pr_url"
    t.integer "status", default: 0, null: false
    t.jsonb "state_history", default: []
    t.datetime "state_changed_at"
    t.integer "total_tokens_used", default: 0
    t.decimal "total_cost", precision: 10, scale: 4, default: "0.0"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slack_thread_ts"
    t.index ["completed_at"], name: "index_pipeline_executions_on_completed_at"
    t.index ["entity_id", "status"], name: "index_pipeline_executions_on_entity_id_and_status"
    t.index ["entity_id", "ticket_id", "mcp_connection_id"], name: "index_pipeline_executions_on_unique_ticket", unique: true
    t.index ["entity_id", "ticket_system"], name: "index_pipeline_executions_on_entity_id_and_ticket_system"
    t.index ["entity_id"], name: "index_pipeline_executions_on_entity_id"
    t.index ["git_connection_id"], name: "index_pipeline_executions_on_git_connection_id"
    t.index ["mcp_connection_id"], name: "index_pipeline_executions_on_mcp_connection_id"
    t.index ["priority"], name: "index_pipeline_executions_on_priority"
    t.index ["slack_thread_ts"], name: "index_pipeline_executions_on_slack_thread_ts"
    t.index ["started_at"], name: "index_pipeline_executions_on_started_at"
    t.index ["status"], name: "index_pipeline_executions_on_status"
    t.index ["ticket_system"], name: "index_pipeline_executions_on_ticket_system"
  end

  create_table "pipeline_interactions", force: :cascade do |t|
    t.bigint "pipeline_execution_id", null: false
    t.bigint "user_id"
    t.string "interaction_type", null: false
    t.string "channel", null: false
    t.string "external_thread_id"
    t.text "question", null: false
    t.text "response"
    t.integer "status", default: 0, null: false
    t.datetime "asked_at", null: false
    t.datetime "answered_at"
    t.datetime "timeout_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel"], name: "index_pipeline_interactions_on_channel"
    t.index ["external_thread_id"], name: "index_pipeline_interactions_on_external_thread_id"
    t.index ["interaction_type"], name: "index_pipeline_interactions_on_interaction_type"
    t.index ["pipeline_execution_id", "status"], name: "idx_on_pipeline_execution_id_status_6bd028d347"
    t.index ["pipeline_execution_id"], name: "index_pipeline_interactions_on_pipeline_execution_id"
    t.index ["status"], name: "index_pipeline_interactions_on_status"
    t.index ["user_id"], name: "index_pipeline_interactions_on_user_id"
  end

  create_table "plugin_permissions", force: :cascade do |t|
    t.bigint "custom_plugin_id", null: false
    t.bigint "user_id"
    t.bigint "entity_id"
    t.string "permission_type", null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["custom_plugin_id", "entity_id", "permission_type"], name: "idx_plugin_perms_entity", unique: true
    t.index ["custom_plugin_id", "user_id", "permission_type"], name: "idx_plugin_perms_user", unique: true
    t.index ["custom_plugin_id"], name: "index_plugin_permissions_on_custom_plugin_id"
    t.index ["entity_id"], name: "index_plugin_permissions_on_entity_id"
    t.index ["user_id"], name: "index_plugin_permissions_on_user_id"
  end

  create_table "plugin_reviews", force: :cascade do |t|
    t.bigint "shared_plugin_id", null: false
    t.bigint "user_id", null: false
    t.integer "rating", null: false
    t.text "review"
    t.boolean "verified_purchase", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["rating"], name: "index_plugin_reviews_on_rating"
    t.index ["shared_plugin_id", "user_id"], name: "index_plugin_reviews_on_shared_plugin_id_and_user_id", unique: true
    t.index ["shared_plugin_id"], name: "index_plugin_reviews_on_shared_plugin_id"
    t.index ["user_id"], name: "index_plugin_reviews_on_user_id"
  end

  create_table "plugin_transactions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "shared_plugin_id"
    t.bigint "shared_model_id"
    t.string "transaction_type"
    t.decimal "amount", precision: 10, scale: 2
    t.string "currency", default: "USD"
    t.string "status"
    t.jsonb "payment_details", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "created_at"], name: "index_plugin_transactions_on_entity_id_and_created_at"
    t.index ["entity_id"], name: "index_plugin_transactions_on_entity_id"
    t.index ["shared_model_id"], name: "index_plugin_transactions_on_shared_model_id"
    t.index ["shared_plugin_id"], name: "index_plugin_transactions_on_shared_plugin_id"
    t.index ["status"], name: "index_plugin_transactions_on_status"
    t.index ["user_id"], name: "index_plugin_transactions_on_user_id"
  end

  create_table "plugin_usages", force: :cascade do |t|
    t.string "plugin_id", null: false
    t.bigint "user_id"
    t.bigint "entity_id"
    t.integer "execution_count", default: 1
    t.float "memory_mb"
    t.float "cpu_seconds"
    t.integer "api_calls"
    t.integer "tokens_used"
    t.float "duration_ms"
    t.jsonb "metrics", default: {}
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_plugin_usages_on_created_at"
    t.index ["entity_id", "plugin_id", "created_at"], name: "idx_plugin_usage_analytics"
    t.index ["entity_id"], name: "index_plugin_usages_on_entity_id"
    t.index ["plugin_id", "created_at"], name: "index_plugin_usages_on_plugin_id_and_created_at"
    t.index ["plugin_id"], name: "index_plugin_usages_on_plugin_id"
    t.index ["user_id"], name: "index_plugin_usages_on_user_id"
  end

  create_table "policy_rules", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "name"
    t.string "resource_type"
    t.string "resource_id"
    t.string "agent_role"
    t.string "action"
    t.jsonb "conditions"
    t.integer "max_daily_calls"
    t.integer "max_write_calls"
    t.boolean "requires_confirmation"
    t.boolean "is_active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_policy_rules_on_entity_id"
  end

  create_table "rag_chunks", force: :cascade do |t|
    t.bigint "rag_document_id", null: false
    t.text "content", null: false
    t.vector "embedding", limit: 1536
    t.string "pinecone_vector_id"
    t.jsonb "metadata", default: {}
    t.integer "chunk_index"
    t.integer "token_count"
    t.string "chunk_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "to_tsvector('english'::regconfig, content)", name: "index_rag_chunks_on_content_tsvector", using: :gin
    t.index ["embedding"], name: "index_rag_chunks_on_embedding", opclass: :vector_cosine_ops, using: :ivfflat
    t.index ["pinecone_vector_id"], name: "index_rag_chunks_on_pinecone_vector_id"
    t.index ["rag_document_id", "chunk_index"], name: "index_rag_chunks_on_rag_document_id_and_chunk_index"
    t.index ["rag_document_id"], name: "index_rag_chunks_on_rag_document_id"
  end

  create_table "rag_documents", force: :cascade do |t|
    t.bigint "rag_store_id", null: false
    t.string "original_filename", null: false
    t.string "content_type"
    t.integer "file_size_bytes"
    t.string "file_hash"
    t.jsonb "docling_metadata", default: {}
    t.jsonb "extracted_tables", default: []
    t.jsonb "extracted_images", default: []
    t.jsonb "document_structure", default: {}
    t.integer "page_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "textract_status"
    t.string "textract_job_id"
    t.jsonb "textract_result"
    t.jsonb "comprehend_analysis"
    t.string "bedrock_ingestion_status"
    t.datetime "bedrock_ingested_at"
    t.string "processing_status"
    t.datetime "deleted_at"
    t.jsonb "metadata", default: {}
    t.string "title", limit: 500
    t.text "summary"
    t.string "author"
    t.date "document_date"
    t.string "language", limit: 10, default: "en"
    t.boolean "ocr_performed", default: false
    t.integer "view_count", default: 0
    t.integer "download_count", default: 0
    t.datetime "last_accessed_at", precision: nil
    t.bigint "last_accessed_by_id"
    t.integer "version", default: 1
    t.bigint "parent_document_id"
    t.boolean "is_latest_version", default: true
    t.tsvector "full_text_search_vector"
    t.jsonb "keywords", default: []
    t.jsonb "custom_metadata", default: {}
    t.index ["author"], name: "index_rag_documents_on_author"
    t.index ["bedrock_ingestion_status"], name: "index_rag_documents_on_bedrock_ingestion_status"
    t.index ["deleted_at"], name: "index_rag_documents_on_deleted_at"
    t.index ["document_date"], name: "index_rag_documents_on_document_date"
    t.index ["file_hash"], name: "index_rag_documents_on_file_hash"
    t.index ["full_text_search_vector"], name: "index_rag_documents_on_full_text_search_vector", using: :gin
    t.index ["is_latest_version"], name: "index_rag_documents_on_is_latest_version"
    t.index ["language"], name: "index_rag_documents_on_language"
    t.index ["parent_document_id"], name: "index_rag_documents_on_parent_document_id"
    t.index ["processing_status"], name: "index_rag_documents_on_processing_status"
    t.index ["rag_store_id", "file_hash"], name: "index_rag_documents_on_rag_store_id_and_file_hash"
    t.index ["rag_store_id"], name: "index_rag_documents_on_rag_store_id"
    t.index ["textract_job_id"], name: "index_rag_documents_on_textract_job_id"
    t.index ["textract_status"], name: "index_rag_documents_on_textract_status"
    t.index ["view_count"], name: "index_rag_documents_on_view_count"
  end

  create_table "rag_processing_jobs", force: :cascade do |t|
    t.bigint "rag_store_id", null: false
    t.string "job_id"
    t.string "job_type"
    t.integer "status", default: 0
    t.text "error_message"
    t.integer "retry_count", default: 0
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_rag_processing_jobs_on_job_id"
    t.index ["job_type", "status"], name: "index_rag_processing_jobs_on_job_type_and_status"
    t.index ["rag_store_id", "status"], name: "index_rag_processing_jobs_on_rag_store_id_and_status"
    t.index ["rag_store_id"], name: "index_rag_processing_jobs_on_rag_store_id"
  end

  create_table "rag_queries", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "rag_store_id"
    t.text "query", null: false
    t.string "query_hash"
    t.integer "response_time_ms"
    t.jsonb "chunks_retrieved", default: []
    t.jsonb "relevance_scores", default: []
    t.boolean "cache_hit", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cache_hit"], name: "index_rag_queries_on_cache_hit"
    t.index ["created_at"], name: "index_rag_queries_on_created_at"
    t.index ["entity_id", "query_hash"], name: "index_rag_queries_on_entity_id_and_query_hash"
    t.index ["entity_id"], name: "index_rag_queries_on_entity_id"
    t.index ["rag_store_id"], name: "index_rag_queries_on_rag_store_id"
  end

  create_table "rag_stores", force: :cascade do |t|
    t.string "name", null: false
    t.string "app_name", null: false
    t.string "pinecone_index"
    t.string "pinecone_namespace"
    t.integer "chunk_count", default: 0
    t.jsonb "metadata", default: {}
    t.string "status", default: "active"
    t.bigint "user_id"
    t.bigint "entity_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "store_type", default: "entity", null: false
    t.integer "metadata_schema_version", default: 1
    t.boolean "supports_page_filtering", default: true
    t.boolean "supports_section_filtering", default: true
    t.boolean "supports_heading_search", default: true
    t.integer "avg_chunk_tokens"
    t.integer "chunks_with_pages", default: 0
    t.integer "chunks_with_headings", default: 0
    t.integer "chunks_with_tables", default: 0
    t.string "s3_raw_path"
    t.string "s3_processed_path"
    t.string "s3_docling_output_path"
    t.integer "token_count", default: 0
    t.integer "processing_time_ms"
    t.string "processing_method"
    t.string "docling_version"
    t.datetime "last_accessed_at"
    t.integer "access_count", default: 0
    t.datetime "expires_at"
    t.index ["app_name"], name: "index_rag_stores_on_app_name"
    t.index ["entity_id", "status"], name: "index_rag_stores_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_rag_stores_on_entity_id"
    t.index ["last_accessed_at"], name: "index_rag_stores_on_last_accessed_at"
    t.index ["pinecone_index", "pinecone_namespace"], name: "index_rag_stores_on_pinecone_index_and_pinecone_namespace", unique: true
    t.index ["status"], name: "index_rag_stores_on_status"
    t.index ["store_type"], name: "index_rag_stores_on_store_type"
    t.index ["user_id"], name: "index_rag_stores_on_user_id"
    t.check_constraint "store_type::text = 'system'::text AND entity_id IS NULL OR store_type::text = 'entity'::text AND entity_id IS NOT NULL", name: "check_entity_required_for_store_type"
  end

  create_table "referrals", force: :cascade do |t|
    t.bigint "affiliate_id", null: false
    t.bigint "referred_user_id"
    t.bigint "referred_entity_id"
    t.string "referral_code_used"
    t.integer "status", default: 0, null: false
    t.datetime "converted_at"
    t.jsonb "cookie_data", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["affiliate_id", "referred_entity_id"], name: "index_referrals_on_affiliate_id_and_referred_entity_id"
    t.index ["affiliate_id"], name: "index_referrals_on_affiliate_id"
    t.index ["converted_at"], name: "index_referrals_on_converted_at"
    t.index ["referred_entity_id"], name: "index_referrals_on_referred_entity_id"
    t.index ["referred_user_id"], name: "index_referrals_on_referred_user_id"
    t.index ["status"], name: "index_referrals_on_status"
  end

  create_table "rich_text_sections", force: :cascade do |t|
    t.string "title"
    t.string "section_type"
    t.integer "section_index"
    t.string "image_url"
    t.bigint "landing_page_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["landing_page_id"], name: "index_rich_text_sections_on_landing_page_id"
  end

  create_table "saved_searches", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.jsonb "query_params", null: false
    t.boolean "alert_enabled", default: false
    t.string "alert_frequency"
    t.datetime "last_run_at"
    t.datetime "last_alert_at"
    t.integer "result_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alert_enabled", "last_run_at"], name: "index_saved_searches_on_alert_enabled_and_last_run_at"
    t.index ["entity_id", "user_id"], name: "index_saved_searches_on_entity_id_and_user_id"
    t.index ["entity_id"], name: "index_saved_searches_on_entity_id"
    t.index ["user_id"], name: "index_saved_searches_on_user_id"
  end

  create_table "scout_conversations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "session_id"
    t.string "message_type"
    t.text "content"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "parallel_task_ids", default: []
    t.jsonb "aggregated_results"
    t.index ["entity_id"], name: "index_scout_conversations_on_entity_id"
    t.index ["user_id"], name: "index_scout_conversations_on_user_id"
  end

  create_table "scout_messages", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id"
    t.string "session_id", null: false
    t.string "role", null: false
    t.text "content", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_scout_messages_on_entity_id"
    t.index ["session_id", "created_at"], name: "index_scout_messages_on_session_and_created"
    t.index ["session_id", "created_at"], name: "index_scout_messages_on_session_id_and_created_at"
    t.index ["session_id", "role", "content", "created_at"], name: "index_scout_messages_duplicate_detection"
    t.index ["session_id", "role"], name: "index_scout_messages_on_session_and_role"
    t.index ["user_id", "session_id"], name: "index_scout_messages_on_user_and_session"
    t.index ["user_id"], name: "index_scout_messages_on_user_id"
  end

  create_table "sequence_enrollments", force: :cascade do |t|
    t.bigint "email_sequence_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "entity_id", null: false
    t.string "status", default: "pending", null: false
    t.integer "current_step_number", default: 0
    t.datetime "next_send_at"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "last_email_sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_id"], name: "index_sequence_enrollments_on_contact_id"
    t.index ["email_sequence_id", "contact_id"], name: "index_enrollments_on_sequence_and_contact", unique: true
    t.index ["email_sequence_id"], name: "index_sequence_enrollments_on_email_sequence_id"
    t.index ["entity_id", "status"], name: "index_sequence_enrollments_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_sequence_enrollments_on_entity_id"
    t.index ["next_send_at"], name: "index_sequence_enrollments_on_next_send_at"
    t.index ["status"], name: "index_sequence_enrollments_on_status"
  end

  create_table "sequence_steps", force: :cascade do |t|
    t.bigint "email_sequence_id", null: false
    t.integer "step_number", null: false
    t.integer "delay_hours", default: 0, null: false
    t.bigint "email_template_id"
    t.string "subject"
    t.text "body"
    t.integer "sent_count", default: 0
    t.integer "opened_count", default: 0
    t.integer "clicked_count", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delay_hours"], name: "index_sequence_steps_on_delay_hours"
    t.index ["email_sequence_id", "step_number"], name: "index_sequence_steps_on_email_sequence_id_and_step_number", unique: true
    t.index ["email_sequence_id"], name: "index_sequence_steps_on_email_sequence_id"
    t.index ["email_template_id"], name: "index_sequence_steps_on_email_template_id"
  end

  create_table "shared_models", force: :cascade do |t|
    t.bigint "custom_model_id", null: false
    t.bigint "entity_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "base_model"
    t.jsonb "capabilities", default: []
    t.jsonb "benchmark_scores", default: {}
    t.decimal "cost_per_1k_tokens", precision: 10, scale: 6
    t.integer "usage_count", default: 0
    t.float "average_rating"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_shared_models_on_active"
    t.index ["base_model"], name: "index_shared_models_on_base_model"
    t.index ["cost_per_1k_tokens"], name: "index_shared_models_on_cost_per_1k_tokens"
    t.index ["custom_model_id"], name: "index_shared_models_on_custom_model_id"
    t.index ["entity_id"], name: "index_shared_models_on_entity_id"
  end

  create_table "shared_plugins", force: :cascade do |t|
    t.bigint "custom_plugin_id", null: false
    t.bigint "user_id", null: false
    t.string "listing_status", default: "pending"
    t.string "title", null: false
    t.text "description"
    t.string "category"
    t.jsonb "tags", default: []
    t.decimal "price", precision: 10, scale: 2, default: "0.0"
    t.string "pricing_model"
    t.integer "install_count", default: 0
    t.float "average_rating"
    t.jsonb "screenshots", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_shared_plugins_on_category"
    t.index ["custom_plugin_id"], name: "index_shared_plugins_on_custom_plugin_id"
    t.index ["listing_status", "average_rating"], name: "idx_marketplace_ranking"
    t.index ["listing_status"], name: "index_shared_plugins_on_listing_status"
    t.index ["price"], name: "index_shared_plugins_on_price"
    t.index ["tags"], name: "index_shared_plugins_on_tags", using: :gin
    t.index ["user_id"], name: "index_shared_plugins_on_user_id"
  end

  create_table "sms_campaigns", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "name", null: false
    t.text "message_body", null: false
    t.string "from_number"
    t.string "status", default: "draft"
    t.integer "total_recipients", default: 0
    t.integer "delivered_count", default: 0
    t.integer "failed_count", default: 0
    t.datetime "scheduled_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "status"], name: "index_sms_campaigns_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_sms_campaigns_on_entity_id"
  end

  create_table "sms_deliveries", force: :cascade do |t|
    t.bigint "sms_campaign_id", null: false
    t.bigint "contact_id", null: false
    t.string "to_number", null: false
    t.string "twilio_sid"
    t.string "status"
    t.text "error_message"
    t.datetime "delivered_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_id"], name: "index_sms_deliveries_on_contact_id"
    t.index ["sms_campaign_id", "status"], name: "index_sms_deliveries_on_sms_campaign_id_and_status"
    t.index ["sms_campaign_id"], name: "index_sms_deliveries_on_sms_campaign_id"
    t.index ["twilio_sid"], name: "index_sms_deliveries_on_twilio_sid", unique: true
  end

  create_table "social_media_accounts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "platform"
    t.string "status"
    t.string "username"
    t.string "profile_url"
    t.string "access_token"
    t.string "refresh_token"
    t.datetime "token_expires_at"
    t.jsonb "settings"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id"
    t.index ["entity_id"], name: "index_social_media_accounts_on_entity_id"
    t.index ["user_id"], name: "index_social_media_accounts_on_user_id"
  end

  create_table "social_post_analytics", force: :cascade do |t|
    t.bigint "social_post_id", null: false
    t.integer "likes"
    t.integer "comments"
    t.integer "shares"
    t.integer "views"
    t.integer "reach"
    t.decimal "engagement_rate"
    t.datetime "collected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["social_post_id"], name: "index_social_post_analytics_on_social_post_id"
  end

  create_table "social_posts", force: :cascade do |t|
    t.string "title"
    t.text "content"
    t.string "status"
    t.datetime "scheduled_at"
    t.datetime "published_at"
    t.string "platform"
    t.string "post_url"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image_url"
    t.jsonb "settings"
    t.bigint "entity_id"
    t.index ["entity_id"], name: "index_social_posts_on_entity_id"
    t.index ["user_id"], name: "index_social_posts_on_user_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", default: -> { "('ContactProcessor-'::text || (gen_random_uuid())::text)" }, null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "subscription_events", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "event_type", null: false
    t.string "previous_status"
    t.string "new_status"
    t.string "previous_plan"
    t.string "new_plan"
    t.string "stripe_event_id"
    t.jsonb "metadata", default: {}
    t.string "triggered_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "created_at"], name: "index_subscription_events_on_entity_id_and_created_at"
    t.index ["entity_id"], name: "index_subscription_events_on_entity_id"
    t.index ["event_type"], name: "index_subscription_events_on_event_type"
    t.index ["stripe_event_id"], name: "index_subscription_events_on_stripe_event_id", unique: true, where: "(stripe_event_id IS NOT NULL)"
  end

  create_table "system_documents", force: :cascade do |t|
    t.string "filename", null: false
    t.string "original_filename", null: false
    t.integer "file_size_bytes", null: false
    t.string "content_type", null: false
    t.string "category", null: false
    t.string "subcategory"
    t.text "description"
    t.string "s3_key", null: false
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.bigint "rag_store_id"
    t.bigint "uploaded_by_id", null: false
    t.datetime "indexed_at"
    t.integer "chunk_count", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category", "subcategory"], name: "index_system_documents_on_category_and_subcategory"
    t.index ["category"], name: "index_system_documents_on_category"
    t.index ["rag_store_id"], name: "index_system_documents_on_rag_store_id"
    t.index ["s3_key"], name: "index_system_documents_on_s3_key", unique: true
    t.index ["status"], name: "index_system_documents_on_status"
    t.index ["uploaded_by_id"], name: "index_system_documents_on_uploaded_by_id"
  end

  create_table "system_settings", force: :cascade do |t|
    t.string "key"
    t.text "value"
    t.text "encrypted_value"
    t.string "category"
    t.text "description"
    t.boolean "is_sensitive"
    t.integer "last_updated_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_system_settings_on_key", unique: true
  end

  create_table "task_dependencies", force: :cascade do |t|
    t.bigint "task_session_id", null: false
    t.bigint "depends_on_task_id", null: false
    t.string "relationship_type", default: "blocks"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "dependency_type", default: "blocking", null: false
    t.string "status", default: "pending", null: false
    t.index ["dependency_type"], name: "index_task_dependencies_on_dependency_type"
    t.index ["depends_on_task_id"], name: "index_task_dependencies_on_depends_on_task_id"
    t.index ["status"], name: "index_task_dependencies_on_status"
    t.index ["task_session_id", "depends_on_task_id"], name: "idx_on_task_session_id_depends_on_task_id_dfb947b090", unique: true
    t.index ["task_session_id"], name: "index_task_dependencies_on_task_session_id"
  end

  create_table "task_events", force: :cascade do |t|
    t.bigint "task_session_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "step_id"
    t.integer "sequence_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_task_events_on_event_type"
    t.index ["task_session_id", "created_at"], name: "index_task_events_on_task_session_id_and_created_at"
    t.index ["task_session_id", "sequence_number"], name: "index_task_events_on_task_session_id_and_sequence_number", unique: true
    t.index ["task_session_id"], name: "index_task_events_on_task_session_id"
  end

  create_table "task_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "status", default: "active", null: false
    t.jsonb "state", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "session_type"
    t.string "workflow_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "parent_conversation_id"
    t.string "task_type"
    t.integer "priority", default: 5
    t.string "model_preference"
    t.string "assigned_worker_id"
    t.integer "progress", default: 0
    t.datetime "started_at"
    t.datetime "estimated_completion_at"
    t.datetime "completed_at"
    t.text "error_message"
    t.index ["assigned_worker_id", "status"], name: "index_task_sessions_on_assigned_worker_id_and_status"
    t.index ["created_at"], name: "index_task_sessions_on_created_at"
    t.index ["parent_conversation_id"], name: "index_task_sessions_on_parent_conversation_id"
    t.index ["session_type"], name: "index_task_sessions_on_session_type"
    t.index ["status", "priority"], name: "index_task_sessions_on_status_and_priority"
    t.index ["status"], name: "index_task_sessions_on_status"
    t.index ["task_type"], name: "index_task_sessions_on_task_type"
    t.index ["user_id", "status"], name: "index_task_sessions_on_user_id_and_status"
    t.index ["user_id"], name: "index_task_sessions_on_user_id"
  end

  create_table "tenant_quotas", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "row_budget"
    t.integer "window_days_cap"
    t.integer "qps_limit"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_tenant_quotas_on_entity_id"
  end

  create_table "tts_usage_logs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.integer "character_count"
    t.string "voice_id"
    t.float "cost_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_tts_usage_logs_on_entity_id"
    t.index ["user_id"], name: "index_tts_usage_logs_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "first_name"
    t.string "last_name"
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key"
    t.boolean "onboarded", default: false, null: false
    t.boolean "developer_mode", default: false
    t.string "api_key_encrypted"
    t.boolean "plugin_development_enabled", default: false
    t.bigint "entity_id", null: false
    t.jsonb "tts_preferences", default: {}, null: false
    t.index ["api_key"], name: "index_users_on_api_key"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["entity_id"], name: "index_users_on_entity_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["tts_preferences"], name: "index_users_on_tts_preferences", using: :gin
  end

  create_table "voice_assistant_settings", force: :cascade do |t|
    t.string "key"
    t.text "value"
    t.string "setting_type"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_voice_assistant_settings_on_key", unique: true
  end

  create_table "voice_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "session_id", null: false
    t.string "status", default: "active", null: false
    t.jsonb "context", default: {}
    t.jsonb "transcript_history", default: []
    t.jsonb "metadata", default: {}
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "status"], name: "index_voice_sessions_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_voice_sessions_on_entity_id"
    t.index ["session_id"], name: "index_voice_sessions_on_session_id", unique: true
    t.index ["started_at"], name: "index_voice_sessions_on_started_at"
    t.index ["status"], name: "index_voice_sessions_on_status"
    t.index ["user_id"], name: "index_voice_sessions_on_user_id"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.bigint "webhook_subscription_id", null: false
    t.string "event_type"
    t.jsonb "payload"
    t.integer "response_status"
    t.text "response_body"
    t.datetime "delivered_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["webhook_subscription_id"], name: "index_webhook_events_on_webhook_subscription_id"
  end

  create_table "webhook_subscriptions", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.string "endpoint_url"
    t.string "signing_secret"
    t.jsonb "events"
    t.jsonb "filters"
    t.integer "status"
    t.integer "retry_count"
    t.datetime "last_triggered_at"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id"], name: "index_webhook_subscriptions_on_connection_id"
  end

  create_table "workflow_contexts", force: :cascade do |t|
    t.bigint "workflow_execution_id", null: false
    t.bigint "task_session_id", null: false
    t.string "key", null: false
    t.jsonb "value", default: {}
    t.string "data_type", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["data_type"], name: "index_workflow_contexts_on_data_type"
    t.index ["key"], name: "index_workflow_contexts_on_key"
    t.index ["task_session_id"], name: "index_workflow_contexts_on_task_session_id"
    t.index ["workflow_execution_id", "key"], name: "index_workflow_contexts_on_workflow_execution_id_and_key"
    t.index ["workflow_execution_id"], name: "index_workflow_contexts_on_workflow_execution_id"
  end

  create_table "workflow_executions", force: :cascade do |t|
    t.bigint "task_session_id", null: false
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "workflow_template_id"
    t.jsonb "workflow_spec", default: {}
    t.string "status", default: "pending", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "error_message"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_workflow_executions_on_created_at"
    t.index ["entity_id", "status"], name: "index_workflow_executions_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_workflow_executions_on_entity_id"
    t.index ["status"], name: "index_workflow_executions_on_status"
    t.index ["task_session_id"], name: "index_workflow_executions_on_task_session_id"
    t.index ["user_id"], name: "index_workflow_executions_on_user_id"
    t.index ["workflow_template_id"], name: "index_workflow_executions_on_workflow_template_id"
  end

  create_table "workflow_step_executions", force: :cascade do |t|
    t.bigint "workflow_execution_id", null: false
    t.string "step_id", null: false
    t.string "step_name"
    t.string "step_type"
    t.string "status", default: "pending", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.jsonb "input_data", default: {}
    t.jsonb "output_data", default: {}
    t.text "error_message"
    t.integer "retry_count", default: 0
    t.string "agent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_workflow_step_executions_on_status"
    t.index ["step_id"], name: "index_workflow_step_executions_on_step_id"
    t.index ["workflow_execution_id", "status"], name: "idx_workflow_step_status"
    t.index ["workflow_execution_id", "step_id"], name: "idx_workflow_step_unique", unique: true
    t.index ["workflow_execution_id"], name: "index_workflow_step_executions_on_workflow_execution_id"
  end

  create_table "workflow_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "category", null: false
    t.text "description"
    t.jsonb "template_spec", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.boolean "is_active", default: true
    t.boolean "is_system", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_workflow_templates_on_category"
    t.index ["is_active"], name: "index_workflow_templates_on_is_active"
    t.index ["slug"], name: "index_workflow_templates_on_slug", unique: true
  end

  create_table "workflow_variables", force: :cascade do |t|
    t.bigint "workflow_execution_id", null: false
    t.string "source_type"
    t.bigint "source_id"
    t.string "name", null: false
    t.jsonb "value"
    t.string "data_type"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_workflow_variables_on_name"
    t.index ["source_type", "source_id"], name: "index_workflow_variables_on_source"
    t.index ["source_type", "source_id"], name: "index_workflow_variables_on_source_type_and_source_id"
    t.index ["workflow_execution_id", "name"], name: "idx_workflow_var_unique", unique: true
    t.index ["workflow_execution_id"], name: "index_workflow_variables_on_workflow_execution_id"
  end

  add_foreign_key "ab_test_variants", "ab_tests"
  add_foreign_key "ab_tests", "entities"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_activities", "admin_users"
  add_foreign_key "affiliate_clicks", "affiliates"
  add_foreign_key "affiliates", "admin_users", column: "approved_by_id"
  add_foreign_key "affiliates", "users"
  add_foreign_key "agent_activities", "scout_conversations", column: "conversation_id"
  add_foreign_key "agent_executions", "pipeline_executions"
  add_foreign_key "agent_lightning_configs", "entities"
  add_foreign_key "agent_lightning_optimizations", "agent_training_jobs"
  add_foreign_key "agent_lightning_optimizations", "entities"
  add_foreign_key "agent_lightning_traces", "entities"
  add_foreign_key "agent_lightning_traces", "task_sessions"
  add_foreign_key "agent_lightning_traces", "users"
  add_foreign_key "agent_lightning_traces", "workflow_executions"
  add_foreign_key "agent_lightning_webhook_logs", "agent_lightning_webhooks"
  add_foreign_key "agent_lightning_webhooks", "entities"
  add_foreign_key "agent_llm_calls", "agent_lightning_traces"
  add_foreign_key "agent_llm_calls", "entities"
  add_foreign_key "agent_messages", "task_sessions"
  add_foreign_key "agent_phase_executions", "agent_lightning_traces"
  add_foreign_key "agent_phase_executions", "entities"
  add_foreign_key "agent_phase_executions", "workflow_executions"
  add_foreign_key "agent_rewards", "agent_lightning_traces"
  add_foreign_key "agent_rewards", "entities"
  add_foreign_key "agent_rewards", "users"
  add_foreign_key "agent_tool_executions", "agent_lightning_traces"
  add_foreign_key "agent_tool_executions", "agent_llm_calls"
  add_foreign_key "agent_tool_executions", "entities"
  add_foreign_key "agent_training_jobs", "entities"
  add_foreign_key "ai_usage_logs", "entities"
  add_foreign_key "ai_usage_logs", "scout_messages"
  add_foreign_key "ai_usage_logs", "users"
  add_foreign_key "analytics_connections", "entities"
  add_foreign_key "analytics_query_logs", "entities"
  add_foreign_key "analytics_query_logs", "metric_definitions"
  add_foreign_key "analytics_query_logs", "users"
  add_foreign_key "artifacts", "entities"
  add_foreign_key "artifacts", "users"
  add_foreign_key "auth_configs", "oauth_configurations"
  add_foreign_key "business_insights", "entities"
  add_foreign_key "business_insights", "scout_conversations", column: "source_conversation_id"
  add_foreign_key "business_profiles", "entities"
  add_foreign_key "business_profiles", "users"
  add_foreign_key "campaign_groups", "campaigns"
  add_foreign_key "campaign_groups", "contact_groups"
  add_foreign_key "campaigns", "email_templates"
  add_foreign_key "campaigns", "entities"
  add_foreign_key "campaigns", "users"
  add_foreign_key "commissions", "admin_users", column: "approved_by_id"
  add_foreign_key "commissions", "affiliates"
  add_foreign_key "commissions", "entities"
  add_foreign_key "commissions", "referrals"
  add_foreign_key "commissions", "subscription_events"
  add_foreign_key "connections", "entities"
  add_foreign_key "connections", "integrations"
  add_foreign_key "contact_groups", "entities"
  add_foreign_key "contact_groups", "users"
  add_foreign_key "contact_groups_contacts", "contact_groups"
  add_foreign_key "contact_groups_contacts", "contacts"
  add_foreign_key "contacts", "entities"
  add_foreign_key "contacts", "users"
  add_foreign_key "conversation_embeddings", "entities"
  add_foreign_key "conversation_embeddings", "scout_messages"
  add_foreign_key "crawler_conversations", "crawler_jobs"
  add_foreign_key "crawler_job_logs", "crawler_jobs"
  add_foreign_key "crawler_jobs", "entities"
  add_foreign_key "crawler_jobs", "users"
  add_foreign_key "custom_models", "entities"
  add_foreign_key "custom_models", "users"
  add_foreign_key "custom_plugins", "entities"
  add_foreign_key "custom_plugins", "users"
  add_foreign_key "document_analytics", "rag_documents"
  add_foreign_key "document_annotations", "rag_documents"
  add_foreign_key "document_annotations", "users"
  add_foreign_key "document_annotations", "users", column: "resolved_by_id"
  add_foreign_key "document_chunks", "knowledge_documents"
  add_foreign_key "document_relationships", "rag_documents", column: "source_document_id"
  add_foreign_key "document_relationships", "rag_documents", column: "target_document_id"
  add_foreign_key "document_subject_assignments", "document_subjects"
  add_foreign_key "document_subject_assignments", "rag_documents"
  add_foreign_key "document_subject_assignments", "users", column: "assigned_by_id"
  add_foreign_key "document_subjects", "document_subjects", column: "parent_id"
  add_foreign_key "document_subjects", "entities"
  add_foreign_key "document_tag_assignments", "document_tags"
  add_foreign_key "document_tag_assignments", "rag_documents"
  add_foreign_key "document_tags", "entities"
  add_foreign_key "dripped_campaigns", "campaigns", column: "follow_up_campaign_id"
  add_foreign_key "dripped_campaigns", "campaigns", column: "original_campaign_id"
  add_foreign_key "email_deliveries", "campaigns"
  add_foreign_key "email_deliveries", "contacts"
  add_foreign_key "email_deliveries", "email_templates"
  add_foreign_key "email_sequences", "contact_groups"
  add_foreign_key "email_sequences", "entities"
  add_foreign_key "email_templates", "entities"
  add_foreign_key "email_templates", "users"
  add_foreign_key "entity_cost_reports", "entities"
  add_foreign_key "entity_cost_summaries", "entities"
  add_foreign_key "entity_usage_metrics", "entities"
  add_foreign_key "entity_users", "entities"
  add_foreign_key "entity_users", "users"
  add_foreign_key "image_assets", "entities"
  add_foreign_key "image_assets", "users"
  add_foreign_key "integration_credentials", "connections"
  add_foreign_key "integration_embeddings", "entities"
  add_foreign_key "integration_embeddings", "integrations"
  add_foreign_key "integration_logs", "connections"
  add_foreign_key "integration_logs", "integration_operations"
  add_foreign_key "integration_logs", "scout_messages"
  add_foreign_key "integration_logs", "users"
  add_foreign_key "integration_operations", "integrations"
  add_foreign_key "knowledge_documents", "entities"
  add_foreign_key "landing_page_chat_messages", "landing_pages"
  add_foreign_key "landing_page_chat_messages", "users"
  add_foreign_key "landing_page_submissions", "contacts"
  add_foreign_key "landing_page_submissions", "landing_pages"
  add_foreign_key "landing_page_versions", "landing_pages"
  add_foreign_key "landing_pages", "campaigns"
  add_foreign_key "landing_pages", "entities"
  add_foreign_key "landing_pages", "users"
  add_foreign_key "mcp_connections", "entities"
  add_foreign_key "model_permissions", "custom_models"
  add_foreign_key "model_permissions", "entities"
  add_foreign_key "o_auth_configurations", "entities"
  add_foreign_key "o_auth_configurations", "integrations"
  add_foreign_key "oauth_configurations", "integrations"
  add_foreign_key "observability_events", "entities"
  add_foreign_key "observability_events", "users"
  add_foreign_key "ocr_metrics", "entities"
  add_foreign_key "ocr_metrics", "rag_documents"
  add_foreign_key "payouts", "admin_users", column: "processed_by_id"
  add_foreign_key "payouts", "affiliates"
  add_foreign_key "pipeline_artifacts", "agent_executions"
  add_foreign_key "pipeline_artifacts", "pipeline_executions"
  add_foreign_key "pipeline_events", "pipeline_executions"
  add_foreign_key "pipeline_executions", "entities"
  add_foreign_key "pipeline_executions", "mcp_connections"
  add_foreign_key "pipeline_executions", "mcp_connections", column: "git_connection_id"
  add_foreign_key "pipeline_interactions", "pipeline_executions"
  add_foreign_key "pipeline_interactions", "users"
  add_foreign_key "plugin_permissions", "custom_plugins"
  add_foreign_key "plugin_permissions", "entities"
  add_foreign_key "plugin_permissions", "users"
  add_foreign_key "plugin_reviews", "shared_plugins"
  add_foreign_key "plugin_reviews", "users"
  add_foreign_key "plugin_transactions", "entities"
  add_foreign_key "plugin_transactions", "shared_models"
  add_foreign_key "plugin_transactions", "shared_plugins"
  add_foreign_key "plugin_transactions", "users"
  add_foreign_key "plugin_usages", "entities"
  add_foreign_key "plugin_usages", "users"
  add_foreign_key "policy_rules", "entities"
  add_foreign_key "rag_chunks", "rag_documents"
  add_foreign_key "rag_documents", "rag_documents", column: "parent_document_id"
  add_foreign_key "rag_documents", "rag_stores"
  add_foreign_key "rag_documents", "users", column: "last_accessed_by_id"
  add_foreign_key "rag_processing_jobs", "rag_stores"
  add_foreign_key "rag_queries", "entities"
  add_foreign_key "rag_queries", "rag_stores"
  add_foreign_key "rag_stores", "entities"
  add_foreign_key "rag_stores", "users"
  add_foreign_key "referrals", "affiliates"
  add_foreign_key "referrals", "entities", column: "referred_entity_id"
  add_foreign_key "referrals", "users", column: "referred_user_id"
  add_foreign_key "rich_text_sections", "landing_pages"
  add_foreign_key "saved_searches", "entities"
  add_foreign_key "saved_searches", "users"
  add_foreign_key "scout_conversations", "entities"
  add_foreign_key "scout_conversations", "users"
  add_foreign_key "scout_messages", "entities"
  add_foreign_key "scout_messages", "users"
  add_foreign_key "sequence_enrollments", "contacts"
  add_foreign_key "sequence_enrollments", "email_sequences"
  add_foreign_key "sequence_enrollments", "entities"
  add_foreign_key "sequence_steps", "email_sequences"
  add_foreign_key "sequence_steps", "email_templates"
  add_foreign_key "shared_models", "custom_models"
  add_foreign_key "shared_models", "entities"
  add_foreign_key "shared_plugins", "custom_plugins"
  add_foreign_key "shared_plugins", "users"
  add_foreign_key "sms_campaigns", "entities"
  add_foreign_key "sms_deliveries", "contacts"
  add_foreign_key "sms_deliveries", "sms_campaigns"
  add_foreign_key "social_media_accounts", "entities"
  add_foreign_key "social_media_accounts", "users"
  add_foreign_key "social_post_analytics", "social_posts"
  add_foreign_key "social_posts", "entities"
  add_foreign_key "social_posts", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "subscription_events", "entities"
  add_foreign_key "system_documents", "rag_stores"
  add_foreign_key "system_documents", "users", column: "uploaded_by_id"
  add_foreign_key "task_dependencies", "task_sessions"
  add_foreign_key "task_dependencies", "task_sessions", column: "depends_on_task_id"
  add_foreign_key "task_events", "task_sessions"
  add_foreign_key "task_sessions", "users"
  add_foreign_key "tenant_quotas", "entities"
  add_foreign_key "tts_usage_logs", "entities"
  add_foreign_key "tts_usage_logs", "users"
  add_foreign_key "users", "entities"
  add_foreign_key "voice_sessions", "entities"
  add_foreign_key "voice_sessions", "users"
  add_foreign_key "webhook_events", "webhook_subscriptions"
  add_foreign_key "webhook_subscriptions", "connections"
  add_foreign_key "workflow_contexts", "task_sessions"
  add_foreign_key "workflow_contexts", "workflow_executions"
  add_foreign_key "workflow_executions", "entities"
  add_foreign_key "workflow_executions", "task_sessions"
  add_foreign_key "workflow_executions", "users"
  add_foreign_key "workflow_step_executions", "workflow_executions"
  add_foreign_key "workflow_variables", "workflow_executions"
end
