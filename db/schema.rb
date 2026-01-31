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

ActiveRecord::Schema[8.0].define(version: 2026_01_30_130000) do
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

  create_table "activities", force: :cascade do |t|
    t.bigint "contact_id"
    t.bigint "opportunity_id"
    t.bigint "user_id"
    t.bigint "performed_by_agent_id"
    t.bigint "assigned_user_id"
    t.bigint "assigned_agent_id"
    t.bigint "entity_id", null: false
    t.string "activity_type", null: false
    t.string "subject"
    t.text "description"
    t.datetime "scheduled_at"
    t.datetime "due_at"
    t.datetime "completed_at"
    t.string "outcome"
    t.string "status", default: "pending", null: false
    t.string "priority", default: "normal"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_type"], name: "index_activities_on_activity_type"
    t.index ["assigned_agent_id", "status"], name: "index_activities_on_assigned_agent_id_and_status"
    t.index ["assigned_agent_id"], name: "index_activities_on_assigned_agent_id"
    t.index ["assigned_user_id", "status"], name: "index_activities_on_assigned_user_id_and_status"
    t.index ["assigned_user_id"], name: "index_activities_on_assigned_user_id"
    t.index ["contact_id", "created_at"], name: "index_activities_on_contact_id_and_created_at"
    t.index ["contact_id"], name: "index_activities_on_contact_id"
    t.index ["due_at"], name: "index_activities_on_due_at"
    t.index ["entity_id", "activity_type"], name: "index_activities_on_entity_id_and_activity_type"
    t.index ["entity_id"], name: "index_activities_on_entity_id"
    t.index ["opportunity_id", "created_at"], name: "index_activities_on_opportunity_id_and_created_at"
    t.index ["opportunity_id"], name: "index_activities_on_opportunity_id"
    t.index ["performed_by_agent_id"], name: "index_activities_on_performed_by_agent_id"
    t.index ["priority"], name: "index_activities_on_priority"
    t.index ["scheduled_at"], name: "index_activities_on_scheduled_at"
    t.index ["status"], name: "index_activities_on_status"
    t.index ["user_id"], name: "index_activities_on_user_id"
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

  create_table "agent_ab_tests", force: :cascade do |t|
    t.bigint "control_agent_id", null: false
    t.bigint "variant_agent_id", null: false
    t.bigint "enrollment_id"
    t.bigint "entity_id", null: false
    t.string "status", default: "pending", null: false
    t.integer "target_tasks", default: 50, null: false
    t.jsonb "metrics_to_compare", default: ["success_rate", "quality_score", "efficiency"]
    t.integer "control_tasks_completed", default: 0
    t.integer "variant_tasks_completed", default: 0
    t.jsonb "control_results", default: {}
    t.jsonb "variant_results", default: {}
    t.jsonb "statistical_analysis", default: {}
    t.string "winner"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "evolution_cycle_id"
    t.bigint "agent_goal_id"
    t.index ["agent_goal_id"], name: "index_agent_ab_tests_on_agent_goal_id"
    t.index ["control_agent_id", "status"], name: "index_agent_ab_tests_on_control_agent_id_and_status"
    t.index ["control_agent_id"], name: "index_agent_ab_tests_on_control_agent_id"
    t.index ["enrollment_id"], name: "index_agent_ab_tests_on_enrollment_id"
    t.index ["entity_id"], name: "index_agent_ab_tests_on_entity_id"
    t.index ["evolution_cycle_id"], name: "index_agent_ab_tests_on_evolution_cycle_id"
    t.index ["status"], name: "index_agent_ab_tests_on_status"
    t.index ["variant_agent_id", "status"], name: "index_agent_ab_tests_on_variant_agent_id_and_status"
    t.index ["variant_agent_id"], name: "index_agent_ab_tests_on_variant_agent_id"
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

  create_table "agent_capabilities", force: :cascade do |t|
    t.bigint "agent_plugin_id", null: false
    t.string "capability_name", null: false
    t.jsonb "contract_schema", default: {}
    t.text "implementation_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_id", "capability_name"], name: "index_agent_capabilities_on_plugin_and_name", unique: true
    t.index ["agent_plugin_id"], name: "index_agent_capabilities_on_agent_plugin_id"
    t.index ["capability_name"], name: "index_agent_capabilities_on_capability_name"
  end

  create_table "agent_capability_beliefs", force: :cascade do |t|
    t.bigint "agent_plugin_id", null: false
    t.string "task_type", null: false
    t.integer "attempts", default: 0, null: false
    t.integer "successes", default: 0, null: false
    t.float "total_quality", default: 0.0
    t.float "avg_quality", default: 0.5
    t.jsonb "confidence_interval", default: [0.0, 1.0]
    t.boolean "is_specialty", default: false
    t.boolean "is_weakness", default: false
    t.float "z_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_id", "task_type"], name: "idx_on_agent_plugin_id_task_type_3d9550fc88", unique: true
    t.index ["agent_plugin_id"], name: "index_agent_capability_beliefs_on_agent_plugin_id"
    t.index ["is_specialty"], name: "index_agent_capability_beliefs_on_is_specialty"
    t.index ["is_weakness"], name: "index_agent_capability_beliefs_on_is_weakness"
  end

  create_table "agent_collaboration_requests", force: :cascade do |t|
    t.bigint "requesting_agent_id", null: false
    t.bigint "helper_agent_id"
    t.bigint "entity_id", null: false
    t.bigint "agent_plugin_execution_id"
    t.bigint "parent_request_id"
    t.string "request_type", null: false
    t.text "description"
    t.jsonb "context", default: {}
    t.string "urgency", default: "medium"
    t.jsonb "required_capabilities", default: []
    t.string "status", default: "pending"
    t.datetime "accepted_at"
    t.datetime "completed_at"
    t.datetime "timeout_at"
    t.jsonb "response"
    t.float "quality_rating"
    t.boolean "was_helpful"
    t.text "feedback"
    t.float "energy_cost"
    t.float "energy_reward"
    t.integer "depth", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_execution_id"], name: "idx_on_agent_plugin_execution_id_5a699e4a66"
    t.index ["depth"], name: "index_agent_collaboration_requests_on_depth"
    t.index ["entity_id"], name: "index_agent_collaboration_requests_on_entity_id"
    t.index ["helper_agent_id", "status"], name: "idx_on_helper_agent_id_status_a0fdb53589"
    t.index ["helper_agent_id"], name: "index_agent_collaboration_requests_on_helper_agent_id"
    t.index ["parent_request_id"], name: "index_agent_collaboration_requests_on_parent_request_id"
    t.index ["request_type"], name: "index_agent_collaboration_requests_on_request_type"
    t.index ["requesting_agent_id", "status"], name: "idx_on_requesting_agent_id_status_caa967ce5e"
    t.index ["requesting_agent_id"], name: "index_agent_collaboration_requests_on_requesting_agent_id"
    t.index ["status"], name: "index_agent_collaboration_requests_on_status"
  end

  create_table "agent_decision_boundaries", force: :cascade do |t|
    t.bigint "agent_plugin_id", null: false
    t.float "ask_alpha", default: 1.0, null: false
    t.float "ask_beta", default: 1.0, null: false
    t.float "solo_alpha", default: 1.0, null: false
    t.float "solo_beta", default: 1.0, null: false
    t.float "current_threshold", default: 50.0
    t.jsonb "decision_history", default: []
    t.integer "total_decisions", default: 0
    t.integer "correct_decisions", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_id"], name: "index_agent_decision_boundaries_on_agent_plugin_id"
  end

  create_table "agent_energy_states", force: :cascade do |t|
    t.bigint "agent_plugin_id", null: false
    t.bigint "entity_id", null: false
    t.float "current_energy", default: 50.0, null: false
    t.float "max_energy", default: 100.0, null: false
    t.float "regeneration_rate", default: 2.0, null: false
    t.boolean "in_debt", default: false
    t.float "total_earned", default: 0.0, null: false
    t.float "total_spent", default: 0.0, null: false
    t.integer "tasks_completed", default: 0, null: false
    t.integer "tasks_failed", default: 0, null: false
    t.integer "tasks_delegated", default: 0, null: false
    t.integer "help_given", default: 0, null: false
    t.integer "help_received", default: 0, null: false
    t.float "success_rate", default: 0.0
    t.float "avg_quality", default: 0.5
    t.float "collaboration_score", default: 0.5
    t.float "elo_rating", default: 1000.0
    t.datetime "last_energy_update_at"
    t.datetime "debt_started_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_id"], name: "index_agent_energy_states_on_agent_plugin_id"
    t.index ["entity_id", "current_energy"], name: "idx_energy_entity_current"
    t.index ["entity_id"], name: "index_agent_energy_states_on_entity_id"
    t.index ["in_debt"], name: "idx_energy_in_debt"
  end

  create_table "agent_energy_transactions", force: :cascade do |t|
    t.bigint "agent_plugin_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "agent_plugin_execution_id"
    t.bigint "collaboration_request_id"
    t.string "transaction_type", null: false
    t.float "amount", null: false
    t.string "reason", null: false
    t.float "balance_before", null: false
    t.float "balance_after", null: false
    t.jsonb "metadata", default: {}
    t.string "ledger_hash"
    t.string "previous_ledger_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_execution_id"], name: "index_agent_energy_transactions_on_agent_plugin_execution_id"
    t.index ["agent_plugin_id", "created_at"], name: "idx_on_agent_plugin_id_created_at_a5c3ddbc09"
    t.index ["agent_plugin_id"], name: "index_agent_energy_transactions_on_agent_plugin_id"
    t.index ["collaboration_request_id"], name: "index_agent_energy_transactions_on_collaboration_request_id"
    t.index ["created_at"], name: "index_agent_energy_transactions_on_created_at"
    t.index ["entity_id"], name: "index_agent_energy_transactions_on_entity_id"
    t.index ["transaction_type"], name: "index_agent_energy_transactions_on_transaction_type"
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

  create_table "agent_genomes", force: :cascade do |t|
    t.string "role", null: false
    t.string "name"
    t.text "description"
    t.jsonb "dna", default: {}, null: false
    t.float "fitness_score", default: 0.0
    t.integer "generation", default: 0
    t.bigint "parent_id"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fitness_score"], name: "index_agent_genomes_on_fitness_score"
    t.index ["parent_id"], name: "index_agent_genomes_on_parent_id"
    t.index ["role"], name: "index_agent_genomes_on_role"
  end

  create_table "agent_goals", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "agent_plugin_id"
    t.bigint "created_by_agent_id"
    t.string "goal_type", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "priority", default: 50
    t.string "status", default: "pending"
    t.string "target_type"
    t.bigint "target_id"
    t.jsonb "success_criteria", default: {}
    t.jsonb "current_metrics", default: {}
    t.jsonb "target_metrics", default: {}
    t.jsonb "suggested_actions", default: []
    t.datetime "scheduled_for"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.bigint "execution_task_id"
    t.bigint "school_enrollment_id"
    t.jsonb "execution_result", default: {}
    t.string "source"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_id", "status"], name: "index_agent_goals_on_agent_plugin_id_and_status"
    t.index ["agent_plugin_id"], name: "index_agent_goals_on_agent_plugin_id"
    t.index ["created_by_agent_id"], name: "index_agent_goals_on_created_by_agent_id"
    t.index ["entity_id", "goal_type"], name: "index_agent_goals_on_entity_id_and_goal_type"
    t.index ["entity_id", "status"], name: "index_agent_goals_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_agent_goals_on_entity_id"
    t.index ["execution_task_id"], name: "index_agent_goals_on_execution_task_id"
    t.index ["scheduled_for"], name: "index_agent_goals_on_scheduled_for"
    t.index ["school_enrollment_id"], name: "index_agent_goals_on_school_enrollment_id"
    t.index ["target_type", "target_id"], name: "index_agent_goals_on_target_type_and_target_id"
  end

  create_table "agent_input_requests", force: :cascade do |t|
    t.bigint "agent_plugin_execution_id", null: false
    t.text "question", null: false
    t.jsonb "context_data", default: {}
    t.string "variable_name"
    t.string "status", default: "pending", null: false
    t.text "response_content"
    t.datetime "responded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "expires_at"
    t.boolean "skipped", default: false, null: false
    t.string "skipped_reason"
    t.string "agent_name"
    t.string "agent_icon"
    t.string "session_id"
    t.index ["agent_plugin_execution_id"], name: "index_agent_input_requests_on_agent_plugin_execution_id"
    t.index ["expires_at"], name: "index_agent_input_requests_on_expires_at"
    t.index ["session_id"], name: "index_agent_input_requests_on_session_id"
    t.index ["status", "priority"], name: "idx_input_requests_queue"
    t.index ["status"], name: "index_agent_input_requests_on_status"
  end

  create_table "agent_knowledge_shares", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "source_agent_id", null: false
    t.bigint "target_agent_id", null: false
    t.bigint "agent_relationship_id"
    t.string "knowledge_type"
    t.string "title", null: false
    t.text "content"
    t.jsonb "metadata", default: {}
    t.text "reason"
    t.decimal "relevance_score", precision: 5, scale: 4
    t.string "status", default: "shared"
    t.boolean "target_found_useful"
    t.text "target_feedback"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_relationship_id"], name: "index_agent_knowledge_shares_on_agent_relationship_id"
    t.index ["entity_id"], name: "index_agent_knowledge_shares_on_entity_id"
    t.index ["source_agent_id", "target_agent_id"], name: "idx_on_source_agent_id_target_agent_id_57a96f5ce9"
    t.index ["source_agent_id"], name: "index_agent_knowledge_shares_on_source_agent_id"
    t.index ["target_agent_id", "status"], name: "index_agent_knowledge_shares_on_target_agent_id_and_status"
    t.index ["target_agent_id"], name: "index_agent_knowledge_shares_on_target_agent_id"
  end

  create_table "agent_lifecycle_events", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "agent_plugin_id", null: false
    t.string "event_type", null: false
    t.text "description"
    t.jsonb "event_data", default: {}
    t.jsonb "metrics_snapshot", default: {}
    t.jsonb "related_agents", default: []
    t.string "triggered_by"
    t.bigint "triggered_by_goal_id"
    t.bigint "school_enrollment_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_id", "event_type"], name: "index_agent_lifecycle_events_on_agent_plugin_id_and_event_type"
    t.index ["agent_plugin_id"], name: "index_agent_lifecycle_events_on_agent_plugin_id"
    t.index ["created_at"], name: "index_agent_lifecycle_events_on_created_at"
    t.index ["entity_id", "event_type"], name: "index_agent_lifecycle_events_on_entity_id_and_event_type"
    t.index ["entity_id"], name: "index_agent_lifecycle_events_on_entity_id"
    t.index ["school_enrollment_id"], name: "index_agent_lifecycle_events_on_school_enrollment_id"
    t.index ["triggered_by_goal_id"], name: "index_agent_lifecycle_events_on_triggered_by_goal_id"
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

  create_table "agent_plugin_executions", force: :cascade do |t|
    t.bigint "agent_plugin_id", null: false
    t.bigint "workflow_execution_id"
    t.bigint "user_id", null: false
    t.string "status", default: "running", null: false
    t.jsonb "input_context", default: {}
    t.jsonb "output_result", default: {}
    t.integer "duration_ms"
    t.integer "tokens_used", default: 0
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "model_id"
    t.integer "model_input_tokens", default: 0
    t.integer "model_output_tokens", default: 0
    t.jsonb "conversation_context", default: []
    t.bigint "evolution_experiment_id"
    t.boolean "is_experiment_control"
    t.boolean "reflection_generated", default: false
    t.index ["agent_plugin_id", "status"], name: "index_agent_plugin_executions_on_agent_plugin_id_and_status"
    t.index ["agent_plugin_id"], name: "index_agent_plugin_executions_on_agent_plugin_id"
    t.index ["evolution_experiment_id"], name: "index_agent_plugin_executions_on_evolution_experiment_id"
    t.index ["model_id"], name: "index_agent_plugin_executions_on_model_id"
    t.index ["started_at"], name: "index_agent_plugin_executions_on_started_at"
    t.index ["status"], name: "index_agent_plugin_executions_on_status"
    t.index ["user_id", "created_at"], name: "index_agent_plugin_executions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_agent_plugin_executions_on_user_id"
    t.index ["workflow_execution_id"], name: "index_agent_plugin_executions_on_workflow_execution_id"
  end

  create_table "agent_plugins", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "role", default: "executor"
    t.text "description"
    t.string "version", default: "1.0.0"
    t.string "status", default: "draft", null: false
    t.string "agent_class"
    t.jsonb "configuration", default: {}
    t.jsonb "system_prompt", default: {}
    t.jsonb "capabilities_definition", default: {}
    t.integer "priority", default: 50
    t.bigint "entity_id"
    t.datetime "last_activated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ai_model", default: "claude-sonnet-4"
    t.jsonb "model_config", default: {}
    t.string "execution_strategy", default: "standard"
    t.jsonb "remote_config", default: {}
    t.vector "embedding", limit: 1536
    t.boolean "is_public", default: false
    t.datetime "published_at"
    t.bigint "user_id"
    t.datetime "probation_started_at"
    t.jsonb "probation_reasons", default: []
    t.float "priority_score", default: 1.0
    t.datetime "sabbatical_until"
    t.bigint "parent_agent_id"
    t.integer "generation", default: 1
    t.jsonb "lineage", default: []
    t.datetime "graduated_at"
    t.string "primary_niche"
    t.jsonb "specialties", default: []
    t.jsonb "weaknesses", default: []
    t.boolean "protected_status", default: false
    t.datetime "last_refinement_at"
    t.float "refinement_priority", default: 0.0
    t.bigint "school_enrollment_id"
    t.string "publish_status", default: "private", null: false
    t.string "security_rating"
    t.text "security_reason"
    t.text "review_notes"
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.integer "usage_count", default: 0, null: false
    t.string "spaces", default: [], array: true
    t.bigint "app_module_id"
    t.bigint "app_id"
    t.string "lifecycle_stage", default: "active"
    t.text "birth_reason"
    t.jsonb "parent_agent_ids", default: []
    t.jsonb "discovered_specializations", default: []
    t.datetime "last_reflection_at"
    t.datetime "last_evolution_at"
    t.integer "evolution_count", default: 0
    t.boolean "autonomous_goals_enabled", default: true
    t.index ["ai_model"], name: "index_agent_plugins_on_ai_model"
    t.index ["app_id"], name: "index_agent_plugins_on_app_id"
    t.index ["app_module_id"], name: "index_agent_plugins_on_app_module_id"
    t.index ["embedding"], name: "index_agent_plugins_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["entity_id", "status"], name: "index_agent_plugins_on_entity_id_and_status"
    t.index ["entity_id", "user_id"], name: "index_agent_plugins_on_entity_id_and_user_id"
    t.index ["entity_id"], name: "index_agent_plugins_on_entity_id"
    t.index ["execution_strategy"], name: "index_agent_plugins_on_execution_strategy"
    t.index ["generation"], name: "index_agent_plugins_on_generation"
    t.index ["is_public", "publish_status"], name: "idx_agent_plugins_public_status"
    t.index ["is_public"], name: "index_agent_plugins_on_is_public"
    t.index ["lifecycle_stage"], name: "index_agent_plugins_on_lifecycle_stage"
    t.index ["parent_agent_id"], name: "index_agent_plugins_on_parent_agent_id"
    t.index ["primary_niche"], name: "index_agent_plugins_on_primary_niche"
    t.index ["priority"], name: "index_agent_plugins_on_priority"
    t.index ["priority_score"], name: "index_agent_plugins_on_priority_score"
    t.index ["protected_status"], name: "index_agent_plugins_on_protected_status"
    t.index ["publish_status"], name: "index_agent_plugins_on_publish_status"
    t.index ["reviewed_by_id"], name: "index_agent_plugins_on_reviewed_by_id"
    t.index ["role"], name: "index_agent_plugins_on_role"
    t.index ["school_enrollment_id"], name: "index_agent_plugins_on_school_enrollment_id"
    t.index ["security_rating"], name: "index_agent_plugins_on_security_rating"
    t.index ["slug"], name: "index_agent_plugins_on_slug", unique: true
    t.index ["spaces"], name: "index_agent_plugins_on_spaces", using: :gin
    t.index ["status"], name: "index_agent_plugins_on_status"
    t.index ["user_id"], name: "index_agent_plugins_on_user_id"
  end

  create_table "agent_reflections", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "agent_plugin_id", null: false
    t.bigint "agent_plugin_execution_id"
    t.string "reflection_type", null: false
    t.integer "efficiency_score"
    t.integer "quality_score"
    t.integer "tool_usage_score"
    t.integer "communication_score"
    t.integer "overall_score"
    t.jsonb "identified_issues", default: []
    t.jsonb "improvement_ideas", default: []
    t.jsonb "knowledge_gaps", default: []
    t.jsonb "strengths_identified", default: []
    t.jsonb "skills_to_develop", default: []
    t.jsonb "peer_comparison", default: {}
    t.jsonb "learning_plan", default: {}
    t.boolean "learning_tasks_scheduled", default: false
    t.bigint "triggered_enrollment_id"
    t.text "raw_reflection"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_execution_id"], name: "index_agent_reflections_on_agent_plugin_execution_id"
    t.index ["agent_plugin_id", "created_at"], name: "index_agent_reflections_on_agent_plugin_id_and_created_at"
    t.index ["agent_plugin_id", "reflection_type"], name: "index_agent_reflections_on_agent_plugin_id_and_reflection_type"
    t.index ["agent_plugin_id"], name: "index_agent_reflections_on_agent_plugin_id"
    t.index ["entity_id"], name: "index_agent_reflections_on_entity_id"
    t.index ["triggered_enrollment_id"], name: "index_agent_reflections_on_triggered_enrollment_id"
  end

  create_table "agent_relationships", force: :cascade do |t|
    t.bigint "requester_id", null: false
    t.bigint "helper_id", null: false
    t.bigint "entity_id", null: false
    t.integer "total_collaborations", default: 0, null: false
    t.integer "successful_collaborations", default: 0, null: false
    t.float "total_quality", default: 0.0
    t.bigint "total_response_time_ms", default: 0
    t.jsonb "helpfulness_ratings", default: []
    t.float "compatibility_score", default: 0.5
    t.float "trust_score", default: 0.5
    t.bigint "inherited_from_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "knowledge_shares_count", default: 0
    t.datetime "last_knowledge_share_at"
    t.string "relationship_type"
    t.index ["compatibility_score"], name: "index_agent_relationships_on_compatibility_score"
    t.index ["entity_id"], name: "index_agent_relationships_on_entity_id"
    t.index ["helper_id"], name: "index_agent_relationships_on_helper_id"
    t.index ["inherited_from_id"], name: "index_agent_relationships_on_inherited_from_id"
    t.index ["requester_id", "helper_id"], name: "index_agent_relationships_on_requester_id_and_helper_id", unique: true
    t.index ["requester_id"], name: "index_agent_relationships_on_requester_id"
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

  create_table "agent_school_enrollments", force: :cascade do |t|
    t.bigint "agent_plugin_id", null: false
    t.bigint "student_agent_id"
    t.bigint "entity_id", null: false
    t.string "status", default: "enrolled", null: false
    t.string "enrollment_reason", null: false
    t.integer "attempt_number", default: 1, null: false
    t.jsonb "diagnosis", default: {}
    t.jsonb "curriculum_applied", default: []
    t.jsonb "comparison_results", default: {}
    t.jsonb "irreplaceability_assessment", default: {}
    t.string "outcome"
    t.datetime "enrolled_at"
    t.datetime "diagnosis_completed_at"
    t.datetime "curriculum_completed_at"
    t.datetime "testing_started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "triggered_by_goal_id"
    t.bigint "evolution_cycle_id"
    t.index ["agent_plugin_id", "attempt_number"], name: "idx_on_agent_plugin_id_attempt_number_00e6ae94bc"
    t.index ["agent_plugin_id"], name: "index_agent_school_enrollments_on_agent_plugin_id"
    t.index ["entity_id"], name: "index_agent_school_enrollments_on_entity_id"
    t.index ["evolution_cycle_id"], name: "index_agent_school_enrollments_on_evolution_cycle_id"
    t.index ["outcome"], name: "index_agent_school_enrollments_on_outcome"
    t.index ["status"], name: "index_agent_school_enrollments_on_status"
    t.index ["student_agent_id"], name: "index_agent_school_enrollments_on_student_agent_id"
    t.index ["triggered_by_goal_id"], name: "index_agent_school_enrollments_on_triggered_by_goal_id"
  end

  create_table "agent_scratchpads", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.string "session_id", null: false
    t.string "key", null: false
    t.jsonb "data", default: {}
    t.string "data_type"
    t.text "description"
    t.bigint "source_agent_plugin_id"
    t.bigint "source_execution_id"
    t.datetime "expires_at", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "session_id"], name: "index_agent_scratchpads_on_entity_id_and_session_id"
    t.index ["entity_id"], name: "index_agent_scratchpads_on_entity_id"
    t.index ["expires_at"], name: "index_agent_scratchpads_on_expires_at"
    t.index ["session_id", "key"], name: "index_agent_scratchpads_on_session_id_and_key", unique: true
    t.index ["session_id"], name: "index_agent_scratchpads_on_session_id"
    t.index ["source_agent_plugin_id"], name: "index_agent_scratchpads_on_source_agent_plugin_id"
    t.index ["source_execution_id"], name: "index_agent_scratchpads_on_source_execution_id"
    t.index ["user_id"], name: "index_agent_scratchpads_on_user_id"
  end

  create_table "agent_simulations", force: :cascade do |t|
    t.bigint "agent_genome_id", null: false
    t.bigint "agent_plugin_id"
    t.string "task_type"
    t.text "task_prompt"
    t.jsonb "result", default: {}
    t.float "score"
    t.text "feedback"
    t.integer "duration_ms"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_genome_id", "score"], name: "index_agent_simulations_on_agent_genome_id_and_score"
    t.index ["agent_genome_id"], name: "index_agent_simulations_on_agent_genome_id"
    t.index ["agent_plugin_id"], name: "index_agent_simulations_on_agent_plugin_id"
  end

  create_table "agent_task_proposals", force: :cascade do |t|
    t.bigint "proposing_agent_id"
    t.bigint "receiving_agent_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "user_id"
    t.string "status", default: "proposed", null: false
    t.text "task_description", null: false
    t.string "task_type"
    t.jsonb "required_capabilities", default: []
    t.jsonb "object_types", default: []
    t.jsonb "tools_needed", default: []
    t.jsonb "context", default: {}
    t.boolean "accepted"
    t.float "confidence"
    t.text "rejection_reason"
    t.jsonb "missing_capabilities", default: []
    t.jsonb "missing_tools", default: []
    t.jsonb "suggested_alternatives", default: []
    t.jsonb "evaluation_details", default: {}
    t.datetime "proposed_at"
    t.datetime "evaluated_at"
    t.datetime "accepted_at"
    t.datetime "rejected_at"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "failed_at"
    t.datetime "expires_at"
    t.bigint "agent_work_item_id"
    t.bigint "agent_plugin_execution_id"
    t.boolean "task_succeeded"
    t.text "failure_reason"
    t.jsonb "outcome_metrics", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted"], name: "index_agent_task_proposals_on_accepted"
    t.index ["agent_plugin_execution_id"], name: "index_agent_task_proposals_on_agent_plugin_execution_id"
    t.index ["agent_work_item_id"], name: "index_agent_task_proposals_on_agent_work_item_id"
    t.index ["entity_id", "created_at"], name: "index_agent_task_proposals_on_entity_id_and_created_at"
    t.index ["entity_id"], name: "index_agent_task_proposals_on_entity_id"
    t.index ["proposing_agent_id", "status"], name: "index_agent_task_proposals_on_proposing_agent_id_and_status"
    t.index ["proposing_agent_id"], name: "index_agent_task_proposals_on_proposing_agent_id"
    t.index ["receiving_agent_id", "status"], name: "index_agent_task_proposals_on_receiving_agent_id_and_status"
    t.index ["receiving_agent_id"], name: "index_agent_task_proposals_on_receiving_agent_id"
    t.index ["status"], name: "index_agent_task_proposals_on_status"
    t.index ["task_succeeded"], name: "index_agent_task_proposals_on_task_succeeded"
    t.index ["task_type"], name: "index_agent_task_proposals_on_task_type"
    t.index ["user_id"], name: "index_agent_task_proposals_on_user_id"
  end

  create_table "agent_template_bindings", force: :cascade do |t|
    t.bigint "workflow_template_id", null: false
    t.bigint "agent_plugin_id", null: false
    t.string "phase"
    t.boolean "required", default: false
    t.integer "execution_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_id"], name: "index_agent_template_bindings_on_agent_plugin_id"
    t.index ["workflow_template_id", "agent_plugin_id", "phase"], name: "index_agent_template_bindings_unique", unique: true
    t.index ["workflow_template_id", "phase"], name: "idx_on_workflow_template_id_phase_15a4218812"
    t.index ["workflow_template_id"], name: "index_agent_template_bindings_on_workflow_template_id"
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

  create_table "agent_tools", force: :cascade do |t|
    t.bigint "agent_plugin_id", null: false
    t.string "tool_name", null: false
    t.boolean "required", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_id", "tool_name"], name: "index_agent_tools_on_plugin_and_tool", unique: true
    t.index ["agent_plugin_id"], name: "index_agent_tools_on_agent_plugin_id"
    t.index ["tool_name"], name: "index_agent_tools_on_tool_name"
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

  create_table "agent_work_items", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.bigint "agent_plugin_id"
    t.bigint "scheduled_task_run_id"
    t.bigint "agent_plugin_execution_id"
    t.bigint "scout_conversation_id"
    t.string "work_type", null: false
    t.string "title", null: false
    t.text "summary"
    t.text "details"
    t.string "asset_type"
    t.bigint "asset_id"
    t.jsonb "asset_data", default: {}
    t.boolean "read", default: false
    t.datetime "read_at"
    t.boolean "starred", default: false
    t.boolean "archived", default: false
    t.datetime "archived_at"
    t.string "priority", default: "normal"
    t.boolean "requires_action", default: false
    t.string "action_type"
    t.datetime "action_due_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_execution_id"], name: "index_agent_work_items_on_agent_plugin_execution_id"
    t.index ["agent_plugin_id"], name: "index_agent_work_items_on_agent_plugin_id"
    t.index ["archived"], name: "index_agent_work_items_on_archived"
    t.index ["asset_type", "asset_id"], name: "index_agent_work_items_on_asset_type_and_asset_id"
    t.index ["created_at"], name: "index_agent_work_items_on_created_at"
    t.index ["entity_id", "user_id", "archived"], name: "index_agent_work_items_on_entity_id_and_user_id_and_archived"
    t.index ["entity_id", "user_id", "read"], name: "index_agent_work_items_on_entity_id_and_user_id_and_read"
    t.index ["entity_id"], name: "index_agent_work_items_on_entity_id"
    t.index ["priority"], name: "index_agent_work_items_on_priority"
    t.index ["read"], name: "index_agent_work_items_on_read"
    t.index ["requires_action"], name: "index_agent_work_items_on_requires_action"
    t.index ["scheduled_task_run_id"], name: "index_agent_work_items_on_scheduled_task_run_id"
    t.index ["scout_conversation_id"], name: "index_agent_work_items_on_scout_conversation_id"
    t.index ["starred"], name: "index_agent_work_items_on_starred"
    t.index ["user_id"], name: "index_agent_work_items_on_user_id"
    t.index ["work_type"], name: "index_agent_work_items_on_work_type"
  end

  create_table "ai_rulesets", force: :cascade do |t|
    t.bigint "entity_id"
    t.string "name", null: false
    t.text "description"
    t.string "category", null: false
    t.text "rules", default: [], array: true
    t.boolean "is_active", default: true
    t.integer "priority", default: 0
    t.boolean "is_system", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_ai_rulesets_on_category"
    t.index ["entity_id", "is_active"], name: "index_ai_rulesets_on_entity_id_and_is_active"
    t.index ["entity_id"], name: "index_ai_rulesets_on_entity_id"
    t.index ["is_system"], name: "index_ai_rulesets_on_is_system"
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

  create_table "amos_thinking_sessions", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "session_type", default: "nightly", null: false
    t.string "status", default: "running"
    t.jsonb "context_analyzed", default: {}
    t.integer "errors_analyzed", default: 0
    t.integer "tickets_analyzed", default: 0
    t.integer "feature_requests_analyzed", default: 0
    t.text "reflection_summary"
    t.text "improvement_ideas"
    t.integer "bounties_created", default: 0
    t.integer "total_points_allocated", default: 0
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "duration_seconds"
    t.integer "llm_tokens_used", default: 0
    t.decimal "llm_cost", precision: 10, scale: 4, default: "0.0"
    t.text "thinking_log"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_amos_thinking_sessions_on_created_at"
    t.index ["entity_id"], name: "index_amos_thinking_sessions_on_entity_id"
    t.index ["session_type"], name: "index_amos_thinking_sessions_on_session_type"
    t.index ["status"], name: "index_amos_thinking_sessions_on_status"
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

  create_table "app_modules", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "created_by_id"
    t.string "slug", null: false
    t.string "name", null: false
    t.text "description"
    t.string "version", default: "1.0.0"
    t.string "icon"
    t.string "status", default: "draft", null: false
    t.string "visibility", default: "entity_private"
    t.string "author_type", default: "amos"
    t.jsonb "components", default: {}
    t.jsonb "ui_modes", default: {"simple" => true, "advanced" => false}
    t.jsonb "dependencies", default: []
    t.jsonb "permissions", default: []
    t.boolean "show_in_menu", default: true
    t.integer "menu_order", default: 100
    t.string "menu_parent"
    t.jsonb "metadata", default: {}
    t.datetime "deployed_at"
    t.datetime "last_tested_at"
    t.jsonb "test_results", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "app_id"
    t.jsonb "field_config", default: {}
    t.jsonb "action_config", default: []
    t.jsonb "tool_config", default: []
    t.jsonb "relationship_config", default: []
    t.boolean "is_primary", default: false
    t.index ["app_id"], name: "index_app_modules_on_app_id"
    t.index ["author_type"], name: "index_app_modules_on_author_type"
    t.index ["created_by_id"], name: "index_app_modules_on_created_by_id"
    t.index ["entity_id", "slug"], name: "index_app_modules_on_entity_id_and_slug", unique: true
    t.index ["entity_id"], name: "index_app_modules_on_entity_id"
    t.index ["status"], name: "index_app_modules_on_status"
    t.index ["visibility"], name: "index_app_modules_on_visibility"
  end

  create_table "application_plans", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "created_by_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "archetype"
    t.string "status", default: "drafting", null: false
    t.jsonb "plan_spec", default: {}, null: false
    t.jsonb "refinement_history", default: [], null: false
    t.jsonb "build_results", default: {}, null: false
    t.text "error_message"
    t.jsonb "build_log", default: [], null: false
    t.datetime "approved_at"
    t.datetime "build_started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["archetype"], name: "index_application_plans_on_archetype"
    t.index ["created_by_id"], name: "index_application_plans_on_created_by_id"
    t.index ["entity_id", "status"], name: "index_application_plans_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_application_plans_on_entity_id"
    t.index ["status"], name: "index_application_plans_on_status"
  end

  create_table "apps", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "created_by_id"
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "icon", default: "grid"
    t.string "color", default: "#6366f1"
    t.string "status", default: "designing", null: false
    t.jsonb "intent", default: {}
    t.jsonb "blueprint", default: {}
    t.jsonb "user_stories", default: []
    t.jsonb "personas", default: []
    t.datetime "blueprint_approved_at"
    t.datetime "build_started_at"
    t.datetime "build_completed_at"
    t.datetime "published_at"
    t.jsonb "settings", default: {}
    t.jsonb "metadata", default: {}
    t.integer "version", default: 1
    t.jsonb "changelog", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_apps_on_created_by_id"
    t.index ["entity_id", "slug"], name: "index_apps_on_entity_id_and_slug", unique: true
    t.index ["entity_id"], name: "index_apps_on_entity_id"
    t.index ["name"], name: "index_apps_on_name"
    t.index ["status"], name: "index_apps_on_status"
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

  create_table "automation_codes", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "web_app_id"
    t.bigint "app_module_id"
    t.bigint "created_by_id"
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "trigger_type", null: false
    t.jsonb "trigger_config", default: {}
    t.text "code", null: false
    t.integer "code_version", default: 1
    t.datetime "code_generated_at"
    t.string "code_generated_by"
    t.jsonb "sample_input", default: {}
    t.jsonb "sample_output", default: {}
    t.boolean "is_tested", default: false
    t.datetime "last_tested_at"
    t.integer "execution_count", default: 0
    t.integer "success_count", default: 0
    t.integer "error_count", default: 0
    t.datetime "last_executed_at"
    t.datetime "last_error_at"
    t.text "last_error_message"
    t.float "avg_execution_time_ms"
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "workflow_definition", default: {}
    t.jsonb "compiled_steps", default: []
    t.datetime "compiled_at"
    t.jsonb "compilation_errors", default: []
    t.boolean "is_compiled", default: false
    t.boolean "design_mode", default: true
    t.index ["app_module_id", "trigger_type"], name: "index_automation_codes_on_app_module_id_and_trigger_type"
    t.index ["app_module_id"], name: "index_automation_codes_on_app_module_id"
    t.index ["created_by_id"], name: "index_automation_codes_on_created_by_id"
    t.index ["entity_id", "slug"], name: "index_automation_codes_on_entity_id_and_slug", unique: true
    t.index ["entity_id", "status"], name: "index_automation_codes_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_automation_codes_on_entity_id"
    t.index ["trigger_type"], name: "index_automation_codes_on_trigger_type"
    t.index ["web_app_id", "trigger_type"], name: "index_automation_codes_on_web_app_id_and_trigger_type"
    t.index ["web_app_id"], name: "index_automation_codes_on_web_app_id"
  end

  create_table "automation_executions", force: :cascade do |t|
    t.bigint "automation_code_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "triggered_by_id"
    t.string "trigger_source"
    t.jsonb "trigger_data", default: {}
    t.jsonb "execution_result", default: {}
    t.datetime "started_at"
    t.datetime "completed_at"
    t.float "duration_ms"
    t.string "status", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "step_executions", default: []
    t.index ["automation_code_id", "status"], name: "index_automation_executions_on_automation_code_id_and_status"
    t.index ["automation_code_id"], name: "index_automation_executions_on_automation_code_id"
    t.index ["entity_id", "created_at"], name: "index_automation_executions_on_entity_id_and_created_at"
    t.index ["entity_id"], name: "index_automation_executions_on_entity_id"
    t.index ["triggered_by_id"], name: "index_automation_executions_on_triggered_by_id"
  end

  create_table "benchmark_runs", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "run_id", null: false
    t.string "run_type", null: false
    t.string "benchmark_category"
    t.string "agent_slug"
    t.boolean "collaboration_enabled", default: true
    t.integer "total_tasks", default: 0
    t.integer "correct_count", default: 0
    t.integer "failed_count", default: 0
    t.float "accuracy_percentage"
    t.integer "avg_execution_time_ms"
    t.integer "total_tokens_used", default: 0
    t.float "total_cost_cents", default: 0.0
    t.integer "collaboration_requests", default: 0
    t.integer "collaboration_helped_count", default: 0
    t.string "environment"
    t.string "model_used"
    t.string "git_commit"
    t.jsonb "metadata", default: {}
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["benchmark_category"], name: "index_benchmark_runs_on_benchmark_category"
    t.index ["entity_id", "created_at"], name: "index_benchmark_runs_on_entity_id_and_created_at"
    t.index ["entity_id"], name: "index_benchmark_runs_on_entity_id"
    t.index ["run_id"], name: "index_benchmark_runs_on_run_id", unique: true
    t.index ["run_type"], name: "index_benchmark_runs_on_run_type"
  end

  create_table "benchmark_task_results", force: :cascade do |t|
    t.bigint "benchmark_run_id", null: false
    t.bigint "agent_plugin_id"
    t.bigint "agent_plugin_execution_id"
    t.string "task_id", null: false
    t.string "category"
    t.string "difficulty"
    t.text "question"
    t.text "expected_answer"
    t.text "actual_answer"
    t.boolean "correct", default: false
    t.integer "execution_time_ms"
    t.integer "tokens_used"
    t.float "cost_cents"
    t.boolean "asked_for_help", default: false
    t.string "helper_agent_slug"
    t.boolean "collaboration_helped", default: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_execution_id"], name: "index_benchmark_task_results_on_agent_plugin_execution_id"
    t.index ["agent_plugin_id"], name: "index_benchmark_task_results_on_agent_plugin_id"
    t.index ["benchmark_run_id", "task_id"], name: "index_benchmark_task_results_on_benchmark_run_id_and_task_id"
    t.index ["benchmark_run_id"], name: "index_benchmark_task_results_on_benchmark_run_id"
    t.index ["task_id"], name: "index_benchmark_task_results_on_task_id"
  end

  create_table "billing_configurations", force: :cascade do |t|
    t.string "name", default: "default", null: false
    t.decimal "uplift_percentage", precision: 5, scale: 2, default: "20.0"
    t.decimal "ai_tokens_rate", precision: 10, scale: 6, default: "1.0"
    t.decimal "email_rate", precision: 10, scale: 4, default: "10.0"
    t.decimal "storage_rate_mb", precision: 10, scale: 4, default: "1.0"
    t.decimal "api_call_rate", precision: 10, scale: 4, default: "0.1"
    t.decimal "other_compute_rate", precision: 10, scale: 4, default: "100.0"
    t.jsonb "model_multipliers", default: {"gpt-4o" => 0.8, "claude-3-opus" => 3.0, "claude-3-haiku" => 0.1, "claude-3-5-sonnet" => 1.0, "claude-sonnet-4-5" => 1.0}
    t.jsonb "purchase_tiers", default: [{"tokens" => 200000, "amount_usd" => 20, "bonus_tokens" => 0}, {"tokens" => 550000, "amount_usd" => 50, "bonus_tokens" => 50000}, {"tokens" => 1200000, "amount_usd" => 100, "bonus_tokens" => 200000}, {"tokens" => 2600000, "amount_usd" => 200, "bonus_tokens" => 600000}]
    t.integer "free_tokens_on_signup", default: 200000
    t.integer "default_auto_replenish_amount_usd", default: 20
    t.integer "default_monthly_limit_usd", default: 100
    t.boolean "is_active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_billing_configurations_on_is_active"
    t.index ["name"], name: "index_billing_configurations_on_name", unique: true
  end

  create_table "bounties", force: :cascade do |t|
    t.string "title", null: false
    t.text "description"
    t.string "bounty_type", null: false
    t.integer "points", default: 0, null: false
    t.string "status", default: "open"
    t.bigint "entity_id", null: false
    t.bigint "created_by_id"
    t.bigint "claimed_by_id"
    t.bigint "reviewed_by_id"
    t.bigint "support_ticket_id"
    t.text "ai_scoring_rationale"
    t.float "estimated_hours"
    t.integer "impact_score"
    t.integer "urgency_score"
    t.integer "complexity_score"
    t.datetime "claimed_at"
    t.datetime "submitted_at"
    t.datetime "approved_at"
    t.datetime "rejected_at"
    t.datetime "expires_at"
    t.text "submission_notes"
    t.text "review_notes"
    t.integer "final_points"
    t.string "source"
    t.jsonb "metadata", default: {}
    t.integer "upvotes", default: 0
    t.integer "downvotes", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "pr_url"
    t.integer "pr_number"
    t.string "commit_sha"
    t.string "branch_name"
    t.string "repo_url"
    t.string "work_url"
    t.jsonb "work_artifacts", default: []
    t.bigint "pull_request_submission_id"
    t.index ["bounty_type"], name: "index_bounties_on_bounty_type"
    t.index ["claimed_by_id"], name: "index_bounties_on_claimed_by_id"
    t.index ["commit_sha"], name: "index_bounties_on_commit_sha"
    t.index ["created_by_id"], name: "index_bounties_on_created_by_id"
    t.index ["entity_id", "status"], name: "index_bounties_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_bounties_on_entity_id"
    t.index ["points"], name: "index_bounties_on_points"
    t.index ["pr_number"], name: "index_bounties_on_pr_number"
    t.index ["pull_request_submission_id"], name: "index_bounties_on_pull_request_submission_id"
    t.index ["reviewed_by_id"], name: "index_bounties_on_reviewed_by_id"
    t.index ["source"], name: "index_bounties_on_source"
    t.index ["status", "bounty_type"], name: "index_bounties_on_status_and_bounty_type"
    t.index ["status"], name: "index_bounties_on_status"
    t.index ["support_ticket_id"], name: "index_bounties_on_support_ticket_id"
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
    t.string "company_size"
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
    t.jsonb "custom_fields", default: {}
    t.index ["custom_fields"], name: "index_campaigns_on_custom_fields", using: :gin
    t.index ["email_template_id"], name: "index_campaigns_on_email_template_id"
    t.index ["entity_id", "status"], name: "index_campaigns_on_entity_status"
    t.index ["entity_id"], name: "index_campaigns_on_entity_id"
    t.index ["user_id"], name: "index_campaigns_on_user_id"
  end

  create_table "code_fixes", force: :cascade do |t|
    t.bigint "debug_session_id", null: false
    t.bigint "support_ticket_id", null: false
    t.bigint "entity_id", null: false
    t.string "fix_id", null: false
    t.string "status", default: "drafting", null: false
    t.text "fix_description"
    t.string "fix_type"
    t.string "risk_level"
    t.jsonb "files_modified", default: []
    t.integer "files_changed_count", default: 0
    t.integer "lines_added", default: 0
    t.integer "lines_removed", default: 0
    t.jsonb "test_results", default: {}
    t.boolean "tests_passed", default: false
    t.boolean "lint_passed", default: false
    t.text "validation_notes"
    t.string "git_branch"
    t.string "git_commit_sha"
    t.string "base_commit_sha"
    t.string "reviewed_by"
    t.datetime "reviewed_at"
    t.text "review_notes"
    t.string "review_decision"
    t.datetime "applied_at"
    t.string "applied_by"
    t.datetime "rolled_back_at"
    t.string "rolled_back_by"
    t.text "rollback_reason"
    t.string "ai_model_used"
    t.integer "tokens_used", default: 0
    t.decimal "cost_usd", precision: 10, scale: 4, default: "0.0"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["debug_session_id"], name: "index_code_fixes_on_debug_session_id"
    t.index ["entity_id"], name: "index_code_fixes_on_entity_id"
    t.index ["fix_id"], name: "index_code_fixes_on_fix_id", unique: true
    t.index ["git_branch"], name: "index_code_fixes_on_git_branch"
    t.index ["git_commit_sha"], name: "index_code_fixes_on_git_commit_sha"
    t.index ["status"], name: "index_code_fixes_on_status"
    t.index ["support_ticket_id", "status"], name: "index_code_fixes_on_support_ticket_id_and_status"
    t.index ["support_ticket_id"], name: "index_code_fixes_on_support_ticket_id"
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

  create_table "community_energy_pools", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.float "current_balance", default: 0.0, null: false
    t.float "total_deposited", default: 0.0, null: false
    t.float "total_distributed", default: 0.0, null: false
    t.integer "distribution_count", default: 0
    t.datetime "last_distribution_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_community_energy_pools_on_entity_id"
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
    t.bigint "user_id"
    t.index ["entity_id"], name: "index_connections_on_entity_id"
    t.index ["integration_id"], name: "index_connections_on_integration_id"
    t.index ["user_id", "integration_id"], name: "index_connections_on_user_and_integration"
    t.index ["user_id"], name: "index_connections_on_user_id"
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
    t.string "lifecycle_stage", default: "subscriber"
    t.integer "lead_score", default: 0
    t.string "lead_source"
    t.bigint "assigned_user_id"
    t.bigint "assigned_agent_id"
    t.datetime "last_activity_at"
    t.datetime "last_contacted_at"
    t.datetime "next_follow_up_at"
    t.datetime "converted_at"
    t.string "conversion_source"
    t.jsonb "custom_fields", default: {}
    t.index ["assigned_agent_id"], name: "index_contacts_on_assigned_agent_id"
    t.index ["assigned_user_id", "lifecycle_stage"], name: "index_contacts_on_assigned_user_id_and_lifecycle_stage"
    t.index ["assigned_user_id"], name: "index_contacts_on_assigned_user_id"
    t.index ["custom_fields"], name: "index_contacts_on_custom_fields", using: :gin
    t.index ["entity_id", "lead"], name: "index_contacts_on_entity_lead"
    t.index ["entity_id", "lifecycle_stage"], name: "index_contacts_on_entity_id_and_lifecycle_stage"
    t.index ["entity_id", "status"], name: "index_contacts_on_entity_status"
    t.index ["entity_id"], name: "index_contacts_on_entity_id"
    t.index ["last_activity_at"], name: "index_contacts_on_last_activity_at"
    t.index ["lead"], name: "index_contacts_on_lead"
    t.index ["lead_score"], name: "index_contacts_on_lead_score"
    t.index ["lifecycle_stage"], name: "index_contacts_on_lifecycle_stage"
    t.index ["next_follow_up_at"], name: "index_contacts_on_next_follow_up_at"
    t.index ["opted_out"], name: "index_contacts_on_opted_out"
    t.index ["user_id"], name: "index_contacts_on_user_id"
  end

  create_table "context_graph_stats", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.date "stats_date", null: false
    t.integer "total_decisions", default: 0
    t.integer "decisions_with_precedents", default: 0
    t.integer "exceptions_granted", default: 0
    t.integer "approvals_pending", default: 0
    t.integer "approvals_granted", default: 0
    t.integer "approvals_rejected", default: 0
    t.decimal "avg_confidence_score", precision: 5, scale: 4
    t.decimal "precedent_match_rate", precision: 5, scale: 4
    t.decimal "exception_success_rate", precision: 5, scale: 4
    t.integer "unique_precedent_chains", default: 0
    t.integer "avg_precedent_depth", default: 0
    t.jsonb "decision_type_breakdown", default: {}
    t.jsonb "top_precedents", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "stats_date"], name: "index_context_graph_stats_on_entity_id_and_stats_date", unique: true
    t.index ["entity_id"], name: "index_context_graph_stats_on_entity_id"
  end

  create_table "contributions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id"
    t.bigint "reviewed_by_id"
    t.string "contribution_type", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.integer "status", default: 0, null: false
    t.decimal "stake_value", precision: 18, scale: 4
    t.decimal "complexity_multiplier", precision: 5, scale: 2, default: "1.0"
    t.string "external_reference"
    t.string "external_url"
    t.text "review_notes"
    t.datetime "reviewed_at"
    t.datetime "merged_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contribution_type"], name: "index_contributions_on_contribution_type"
    t.index ["entity_id"], name: "index_contributions_on_entity_id"
    t.index ["external_reference"], name: "index_contributions_on_external_reference"
    t.index ["reviewed_by_id"], name: "index_contributions_on_reviewed_by_id"
    t.index ["status"], name: "index_contributions_on_status"
    t.index ["user_id", "contribution_type"], name: "index_contributions_on_user_id_and_contribution_type"
    t.index ["user_id", "status"], name: "index_contributions_on_user_id_and_status"
    t.index ["user_id"], name: "index_contributions_on_user_id"
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

  create_table "conversation_summaries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "session_id", null: false
    t.text "summary", null: false
    t.text "key_topics"
    t.text "key_decisions"
    t.text "action_items"
    t.text "context_for_future"
    t.integer "message_start_index", null: false
    t.integer "message_end_index", null: false
    t.integer "messages_summarized", null: false
    t.integer "original_tokens"
    t.integer "summary_tokens"
    t.string "model_used"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_conversation_summaries_on_entity_id"
    t.index ["message_end_index"], name: "index_conversation_summaries_on_message_end_index"
    t.index ["session_id", "active"], name: "index_conversation_summaries_on_session_id_and_active"
    t.index ["session_id"], name: "index_conversation_summaries_on_session_id"
    t.index ["user_id", "entity_id", "session_id"], name: "idx_on_user_id_entity_id_session_id_708c948e1b"
    t.index ["user_id"], name: "index_conversation_summaries_on_user_id"
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

  create_table "custom_domains", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.string "domain_name", null: false
    t.string "subdomain"
    t.string "cname_target", null: false
    t.string "verification_token"
    t.string "web_status", default: "pending"
    t.datetime "web_verified_at"
    t.string "ssl_status", default: "pending"
    t.string "ssl_certificate_arn"
    t.datetime "ssl_provisioned_at"
    t.string "email_status", default: "pending"
    t.string "ses_identity_arn"
    t.datetime "email_verified_at"
    t.jsonb "dns_records", default: {}
    t.bigint "connection_id"
    t.boolean "auto_dns_configured", default: false
    t.boolean "is_primary", default: false
    t.boolean "redirect_www", default: true
    t.jsonb "metadata", default: {}
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cname_target"], name: "index_custom_domains_on_cname_target", unique: true
    t.index ["connection_id"], name: "index_custom_domains_on_connection_id"
    t.index ["domain_name"], name: "index_custom_domains_on_domain_name", unique: true
    t.index ["email_status"], name: "index_custom_domains_on_email_status"
    t.index ["entity_id", "is_primary"], name: "index_custom_domains_on_entity_id_and_is_primary"
    t.index ["entity_id"], name: "index_custom_domains_on_entity_id"
    t.index ["user_id"], name: "index_custom_domains_on_user_id"
    t.index ["web_status"], name: "index_custom_domains_on_web_status"
  end

  create_table "custom_field_definitions", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "app_module_id"
    t.string "model_type", null: false
    t.string "field_name", null: false
    t.string "field_type", null: false
    t.string "field_label"
    t.text "field_description"
    t.string "display_type", default: "text"
    t.integer "display_order", default: 0
    t.boolean "show_in_list", default: true
    t.boolean "show_in_form", default: true
    t.boolean "show_in_search", default: false
    t.jsonb "options", default: []
    t.jsonb "validations", default: {}
    t.string "default_value"
    t.string "reference_model"
    t.string "reference_display_field", default: "name"
    t.boolean "active", default: true
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_custom_field_definitions_on_active"
    t.index ["app_module_id"], name: "index_custom_field_definitions_on_app_module_id"
    t.index ["entity_id", "model_type", "field_name"], name: "idx_custom_fields_entity_model_name", unique: true
    t.index ["entity_id", "model_type"], name: "index_custom_field_definitions_on_entity_id_and_model_type"
    t.index ["entity_id"], name: "index_custom_field_definitions_on_entity_id"
    t.index ["field_type"], name: "index_custom_field_definitions_on_field_type"
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

  create_table "debug_sessions", force: :cascade do |t|
    t.bigint "support_ticket_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "user_id"
    t.string "session_id", null: false
    t.string "status", default: "gathering_info", null: false
    t.jsonb "conversation_history", default: []
    t.jsonb "findings", default: {}
    t.text "root_cause_analysis"
    t.decimal "confidence_score", precision: 5, scale: 4
    t.jsonb "proposed_fixes", default: []
    t.integer "selected_fix_index"
    t.text "fix_rationale"
    t.boolean "reproduced", default: false
    t.jsonb "reproduction_steps", default: []
    t.jsonb "reproduction_results", default: {}
    t.string "ai_model_used"
    t.integer "total_tokens_used", default: 0
    t.decimal "total_cost_usd", precision: 10, scale: 4, default: "0.0"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_debug_sessions_on_entity_id"
    t.index ["session_id"], name: "index_debug_sessions_on_session_id", unique: true
    t.index ["status"], name: "index_debug_sessions_on_status"
    t.index ["support_ticket_id", "status"], name: "index_debug_sessions_on_support_ticket_id_and_status"
    t.index ["support_ticket_id"], name: "index_debug_sessions_on_support_ticket_id"
    t.index ["user_id"], name: "index_debug_sessions_on_user_id"
  end

  create_table "decision_precedents", force: :cascade do |t|
    t.bigint "decision_trace_id", null: false
    t.bigint "precedent_decision_id", null: false
    t.decimal "similarity_score", precision: 5, scale: 4, null: false
    t.string "influence_type", null: false
    t.boolean "outcome_matches"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["decision_trace_id", "precedent_decision_id"], name: "idx_decision_precedent_unique", unique: true
    t.index ["decision_trace_id"], name: "index_decision_precedents_on_decision_trace_id"
    t.index ["influence_type"], name: "index_decision_precedents_on_influence_type"
    t.index ["precedent_decision_id"], name: "index_decision_precedents_on_precedent_decision_id"
  end

  create_table "decision_traces", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id"
    t.bigint "agent_plugin_id"
    t.bigint "agent_lightning_trace_id"
    t.bigint "parent_decision_id"
    t.string "trace_id", null: false
    t.string "decision_type", null: false
    t.text "decision_summary", null: false
    t.text "reasoning"
    t.jsonb "context_gathered", default: {}
    t.jsonb "inputs_used", default: []
    t.jsonb "policies_evaluated", default: []
    t.boolean "is_exception", default: false
    t.text "exception_justification"
    t.boolean "requires_approval", default: false
    t.string "approval_status"
    t.string "approved_by"
    t.datetime "approved_at"
    t.text "approval_notes"
    t.string "outcome"
    t.jsonb "outcome_details", default: {}
    t.decimal "outcome_quality_score", precision: 5, scale: 4
    t.datetime "outcome_recorded_at"
    t.decimal "confidence_score", precision: 5, scale: 4
    t.vector "embedding", limit: 1536
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_lightning_trace_id"], name: "index_decision_traces_on_agent_lightning_trace_id"
    t.index ["agent_plugin_id", "created_at"], name: "index_decision_traces_on_agent_plugin_id_and_created_at"
    t.index ["agent_plugin_id"], name: "index_decision_traces_on_agent_plugin_id"
    t.index ["approval_status"], name: "index_decision_traces_on_approval_status"
    t.index ["entity_id", "created_at"], name: "index_decision_traces_on_entity_id_and_created_at"
    t.index ["entity_id", "decision_type"], name: "index_decision_traces_on_entity_id_and_decision_type"
    t.index ["entity_id", "is_exception"], name: "index_decision_traces_on_entity_id_and_is_exception"
    t.index ["entity_id", "outcome"], name: "index_decision_traces_on_entity_id_and_outcome"
    t.index ["entity_id"], name: "index_decision_traces_on_entity_id"
    t.index ["parent_decision_id"], name: "index_decision_traces_on_parent_decision_id"
    t.index ["trace_id"], name: "index_decision_traces_on_trace_id", unique: true
    t.index ["user_id"], name: "index_decision_traces_on_user_id"
  end

  create_table "design_plans", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.bigint "landing_page_id"
    t.string "name", null: false
    t.string "design_type", default: "landing_page", null: false
    t.text "description"
    t.jsonb "plan_data", default: {}, null: false
    t.string "status", default: "draft", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "website_id"
    t.jsonb "data_sources", default: [], null: false
    t.bigint "app_id"
    t.bigint "module_canvas_id"
    t.index ["app_id"], name: "index_design_plans_on_app_id"
    t.index ["data_sources"], name: "index_design_plans_on_data_sources", using: :gin
    t.index ["entity_id", "user_id", "status"], name: "index_design_plans_on_entity_id_and_user_id_and_status"
    t.index ["entity_id"], name: "index_design_plans_on_entity_id"
    t.index ["landing_page_id"], name: "index_design_plans_on_landing_page_id"
    t.index ["module_canvas_id"], name: "index_design_plans_on_module_canvas_id"
    t.index ["status"], name: "index_design_plans_on_status"
    t.index ["user_id"], name: "index_design_plans_on_user_id"
    t.index ["website_id"], name: "index_design_plans_on_website_id"
  end

  create_table "device_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token", null: false
    t.string "platform", null: false
    t.string "endpoint_arn"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_device_tokens_on_token", unique: true
    t.index ["user_id", "active"], name: "index_device_tokens_on_user_id_and_active"
    t.index ["user_id"], name: "index_device_tokens_on_user_id"
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

  create_table "dynamic_contents", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.bigint "scout_conversation_id"
    t.bigint "agent_plugin_execution_id"
    t.bigint "scheduled_task_run_id"
    t.string "content_type", null: false
    t.string "title", null: false
    t.text "subtitle"
    t.text "html_content", null: false
    t.jsonb "data_snapshot", default: {}
    t.jsonb "generation_context", default: {}
    t.string "session_id"
    t.integer "message_index"
    t.string "category"
    t.jsonb "tags", default: []
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_execution_id"], name: "index_dynamic_contents_on_agent_plugin_execution_id"
    t.index ["category"], name: "index_dynamic_contents_on_category"
    t.index ["content_type"], name: "index_dynamic_contents_on_content_type"
    t.index ["created_at"], name: "index_dynamic_contents_on_created_at"
    t.index ["entity_id", "user_id"], name: "index_dynamic_contents_on_entity_id_and_user_id"
    t.index ["entity_id"], name: "index_dynamic_contents_on_entity_id"
    t.index ["scheduled_task_run_id"], name: "index_dynamic_contents_on_scheduled_task_run_id"
    t.index ["scout_conversation_id"], name: "index_dynamic_contents_on_scout_conversation_id"
    t.index ["session_id"], name: "index_dynamic_contents_on_session_id"
    t.index ["user_id"], name: "index_dynamic_contents_on_user_id"
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
    t.string "ses_message_id"
    t.index ["campaign_id", "id"], name: "index_email_deliveries_on_campaign_id_and_id"
    t.index ["campaign_id", "status", "sent_at"], name: "index_email_deliveries_on_campaign_status_sent"
    t.index ["campaign_id", "status"], name: "index_email_deliveries_on_campaign_id_and_status"
    t.index ["campaign_id"], name: "index_email_deliveries_on_campaign_id"
    t.index ["contact_id"], name: "index_email_deliveries_on_contact_id"
    t.index ["email_template_id"], name: "index_email_deliveries_on_email_template_id"
    t.index ["ses_message_id"], name: "index_email_deliveries_on_ses_message_id"
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
    t.boolean "use_shared_token_pool", default: false
    t.bigint "token_pool_owner_id"
    t.index ["bedrock_kb_id"], name: "index_entities_on_bedrock_kb_id"
    t.index ["bedrock_kb_status"], name: "index_entities_on_bedrock_kb_status"
    t.index ["bedrock_knowledge_base_id"], name: "index_entities_on_bedrock_knowledge_base_id"
    t.index ["bedrock_last_ingestion_job_id"], name: "index_entities_on_bedrock_last_ingestion_job_id"
    t.index ["slug"], name: "index_entities_on_slug", unique: true
    t.index ["stripe_customer_id"], name: "index_entities_on_stripe_customer_id"
    t.index ["stripe_subscription_id"], name: "index_entities_on_stripe_subscription_id"
    t.index ["subdomain"], name: "index_entities_on_subdomain", unique: true
    t.index ["subscription_status"], name: "index_entities_on_subscription_status"
    t.index ["token_pool_owner_id"], name: "index_entities_on_token_pool_owner_id"
    t.index ["use_bedrock_kb"], name: "index_entities_on_use_bedrock_kb"
  end

  create_table "entity_billing_accounts", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.integer "work_token_balance", default: 0, null: false
    t.string "stripe_customer_id"
    t.string "stripe_default_payment_method_id"
    t.boolean "has_payment_method", default: false
    t.boolean "auto_replenish_enabled", default: false
    t.integer "auto_replenish_threshold", default: 10000
    t.integer "auto_replenish_amount_usd", default: 50
    t.integer "monthly_limit_usd", default: 500
    t.integer "current_month_spend_cents", default: 0
    t.string "status", default: "active", null: false
    t.integer "lifetime_tokens_used", default: 0
    t.integer "lifetime_tokens_purchased", default: 0
    t.datetime "last_usage_at"
    t.datetime "last_purchase_at"
    t.integer "last_threshold_notified"
    t.integer "initial_tokens_granted"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_entity_billing_accounts_on_entity_id", unique: true
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

  create_table "error_log_entries", force: :cascade do |t|
    t.bigint "entity_id"
    t.bigint "support_ticket_id"
    t.string "log_level", null: false
    t.string "error_class"
    t.string "error_message"
    t.text "stack_trace"
    t.string "error_signature"
    t.string "source_file"
    t.integer "source_line"
    t.string "source_method"
    t.jsonb "context", default: {}
    t.datetime "occurred_at", null: false
    t.integer "occurrence_count", default: 1
    t.datetime "first_occurrence"
    t.datetime "last_occurrence"
    t.boolean "processed", default: false
    t.boolean "ticket_created", default: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "occurred_at"], name: "index_error_log_entries_on_entity_id_and_occurred_at"
    t.index ["entity_id"], name: "index_error_log_entries_on_entity_id"
    t.index ["error_signature", "processed"], name: "index_error_log_entries_on_error_signature_and_processed"
    t.index ["error_signature"], name: "index_error_log_entries_on_error_signature"
    t.index ["log_level"], name: "index_error_log_entries_on_log_level"
    t.index ["occurred_at"], name: "index_error_log_entries_on_occurred_at"
    t.index ["support_ticket_id"], name: "index_error_log_entries_on_support_ticket_id"
  end

  create_table "evolution_cycles", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "cycle_type", null: false
    t.string "status", default: "running"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.jsonb "metrics_snapshot", default: {}
    t.jsonb "anomalies_detected", default: []
    t.jsonb "opportunities_detected", default: []
    t.jsonb "threats_detected", default: []
    t.jsonb "analysis_results", default: {}
    t.jsonb "improvement_hypotheses", default: []
    t.integer "experiments_started", default: 0
    t.integer "experiments_completed", default: 0
    t.integer "experiments_successful", default: 0
    t.integer "goals_generated", default: 0
    t.integer "goals_completed", default: 0
    t.jsonb "evolutions_promoted", default: []
    t.jsonb "learnings", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "promotion_count", default: 0
    t.integer "anomaly_count", default: 0
    t.integer "duration_minutes", default: 0
    t.index ["entity_id", "cycle_type"], name: "index_evolution_cycles_on_entity_id_and_cycle_type"
    t.index ["entity_id", "status"], name: "index_evolution_cycles_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_evolution_cycles_on_entity_id"
    t.index ["started_at"], name: "index_evolution_cycles_on_started_at"
  end

  create_table "execution_plans", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.bigint "created_by_agent_id"
    t.string "title", null: false
    t.text "original_request", null: false
    t.text "summary"
    t.string "status", default: "planning", null: false
    t.string "complexity", default: "medium"
    t.jsonb "phases", default: []
    t.jsonb "dependencies", default: {}
    t.jsonb "agent_assignments", default: {}
    t.jsonb "validation_results", default: {}
    t.integer "total_steps", default: 0
    t.integer "completed_steps", default: 0
    t.integer "failed_steps", default: 0
    t.integer "current_phase", default: 0
    t.string "current_step_id"
    t.jsonb "step_results", default: {}
    t.jsonb "execution_log", default: []
    t.boolean "requires_approval", default: false
    t.boolean "approved", default: false
    t.datetime "approved_at"
    t.jsonb "user_decisions", default: {}
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "failed_at"
    t.integer "estimated_duration_minutes"
    t.integer "actual_duration_minutes"
    t.text "failure_reason"
    t.jsonb "blocked_by", default: []
    t.integer "retry_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "depends_on_plan_ids", default: [], null: false
    t.jsonb "blocks_plan_ids", default: [], null: false
    t.integer "priority", default: 50, null: false
    t.index ["complexity"], name: "index_execution_plans_on_complexity"
    t.index ["created_by_agent_id"], name: "index_execution_plans_on_created_by_agent_id"
    t.index ["entity_id", "status"], name: "index_execution_plans_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_execution_plans_on_entity_id"
    t.index ["priority"], name: "index_execution_plans_on_priority"
    t.index ["status"], name: "index_execution_plans_on_status"
    t.index ["user_id", "created_at"], name: "index_execution_plans_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_execution_plans_on_user_id"
  end

  create_table "factory_test_criteria", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.string "testable_type", null: false
    t.bigint "testable_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "test_type", default: "semantic", null: false
    t.integer "weight", default: 1
    t.integer "position", default: 0
    t.text "input_prompt"
    t.jsonb "input_data", default: {}
    t.text "expected_output"
    t.jsonb "expected_values", default: {}
    t.jsonb "validation_rules", default: {}
    t.integer "expected_status_code"
    t.jsonb "expected_headers", default: {}
    t.boolean "is_required", default: true
    t.boolean "is_active", default: true
    t.string "category"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_factory_test_criteria_on_category"
    t.index ["entity_id"], name: "index_factory_test_criteria_on_entity_id"
    t.index ["test_type"], name: "index_factory_test_criteria_on_test_type"
    t.index ["testable_type", "testable_id", "is_active"], name: "idx_test_criteria_active"
    t.index ["testable_type", "testable_id"], name: "idx_test_criteria_testable"
    t.index ["user_id"], name: "index_factory_test_criteria_on_user_id"
  end

  create_table "factory_test_runs", force: :cascade do |t|
    t.bigint "factory_test_criteria_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.integer "attempt_number", default: 1, null: false
    t.string "status", default: "pending", null: false
    t.boolean "passed", default: false
    t.text "actual_output"
    t.jsonb "actual_values", default: {}
    t.text "error_message"
    t.text "diff_summary"
    t.float "similarity_score"
    t.text "ai_evaluation"
    t.integer "actual_status_code"
    t.jsonb "actual_headers", default: {}
    t.float "response_time_ms"
    t.integer "duration_ms"
    t.integer "tokens_used"
    t.text "ai_feedback"
    t.text "fix_suggestion"
    t.jsonb "metadata", default: {}
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "factory_test_session_id"
    t.index ["created_at", "status"], name: "idx_test_runs_recent"
    t.index ["entity_id"], name: "index_factory_test_runs_on_entity_id"
    t.index ["factory_test_criteria_id", "attempt_number"], name: "idx_test_runs_attempt"
    t.index ["factory_test_criteria_id"], name: "index_factory_test_runs_on_factory_test_criteria_id"
    t.index ["factory_test_session_id"], name: "index_factory_test_runs_on_factory_test_session_id"
    t.index ["passed"], name: "index_factory_test_runs_on_passed"
    t.index ["status"], name: "index_factory_test_runs_on_status"
    t.index ["user_id"], name: "index_factory_test_runs_on_user_id"
  end

  create_table "factory_test_sessions", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.string "testable_type", null: false
    t.bigint "testable_id", null: false
    t.integer "attempt_number", default: 1, null: false
    t.integer "max_attempts", default: 3
    t.string "status", default: "pending", null: false
    t.integer "total_tests", default: 0
    t.integer "passed_tests", default: 0
    t.integer "failed_tests", default: 0
    t.integer "skipped_tests", default: 0
    t.float "overall_score"
    t.integer "total_duration_ms"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.boolean "delivered", default: false
    t.datetime "delivered_at"
    t.text "delivery_notes"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_factory_test_sessions_on_entity_id"
    t.index ["status"], name: "index_factory_test_sessions_on_status"
    t.index ["testable_type", "testable_id", "attempt_number"], name: "idx_test_sessions_unique_attempt", unique: true
    t.index ["testable_type", "testable_id"], name: "idx_test_sessions_testable"
    t.index ["user_id"], name: "index_factory_test_sessions_on_user_id"
  end

  create_table "global_knowledge_archives", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "source_agent_slug"
    t.string "source_agent_name"
    t.string "source_type"
    t.string "title", null: false
    t.text "content"
    t.string "knowledge_type"
    t.jsonb "applicable_domains", default: []
    t.jsonb "applicable_capabilities", default: []
    t.decimal "utility_score", precision: 5, scale: 4
    t.integer "times_accessed", default: 0
    t.integer "times_applied", default: 0
    t.datetime "last_accessed_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "knowledge_type"], name: "idx_on_entity_id_knowledge_type_54ffe25eb8"
    t.index ["entity_id"], name: "index_global_knowledge_archives_on_entity_id"
    t.index ["source_agent_slug"], name: "index_global_knowledge_archives_on_source_agent_slug"
  end

  create_table "governance_proposals", force: :cascade do |t|
    t.bigint "proposer_id", null: false
    t.bigint "entity_id"
    t.string "title", null: false
    t.text "description", null: false
    t.string "proposal_type", null: false
    t.string "status", default: "discussion", null: false
    t.decimal "staked_amount", precision: 20, scale: 4, default: "0.0"
    t.datetime "voting_started_at"
    t.datetime "finalized_at"
    t.datetime "executed_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "snapshot_at"
    t.decimal "snapshot_total_supply", precision: 24, scale: 8
    t.index ["entity_id"], name: "index_governance_proposals_on_entity_id"
    t.index ["proposal_type"], name: "index_governance_proposals_on_proposal_type"
    t.index ["proposer_id"], name: "index_governance_proposals_on_proposer_id"
    t.index ["snapshot_at"], name: "index_governance_proposals_on_snapshot_at"
    t.index ["status"], name: "index_governance_proposals_on_status"
    t.index ["voting_started_at"], name: "index_governance_proposals_on_voting_started_at"
  end

  create_table "governance_votes", force: :cascade do |t|
    t.bigint "governance_proposal_id", null: false
    t.bigint "user_id", null: false
    t.string "vote", null: false
    t.decimal "voting_power", precision: 20, scale: 4, null: false
    t.datetime "voted_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "stake_at_snapshot", precision: 24, scale: 8
    t.index ["governance_proposal_id", "user_id"], name: "idx_gov_votes_proposal_user", unique: true
    t.index ["governance_proposal_id"], name: "index_governance_votes_on_governance_proposal_id"
    t.index ["user_id"], name: "index_governance_votes_on_user_id"
    t.index ["vote"], name: "index_governance_votes_on_vote"
  end

  create_table "hub_messages", force: :cascade do |t|
    t.bigint "hub_thread_id", null: false
    t.string "sender_type", null: false
    t.bigint "sender_id", null: false
    t.text "content", null: false
    t.string "message_type", default: "text", null: false
    t.bigint "reply_to_id"
    t.boolean "needs_response", default: false
    t.boolean "is_handoff", default: false
    t.string "handoff_status"
    t.bigint "agent_input_request_id"
    t.bigint "agent_plugin_execution_id"
    t.jsonb "attachments", default: []
    t.jsonb "actions", default: []
    t.jsonb "metadata", default: {}
    t.jsonb "reactions", default: {}
    t.boolean "edited", default: false
    t.datetime "edited_at"
    t.boolean "deleted", default: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_input_request_id"], name: "index_hub_messages_on_agent_input_request_id"
    t.index ["agent_plugin_execution_id"], name: "index_hub_messages_on_agent_plugin_execution_id"
    t.index ["hub_thread_id", "created_at"], name: "index_hub_messages_on_hub_thread_id_and_created_at"
    t.index ["hub_thread_id", "needs_response"], name: "idx_hub_messages_pending_responses", where: "(needs_response = true)"
    t.index ["hub_thread_id"], name: "index_hub_messages_on_hub_thread_id"
    t.index ["is_handoff"], name: "index_hub_messages_on_is_handoff"
    t.index ["message_type"], name: "index_hub_messages_on_message_type"
    t.index ["needs_response"], name: "index_hub_messages_on_needs_response"
    t.index ["reply_to_id"], name: "index_hub_messages_on_reply_to_id"
    t.index ["sender_type", "sender_id", "created_at"], name: "idx_hub_messages_by_sender"
    t.index ["sender_type", "sender_id"], name: "index_hub_messages_on_sender"
  end

  create_table "hub_participants", force: :cascade do |t|
    t.bigint "hub_thread_id", null: false
    t.string "participant_type", null: false
    t.bigint "participant_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "joined_at", null: false
    t.datetime "left_at"
    t.datetime "last_read_at"
    t.integer "unread_count", default: 0
    t.boolean "notifications_enabled", default: true
    t.boolean "muted", default: false
    t.datetime "muted_until"
    t.datetime "context_access_from"
    t.jsonb "permissions", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hub_thread_id", "participant_type", "participant_id"], name: "idx_hub_participants_unique", unique: true
    t.index ["hub_thread_id"], name: "index_hub_participants_on_hub_thread_id"
    t.index ["participant_type", "participant_id", "left_at"], name: "idx_hub_participants_active", where: "(left_at IS NULL)"
    t.index ["participant_type", "participant_id"], name: "index_hub_participants_on_participant"
    t.index ["participant_type", "participant_id"], name: "index_hub_participants_on_participant_type_and_participant_id"
    t.index ["unread_count"], name: "index_hub_participants_on_unread_count", where: "(unread_count > 0)"
  end

  create_table "hub_presences", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "participant_type", null: false
    t.bigint "participant_id", null: false
    t.string "status", default: "offline", null: false
    t.string "status_message"
    t.string "status_emoji"
    t.string "current_activity"
    t.bigint "active_execution_id"
    t.float "activity_progress"
    t.datetime "last_seen_at"
    t.datetime "status_changed_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_execution_id"], name: "index_hub_presences_on_active_execution_id"
    t.index ["entity_id", "status"], name: "index_hub_presences_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_hub_presences_on_entity_id"
    t.index ["expires_at"], name: "index_hub_presences_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["participant_type", "participant_id"], name: "index_hub_presences_on_participant"
    t.index ["participant_type", "participant_id"], name: "index_hub_presences_on_participant_type_and_participant_id", unique: true
    t.index ["status"], name: "index_hub_presences_on_status"
  end

  create_table "hub_threads", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "team_channel_id"
    t.string "started_by_type", null: false
    t.bigint "started_by_id", null: false
    t.string "thread_type", default: "channel", null: false
    t.string "subject"
    t.string "status", default: "active", null: false
    t.jsonb "dm_participant_ids", default: []
    t.bigint "agent_plugin_execution_id"
    t.bigint "agent_work_item_id"
    t.jsonb "metadata", default: {}
    t.integer "message_count", default: 0
    t.datetime "last_activity_at"
    t.boolean "pinned", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_execution_id"], name: "index_hub_threads_on_agent_plugin_execution_id"
    t.index ["agent_work_item_id"], name: "index_hub_threads_on_agent_work_item_id"
    t.index ["dm_participant_ids"], name: "index_hub_threads_on_dm_participant_ids", using: :gin
    t.index ["entity_id", "status", "last_activity_at"], name: "idx_hub_threads_active_recent"
    t.index ["entity_id", "thread_type"], name: "index_hub_threads_on_entity_id_and_thread_type"
    t.index ["entity_id"], name: "index_hub_threads_on_entity_id"
    t.index ["last_activity_at"], name: "index_hub_threads_on_last_activity_at"
    t.index ["started_by_type", "started_by_id"], name: "index_hub_threads_on_started_by"
    t.index ["status"], name: "index_hub_threads_on_status"
    t.index ["team_channel_id"], name: "index_hub_threads_on_team_channel_id"
    t.index ["thread_type"], name: "index_hub_threads_on_thread_type"
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
    t.boolean "shared_with_entity", default: false, null: false
    t.index ["entity_id", "shared_with_entity"], name: "index_image_assets_on_entity_id_and_shared_with_entity"
    t.index ["entity_id"], name: "index_image_assets_on_entity_id"
    t.index ["tags"], name: "index_image_assets_on_tags", using: :gin
    t.index ["user_id", "shared_with_entity"], name: "index_image_assets_on_user_id_and_shared_with_entity"
    t.index ["user_id"], name: "index_image_assets_on_user_id"
  end

  create_table "integration_action_executions", force: :cascade do |t|
    t.bigint "integration_action_id", null: false
    t.bigint "connection_id", null: false
    t.bigint "user_id"
    t.bigint "entity_id"
    t.jsonb "inputs", default: {}
    t.jsonb "mapped_params", default: {}
    t.jsonb "raw_response", default: {}
    t.jsonb "normalized_response", default: {}
    t.integer "status", default: 0
    t.text "error_message"
    t.integer "http_status_code"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id"], name: "index_integration_action_executions_on_connection_id"
    t.index ["created_at"], name: "index_integration_action_executions_on_created_at"
    t.index ["entity_id"], name: "index_integration_action_executions_on_entity_id"
    t.index ["integration_action_id"], name: "index_integration_action_executions_on_integration_action_id"
    t.index ["status"], name: "index_integration_action_executions_on_status"
    t.index ["user_id"], name: "index_integration_action_executions_on_user_id"
  end

  create_table "integration_actions", force: :cascade do |t|
    t.bigint "integration_id", null: false
    t.bigint "integration_operation_id", null: false
    t.bigint "entity_id"
    t.bigint "created_by_id"
    t.string "action_name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "category"
    t.jsonb "input_schema", default: []
    t.text "mapping_code"
    t.integer "mapping_code_version", default: 0
    t.datetime "mapping_code_generated_at"
    t.string "mapping_code_generated_by"
    t.text "response_mapping_code"
    t.jsonb "sample_input", default: {}
    t.jsonb "sample_output", default: {}
    t.jsonb "sample_response", default: {}
    t.integer "status", default: 0
    t.integer "usage_count", default: 0
    t.integer "success_count", default: 0
    t.integer "error_count", default: 0
    t.datetime "last_used_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_integration_actions_on_category"
    t.index ["created_by_id"], name: "index_integration_actions_on_created_by_id"
    t.index ["entity_id"], name: "index_integration_actions_on_entity_id"
    t.index ["integration_id", "action_name"], name: "index_integration_actions_on_integration_id_and_action_name", unique: true
    t.index ["integration_id"], name: "index_integration_actions_on_integration_id"
    t.index ["integration_operation_id"], name: "index_integration_actions_on_integration_operation_id"
    t.index ["slug"], name: "index_integration_actions_on_slug", unique: true
    t.index ["status"], name: "index_integration_actions_on_status"
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
    t.text "credentials_backup"
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
    t.bigint "user_id"
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
    t.vector "embedding", limit: 1536
    t.index ["embedding"], name: "index_integration_operations_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["integration_id"], name: "index_integration_operations_on_integration_id"
    t.index ["is_enabled"], name: "index_integration_operations_on_is_enabled"
    t.index ["operation_id"], name: "index_integration_operations_on_operation_id"
  end

  create_table "integration_staging_records", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "connection_id", null: false
    t.bigint "scheduled_agent_task_id"
    t.string "external_id", null: false
    t.string "external_type", null: false
    t.string "target_type", null: false
    t.jsonb "staged_data", null: false
    t.jsonb "field_mappings", default: {}
    t.jsonb "validation_results", default: {}
    t.string "status", default: "pending"
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.text "review_notes"
    t.bigint "created_record_id"
    t.datetime "imported_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "external_type", "external_id"], name: "idx_staging_external"
    t.index ["connection_id"], name: "index_integration_staging_records_on_connection_id"
    t.index ["entity_id", "status"], name: "index_integration_staging_records_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_integration_staging_records_on_entity_id"
    t.index ["reviewed_by_id"], name: "index_integration_staging_records_on_reviewed_by_id"
    t.index ["scheduled_agent_task_id"], name: "index_integration_staging_records_on_scheduled_agent_task_id"
  end

  create_table "integration_sync_configs", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "connection_id", null: false
    t.string "resource_type", null: false
    t.string "target_type", null: false
    t.boolean "enabled", default: true
    t.string "sync_direction", default: "inbound"
    t.string "sync_mode", default: "incremental"
    t.string "conflict_resolution", default: "external_wins"
    t.string "schedule_type"
    t.string "cron_expression"
    t.bigint "scheduled_agent_task_id"
    t.jsonb "field_mappings", null: false
    t.jsonb "default_values", default: {}
    t.jsonb "transformations", default: {}
    t.jsonb "filter_conditions", default: {}
    t.boolean "requires_approval", default: false
    t.integer "approval_threshold"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "transform_code"
    t.integer "transform_code_version", default: 1
    t.datetime "transform_code_generated_at"
    t.string "transform_code_generated_by"
    t.bigint "post_sync_workflow_id"
    t.jsonb "sample_input", default: {}
    t.jsonb "sample_output", default: {}
    t.index ["connection_id", "resource_type", "target_type"], name: "idx_sync_config_unique", unique: true
    t.index ["connection_id"], name: "index_integration_sync_configs_on_connection_id"
    t.index ["entity_id"], name: "index_integration_sync_configs_on_entity_id"
    t.index ["post_sync_workflow_id"], name: "index_integration_sync_configs_on_post_sync_workflow_id"
    t.index ["scheduled_agent_task_id"], name: "index_integration_sync_configs_on_scheduled_agent_task_id"
  end

  create_table "integration_sync_cursors", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "connection_id", null: false
    t.string "resource_type", null: false
    t.string "cursor_type", default: "timestamp"
    t.datetime "cursor_timestamp"
    t.integer "cursor_offset"
    t.string "cursor_token"
    t.jsonb "cursor_data", default: {}
    t.datetime "last_full_sync_at"
    t.datetime "last_incremental_sync_at"
    t.integer "total_records_synced", default: 0
    t.integer "records_synced_in_last_run", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "resource_type"], name: "idx_on_connection_id_resource_type_104c6c4de5", unique: true
    t.index ["connection_id"], name: "index_integration_sync_cursors_on_connection_id"
    t.index ["entity_id"], name: "index_integration_sync_cursors_on_entity_id"
  end

  create_table "integration_sync_records", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "connection_id", null: false
    t.string "external_id", null: false
    t.string "external_type", null: false
    t.jsonb "external_data", default: {}
    t.string "external_hash"
    t.string "internal_type", null: false
    t.bigint "internal_id"
    t.string "sync_status", default: "synced"
    t.string "sync_direction", default: "inbound"
    t.datetime "last_synced_at"
    t.datetime "last_external_update_at"
    t.integer "sync_count", default: 0
    t.text "last_error"
    t.datetime "last_error_at"
    t.integer "error_count", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "external_type", "external_id"], name: "idx_sync_records_unique", unique: true
    t.index ["connection_id"], name: "index_integration_sync_records_on_connection_id"
    t.index ["entity_id", "internal_type", "internal_id"], name: "idx_sync_records_internal"
    t.index ["entity_id"], name: "index_integration_sync_records_on_entity_id"
    t.index ["last_synced_at"], name: "index_integration_sync_records_on_last_synced_at"
    t.index ["sync_status"], name: "index_integration_sync_records_on_sync_status"
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
    t.vector "embedding", limit: 1536
    t.bigint "entity_id"
    t.boolean "is_public", default: false, null: false
    t.bigint "created_by_id"
    t.string "publish_status", default: "private", null: false
    t.datetime "published_at"
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.text "review_notes"
    t.integer "usage_count", default: 0, null: false
    t.index ["created_by_id"], name: "index_integrations_on_created_by_id"
    t.index ["embedding"], name: "index_integrations_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["entity_id"], name: "index_integrations_on_entity_id"
    t.index ["is_public", "publish_status"], name: "idx_integrations_public_status"
    t.index ["is_public"], name: "index_integrations_on_is_public"
    t.index ["name"], name: "index_integrations_on_name", unique: true
    t.index ["publish_status"], name: "index_integrations_on_publish_status"
    t.index ["reviewed_by_id"], name: "index_integrations_on_reviewed_by_id"
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
    t.jsonb "custom_fields", default: {}
    t.string "subdomain"
    t.bigint "custom_domain_id"
    t.index ["campaign_id"], name: "index_landing_pages_on_campaign_id"
    t.index ["custom_domain_id"], name: "index_landing_pages_on_custom_domain_id"
    t.index ["custom_fields"], name: "index_landing_pages_on_custom_fields", using: :gin
    t.index ["entity_id", "status"], name: "index_landing_pages_on_entity_status"
    t.index ["entity_id"], name: "index_landing_pages_on_entity_id"
    t.index ["metadata"], name: "index_landing_pages_on_metadata", using: :gin
    t.index ["slug"], name: "index_landing_pages_on_slug", unique: true
    t.index ["subdomain"], name: "index_landing_pages_on_subdomain", unique: true, where: "(subdomain IS NOT NULL)"
    t.index ["user_id"], name: "index_landing_pages_on_user_id"
  end

  create_table "loadout_metrics", force: :cascade do |t|
    t.string "loadout_slug", null: false
    t.bigint "entity_id", null: false
    t.bigint "user_id"
    t.string "canvas_context"
    t.string "event_type", null: false
    t.jsonb "details", default: {}
    t.float "quality_score"
    t.integer "response_time_ms"
    t.string "session_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["canvas_context"], name: "index_loadout_metrics_on_canvas_context"
    t.index ["entity_id", "event_type", "created_at"], name: "idx_on_entity_id_event_type_created_at_9a7db00825"
    t.index ["entity_id", "loadout_slug"], name: "index_loadout_metrics_on_entity_id_and_loadout_slug"
    t.index ["entity_id"], name: "index_loadout_metrics_on_entity_id"
    t.index ["loadout_slug", "created_at"], name: "index_loadout_metrics_on_loadout_slug_and_created_at"
    t.index ["user_id"], name: "index_loadout_metrics_on_user_id"
  end

  create_table "loadout_versions", force: :cascade do |t|
    t.bigint "agent_plugin_id", null: false
    t.integer "version_number", null: false
    t.text "system_prompt_snapshot"
    t.jsonb "tools_snapshot", default: []
    t.string "change_reason"
    t.string "changed_by_type"
    t.bigint "changed_by_id"
    t.jsonb "performance_before", default: {}
    t.jsonb "performance_after", default: {}
    t.boolean "is_active", default: false
    t.datetime "activated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_id", "is_active"], name: "index_loadout_versions_on_agent_plugin_id_and_is_active"
    t.index ["agent_plugin_id", "version_number"], name: "index_loadout_versions_on_agent_plugin_id_and_version_number", unique: true
    t.index ["agent_plugin_id"], name: "index_loadout_versions_on_agent_plugin_id"
    t.index ["changed_by_type", "changed_by_id"], name: "index_loadout_versions_on_changed_by"
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

  create_table "memory_bookmarks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "scout_message_id"
    t.string "title", null: false
    t.text "description"
    t.text "context_snapshot"
    t.string "bookmark_type", default: "saved"
    t.boolean "shareable", default: false
    t.string "share_token"
    t.datetime "shared_at"
    t.integer "view_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "content_type", default: "conversation"
    t.jsonb "content", default: {}
    t.jsonb "tags", default: []
    t.string "source"
    t.index ["bookmark_type"], name: "index_memory_bookmarks_on_bookmark_type"
    t.index ["entity_id"], name: "index_memory_bookmarks_on_entity_id"
    t.index ["scout_message_id"], name: "index_memory_bookmarks_on_scout_message_id"
    t.index ["share_token"], name: "index_memory_bookmarks_on_share_token", unique: true
    t.index ["user_id", "entity_id", "content_type"], name: "idx_on_user_id_entity_id_content_type_3cf390a3f8"
    t.index ["user_id", "entity_id"], name: "index_memory_bookmarks_on_user_id_and_entity_id"
    t.index ["user_id"], name: "index_memory_bookmarks_on_user_id"
  end

  create_table "memory_preferences", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.integer "retention_days", default: 90
    t.boolean "auto_summarize", default: true
    t.integer "summarize_after_messages", default: 50
    t.boolean "memory_enabled", default: true
    t.boolean "learn_preferences", default: true
    t.boolean "learn_business_facts", default: true
    t.boolean "cross_session_memory", default: true
    t.text "forget_topics"
    t.boolean "forget_after_session", default: false
    t.boolean "allow_sharing", default: true
    t.boolean "default_shareable", default: false
    t.boolean "notify_on_summary", default: false
    t.boolean "notify_on_learn", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_memory_preferences_on_entity_id"
    t.index ["user_id", "entity_id"], name: "index_memory_preferences_on_user_id_and_entity_id", unique: true
    t.index ["user_id"], name: "index_memory_preferences_on_user_id"
  end

  create_table "memory_segments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "segment_type", null: false
    t.datetime "period_start"
    t.datetime "period_end"
    t.integer "message_count", default: 0
    t.text "summary", null: false
    t.text "key_topics"
    t.text "key_decisions"
    t.text "action_items"
    t.text "context_snapshot"
    t.string "embedding_id"
    t.float "relevance_decay", default: 1.0
    t.integer "retrieval_count", default: 0
    t.datetime "last_retrieved_at"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_memory_segments_on_entity_id"
    t.index ["user_id", "entity_id", "active"], name: "index_memory_segments_on_user_id_and_entity_id_and_active"
    t.index ["user_id", "entity_id", "period_start"], name: "idx_on_user_id_entity_id_period_start_6661d39b9c"
    t.index ["user_id", "entity_id", "segment_type"], name: "idx_on_user_id_entity_id_segment_type_5c4e869f43"
    t.index ["user_id"], name: "index_memory_segments_on_user_id"
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

  create_table "model_quality_logs", force: :cascade do |t|
    t.string "model_id", null: false
    t.string "event_type", null: false
    t.string "tool_name"
    t.text "details"
    t.bigint "entity_id"
    t.bigint "user_id"
    t.string "session_id"
    t.float "latency_ms"
    t.boolean "fallback_used", default: false
    t.string "fallback_model_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_model_quality_logs_on_created_at"
    t.index ["entity_id"], name: "index_model_quality_logs_on_entity_id"
    t.index ["event_type"], name: "index_model_quality_logs_on_event_type"
    t.index ["model_id", "event_type"], name: "index_model_quality_logs_on_model_id_and_event_type"
    t.index ["model_id", "tool_name"], name: "index_model_quality_logs_on_model_id_and_tool_name"
    t.index ["model_id"], name: "index_model_quality_logs_on_model_id"
    t.index ["user_id"], name: "index_model_quality_logs_on_user_id"
  end

  create_table "module_actions", force: :cascade do |t|
    t.bigint "app_module_id", null: false
    t.bigint "entity_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "icon", default: "play"
    t.string "style", default: "primary"
    t.string "location", default: "toolbar"
    t.string "target_field"
    t.integer "position", default: 0
    t.jsonb "show_when", default: {}
    t.jsonb "requires_role", default: {}
    t.string "behavior_type", null: false
    t.jsonb "behavior_config", default: {}
    t.boolean "active", default: true
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_module_actions_on_active"
    t.index ["app_module_id", "slug"], name: "index_module_actions_on_app_module_id_and_slug", unique: true
    t.index ["app_module_id"], name: "index_module_actions_on_app_module_id"
    t.index ["entity_id"], name: "index_module_actions_on_entity_id"
    t.index ["location"], name: "index_module_actions_on_location"
  end

  create_table "module_canvases", force: :cascade do |t|
    t.bigint "app_module_id", null: false
    t.bigint "entity_id", null: false
    t.string "slug", null: false
    t.string "name", null: false
    t.text "description"
    t.string "canvas_type", default: "module"
    t.string "ui_mode", default: "simple"
    t.text "html_content"
    t.text "js_content"
    t.text "css_content"
    t.jsonb "data_sources", default: []
    t.jsonb "actions", default: []
    t.jsonb "layout_config", default: {}
    t.integer "version", default: 1
    t.text "previous_versions"
    t.boolean "is_default", default: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "layout", default: "default"
    t.jsonb "sections", default: []
    t.jsonb "tabs", default: []
    t.jsonb "filters", default: []
    t.jsonb "sorting", default: []
    t.jsonb "columns", default: []
    t.jsonb "card_config", default: {}
    t.boolean "is_public", default: false, null: false
    t.string "public_slug"
    t.datetime "published_at"
    t.integer "view_count", default: 0, null: false
    t.bigint "custom_domain_id"
    t.index ["app_module_id", "slug"], name: "index_module_canvases_on_app_module_id_and_slug", unique: true
    t.index ["app_module_id"], name: "index_module_canvases_on_app_module_id"
    t.index ["canvas_type"], name: "index_module_canvases_on_canvas_type"
    t.index ["custom_domain_id"], name: "index_module_canvases_on_custom_domain_id"
    t.index ["entity_id", "slug"], name: "index_module_canvases_on_entity_id_and_slug"
    t.index ["entity_id"], name: "index_module_canvases_on_entity_id"
    t.index ["is_public"], name: "index_module_canvases_on_is_public"
    t.index ["layout"], name: "index_module_canvases_on_layout"
    t.index ["public_slug"], name: "index_module_canvases_on_public_slug", unique: true, where: "(public_slug IS NOT NULL)"
    t.index ["ui_mode"], name: "index_module_canvases_on_ui_mode"
  end

  create_table "module_codes", force: :cascade do |t|
    t.bigint "app_module_id", null: false
    t.bigint "entity_id", null: false
    t.string "name", null: false
    t.string "code_type", null: false
    t.text "content", null: false
    t.jsonb "schema_definition", default: {}
    t.integer "version", default: 1
    t.text "previous_content"
    t.string "status", default: "generated"
    t.text "validation_errors"
    t.datetime "deployed_at"
    t.boolean "loaded", default: false
    t.datetime "last_loaded_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_module_id", "name", "code_type"], name: "index_module_codes_on_app_module_id_and_name_and_code_type", unique: true
    t.index ["app_module_id"], name: "index_module_codes_on_app_module_id"
    t.index ["code_type"], name: "index_module_codes_on_code_type"
    t.index ["entity_id"], name: "index_module_codes_on_entity_id"
    t.index ["loaded"], name: "index_module_codes_on_loaded"
    t.index ["status"], name: "index_module_codes_on_status"
  end

  create_table "module_design_sessions", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "app_module_id"
    t.string "status", default: "gathering_requirements"
    t.string "module_name"
    t.text "user_description"
    t.jsonb "proposed_schema", default: {}
    t.jsonb "user_feedback", default: []
    t.jsonb "final_schema", default: {}
    t.jsonb "conversation_context", default: {}
    t.integer "iteration_count", default: 0
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_module_id"], name: "index_module_design_sessions_on_app_module_id"
    t.index ["entity_id", "status"], name: "index_module_design_sessions_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_module_design_sessions_on_entity_id"
    t.index ["status"], name: "index_module_design_sessions_on_status"
  end

  create_table "module_integrations", force: :cascade do |t|
    t.bigint "app_module_id", null: false
    t.bigint "integration_id", null: false
    t.string "purpose", null: false
    t.string "status", default: "required"
    t.text "description"
    t.jsonb "config", default: {}
    t.boolean "is_critical", default: false
    t.datetime "connected_at"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_module_id", "integration_id"], name: "index_module_integrations_on_app_module_id_and_integration_id", unique: true
    t.index ["app_module_id"], name: "index_module_integrations_on_app_module_id"
    t.index ["integration_id"], name: "index_module_integrations_on_integration_id"
    t.index ["is_critical"], name: "index_module_integrations_on_is_critical"
    t.index ["status"], name: "index_module_integrations_on_status"
  end

  create_table "module_webhooks", force: :cascade do |t|
    t.bigint "app_module_id", null: false
    t.bigint "entity_id", null: false
    t.string "event_name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "auth_type", default: "token"
    t.string "auth_token"
    t.string "signing_secret"
    t.jsonb "ip_allowlist", default: []
    t.jsonb "payload_schema", default: {}
    t.jsonb "field_mappings", default: {}
    t.string "target_type", null: false
    t.bigint "target_id"
    t.string "target_tool"
    t.jsonb "context_template", default: {}
    t.integer "rate_limit_per_minute", default: 60
    t.integer "rate_limit_per_hour", default: 1000
    t.string "status", default: "active"
    t.integer "call_count", default: 0
    t.datetime "last_called_at"
    t.datetime "last_success_at"
    t.datetime "last_failure_at"
    t.text "last_failure_reason"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_module_id", "event_name"], name: "index_module_webhooks_on_app_module_id_and_event_name"
    t.index ["app_module_id"], name: "index_module_webhooks_on_app_module_id"
    t.index ["entity_id", "slug"], name: "index_module_webhooks_on_entity_id_and_slug", unique: true
    t.index ["entity_id"], name: "index_module_webhooks_on_entity_id"
    t.index ["status"], name: "index_module_webhooks_on_status"
    t.index ["target_type"], name: "index_module_webhooks_on_target_type"
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
    t.jsonb "required_params", default: [], null: false
    t.index ["callback_params"], name: "index_oauth_configurations_on_callback_params", using: :gin
    t.index ["integration_id"], name: "index_oauth_configurations_on_integration_id", unique: true
    t.index ["required_params"], name: "index_oauth_configurations_on_required_params", using: :gin
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

  create_table "opportunities", force: :cascade do |t|
    t.bigint "contact_id", null: false
    t.bigint "user_id"
    t.bigint "entity_id", null: false
    t.bigint "assigned_agent_id"
    t.string "name", null: false
    t.string "stage", default: "lead", null: false
    t.decimal "value", precision: 12, scale: 2
    t.integer "probability", default: 10
    t.date "expected_close_date"
    t.date "actual_close_date"
    t.string "lost_reason"
    t.string "source"
    t.text "notes"
    t.jsonb "metadata", default: {}
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "custom_fields", default: {}
    t.index ["assigned_agent_id", "stage"], name: "index_opportunities_on_assigned_agent_id_and_stage"
    t.index ["assigned_agent_id"], name: "index_opportunities_on_assigned_agent_id"
    t.index ["contact_id"], name: "index_opportunities_on_contact_id"
    t.index ["custom_fields"], name: "index_opportunities_on_custom_fields", using: :gin
    t.index ["entity_id", "stage"], name: "index_opportunities_on_entity_id_and_stage"
    t.index ["entity_id"], name: "index_opportunities_on_entity_id"
    t.index ["expected_close_date"], name: "index_opportunities_on_expected_close_date"
    t.index ["source"], name: "index_opportunities_on_source"
    t.index ["stage"], name: "index_opportunities_on_stage"
    t.index ["user_id", "stage"], name: "index_opportunities_on_user_id_and_stage"
    t.index ["user_id"], name: "index_opportunities_on_user_id"
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

  create_table "plan_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "category"
    t.jsonb "trigger_patterns", default: []
    t.jsonb "keywords", default: []
    t.jsonb "phases", default: []
    t.string "complexity", default: "medium"
    t.integer "estimated_duration_minutes"
    t.jsonb "common_issues", default: []
    t.jsonb "requirements", default: []
    t.integer "times_used", default: 0
    t.integer "success_count", default: 0
    t.integer "failure_count", default: 0
    t.float "average_duration_minutes"
    t.float "success_rate"
    t.string "status", default: "active"
    t.string "author", default: "system"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_plan_templates_on_category"
    t.index ["slug"], name: "index_plan_templates_on_slug", unique: true
    t.index ["status"], name: "index_plan_templates_on_status"
    t.index ["success_rate"], name: "index_plan_templates_on_success_rate"
    t.index ["times_used"], name: "index_plan_templates_on_times_used"
  end

  create_table "platform_anomalies", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "platform_perception_id"
    t.string "anomaly_type", null: false
    t.string "severity", null: false
    t.string "status", default: "detected"
    t.string "target_type"
    t.bigint "target_id"
    t.string "title", null: false
    t.text "description"
    t.jsonb "details", default: {}
    t.jsonb "triggering_metrics", default: {}
    t.decimal "deviation_percent", precision: 8, scale: 4
    t.jsonb "suggested_actions", default: []
    t.jsonb "resolution_actions", default: []
    t.datetime "resolved_at"
    t.text "resolution_notes"
    t.bigint "triggered_goal_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "severity"], name: "index_platform_anomalies_on_entity_id_and_severity"
    t.index ["entity_id", "status"], name: "index_platform_anomalies_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_platform_anomalies_on_entity_id"
    t.index ["platform_perception_id"], name: "index_platform_anomalies_on_platform_perception_id"
    t.index ["target_type", "target_id"], name: "index_platform_anomalies_on_target_type_and_target_id"
    t.index ["triggered_goal_id"], name: "index_platform_anomalies_on_triggered_goal_id"
  end

  create_table "platform_evolution_tickets", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "ticket_type", null: false
    t.string "status", default: "open", null: false
    t.string "priority", default: "medium", null: false
    t.string "title", null: false
    t.text "description"
    t.jsonb "evidence", default: {}
    t.jsonb "proposed_solution", default: {}
    t.jsonb "implementation_details", default: {}
    t.string "source"
    t.string "target_area"
    t.string "target_slug"
    t.string "assigned_to_type"
    t.bigint "assigned_to_id"
    t.string "created_by_type"
    t.bigint "created_by_id"
    t.string "completed_by_type"
    t.bigint "completed_by_id"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "estimated_hours"
    t.integer "actual_hours"
    t.float "impact_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_to_type", "assigned_to_id"], name: "index_platform_evolution_tickets_on_assigned_to"
    t.index ["completed_by_type", "completed_by_id"], name: "index_platform_evolution_tickets_on_completed_by"
    t.index ["created_by_type", "created_by_id"], name: "index_platform_evolution_tickets_on_created_by"
    t.index ["entity_id", "status"], name: "index_platform_evolution_tickets_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_platform_evolution_tickets_on_entity_id"
    t.index ["status", "priority"], name: "index_platform_evolution_tickets_on_status_and_priority"
    t.index ["target_area", "target_slug"], name: "idx_on_target_area_target_slug_fcc1d8f5cf"
    t.index ["ticket_type", "status"], name: "index_platform_evolution_tickets_on_ticket_type_and_status"
  end

  create_table "platform_perceptions", force: :cascade do |t|
    t.bigint "entity_id"
    t.datetime "perceived_at", null: false
    t.string "perception_type", null: false
    t.decimal "overall_health_score", precision: 5, scale: 4
    t.jsonb "health_breakdown", default: {}
    t.integer "active_agents", default: 0
    t.integer "tasks_completed_24h", default: 0
    t.integer "tasks_failed_24h", default: 0
    t.decimal "success_rate_24h", precision: 5, scale: 4
    t.jsonb "anomalies", default: []
    t.integer "anomaly_count", default: 0
    t.integer "critical_anomalies", default: 0
    t.jsonb "opportunities", default: []
    t.jsonb "threats", default: []
    t.jsonb "autonomous_actions_triggered", default: []
    t.integer "actions_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "metrics_snapshot", default: {}
    t.index ["entity_id", "perceived_at"], name: "index_platform_perceptions_on_entity_id_and_perceived_at"
    t.index ["entity_id"], name: "index_platform_perceptions_on_entity_id"
    t.index ["perceived_at"], name: "index_platform_perceptions_on_perceived_at"
    t.index ["perception_type"], name: "index_platform_perceptions_on_perception_type"
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

  create_table "pull_request_submissions", force: :cascade do |t|
    t.bigint "code_fix_id", null: false
    t.bigint "support_ticket_id", null: false
    t.bigint "entity_id", null: false
    t.string "pr_number"
    t.string "pr_url"
    t.string "pr_title"
    t.text "pr_body"
    t.string "source_branch"
    t.string "target_branch", default: "main"
    t.string "status", default: "pending", null: false
    t.jsonb "reviewers", default: []
    t.jsonb "review_comments", default: []
    t.integer "review_count", default: 0
    t.integer "approval_count", default: 0
    t.string "ci_status"
    t.jsonb "ci_results", default: {}
    t.datetime "merged_at"
    t.string "merged_by"
    t.string "merge_commit_sha"
    t.datetime "closed_at"
    t.string "closed_by"
    t.text "close_reason"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code_fix_id", "status"], name: "index_pull_request_submissions_on_code_fix_id_and_status"
    t.index ["code_fix_id"], name: "index_pull_request_submissions_on_code_fix_id"
    t.index ["entity_id"], name: "index_pull_request_submissions_on_entity_id"
    t.index ["pr_number"], name: "index_pull_request_submissions_on_pr_number"
    t.index ["status"], name: "index_pull_request_submissions_on_status"
    t.index ["support_ticket_id"], name: "index_pull_request_submissions_on_support_ticket_id"
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
    t.bigint "agent_plugin_id"
    t.index ["agent_plugin_id", "status"], name: "index_rag_stores_on_agent_plugin_id_and_status", where: "(agent_plugin_id IS NOT NULL)"
    t.index ["agent_plugin_id"], name: "index_rag_stores_on_agent_plugin_id"
    t.index ["app_name"], name: "index_rag_stores_on_app_name"
    t.index ["entity_id", "status"], name: "index_rag_stores_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_rag_stores_on_entity_id"
    t.index ["last_accessed_at"], name: "index_rag_stores_on_last_accessed_at"
    t.index ["pinecone_index", "pinecone_namespace"], name: "index_rag_stores_on_pinecone_index_and_pinecone_namespace", unique: true
    t.index ["status"], name: "index_rag_stores_on_status"
    t.index ["store_type"], name: "index_rag_stores_on_store_type"
    t.index ["user_id"], name: "index_rag_stores_on_user_id"
    t.check_constraint "store_type::text = 'system'::text AND entity_id IS NULL OR store_type::text = 'entity'::text AND entity_id IS NOT NULL OR store_type::text = 'agent'::text", name: "check_entity_required_for_store_type"
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

  create_table "revenue_distributions", force: :cascade do |t|
    t.string "period", null: false
    t.decimal "gross_revenue", precision: 15, scale: 2, null: false
    t.decimal "holder_pool", precision: 15, scale: 2, null: false
    t.decimal "usdc_distributed", precision: 15, scale: 2, default: "0.0"
    t.decimal "buyback_burned", precision: 20, scale: 4, default: "0.0"
    t.integer "recipients_count", default: 0
    t.datetime "distributed_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["distributed_at"], name: "index_revenue_distributions_on_distributed_at"
    t.index ["period"], name: "index_revenue_distributions_on_period", unique: true
  end

  create_table "revenue_payments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "revenue_distribution_id"
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.string "currency", default: "USDC", null: false
    t.string "period", null: false
    t.string "status", default: "pending", null: false
    t.string "payment_method"
    t.string "transaction_signature"
    t.datetime "paid_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["period"], name: "index_revenue_payments_on_period"
    t.index ["revenue_distribution_id"], name: "index_revenue_payments_on_revenue_distribution_id"
    t.index ["status"], name: "index_revenue_payments_on_status"
    t.index ["user_id", "period"], name: "index_revenue_payments_on_user_id_and_period", unique: true
    t.index ["user_id"], name: "index_revenue_payments_on_user_id"
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

  create_table "saved_visualizations", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.bigint "scout_message_id"
    t.bigint "scout_conversation_id"
    t.bigint "agent_work_item_id"
    t.bigint "agent_plugin_execution_id"
    t.string "name", null: false
    t.text "description"
    t.string "visualization_type", null: false
    t.string "source_type", null: false
    t.string "source_session_id"
    t.integer "source_message_index"
    t.text "html_content_cache"
    t.jsonb "canvas_data_cache", default: {}
    t.datetime "cache_expires_at"
    t.text "original_prompt"
    t.jsonb "generation_config", default: {}
    t.boolean "auto_refresh", default: false
    t.string "refresh_schedule"
    t.datetime "last_refreshed_at"
    t.datetime "next_refresh_at"
    t.string "category"
    t.jsonb "tags", default: []
    t.boolean "pinned", default: false
    t.boolean "shared", default: false
    t.boolean "archived", default: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "dynamic_content_id"
    t.index ["agent_plugin_execution_id"], name: "index_saved_visualizations_on_agent_plugin_execution_id"
    t.index ["agent_work_item_id"], name: "index_saved_visualizations_on_agent_work_item_id"
    t.index ["archived"], name: "index_saved_visualizations_on_archived"
    t.index ["auto_refresh"], name: "index_saved_visualizations_on_auto_refresh"
    t.index ["category"], name: "index_saved_visualizations_on_category"
    t.index ["dynamic_content_id"], name: "index_saved_visualizations_on_dynamic_content_id"
    t.index ["entity_id", "shared"], name: "index_saved_visualizations_on_entity_id_and_shared"
    t.index ["entity_id", "user_id"], name: "index_saved_visualizations_on_entity_id_and_user_id"
    t.index ["entity_id"], name: "index_saved_visualizations_on_entity_id"
    t.index ["pinned"], name: "index_saved_visualizations_on_pinned"
    t.index ["scout_conversation_id"], name: "index_saved_visualizations_on_scout_conversation_id"
    t.index ["scout_message_id"], name: "index_saved_visualizations_on_scout_message_id"
    t.index ["shared"], name: "index_saved_visualizations_on_shared"
    t.index ["source_session_id"], name: "index_saved_visualizations_on_source_session_id"
    t.index ["source_type"], name: "index_saved_visualizations_on_source_type"
    t.index ["user_id"], name: "index_saved_visualizations_on_user_id"
    t.index ["visualization_type"], name: "index_saved_visualizations_on_visualization_type"
  end

  create_table "scheduled_agent_tasks", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.bigint "agent_plugin_id"
    t.string "name", null: false
    t.text "description"
    t.string "task_type", null: false
    t.text "prompt", null: false
    t.string "schedule_type", null: false
    t.string "cron_expression"
    t.time "run_at_time"
    t.integer "run_on_day"
    t.string "timezone", default: "UTC"
    t.datetime "next_run_at"
    t.datetime "last_run_at"
    t.integer "run_count", default: 0
    t.integer "failure_count", default: 0
    t.integer "consecutive_failures", default: 0
    t.jsonb "input_context", default: {}
    t.jsonb "output_config", default: {}
    t.jsonb "metadata", default: {}
    t.string "status", default: "active"
    t.boolean "enabled", default: true
    t.integer "max_runs"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "app_module_id"
    t.index ["agent_plugin_id"], name: "index_scheduled_agent_tasks_on_agent_plugin_id"
    t.index ["app_module_id"], name: "index_scheduled_agent_tasks_on_app_module_id"
    t.index ["enabled"], name: "index_scheduled_agent_tasks_on_enabled"
    t.index ["entity_id", "next_run_at"], name: "index_scheduled_agent_tasks_on_entity_id_and_next_run_at"
    t.index ["entity_id", "status"], name: "index_scheduled_agent_tasks_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_scheduled_agent_tasks_on_entity_id"
    t.index ["next_run_at"], name: "index_scheduled_agent_tasks_on_next_run_at"
    t.index ["status"], name: "index_scheduled_agent_tasks_on_status"
    t.index ["task_type"], name: "index_scheduled_agent_tasks_on_task_type"
    t.index ["user_id"], name: "index_scheduled_agent_tasks_on_user_id"
  end

  create_table "scheduled_task_runs", force: :cascade do |t|
    t.bigint "scheduled_agent_task_id", null: false
    t.bigint "agent_plugin_execution_id"
    t.bigint "user_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "duration_ms"
    t.text "result_summary"
    t.jsonb "result_data", default: {}
    t.text "error_message"
    t.boolean "notification_sent", default: false
    t.datetime "notification_sent_at"
    t.string "notification_method"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_plugin_execution_id"], name: "index_scheduled_task_runs_on_agent_plugin_execution_id"
    t.index ["scheduled_agent_task_id", "status"], name: "idx_on_scheduled_agent_task_id_status_30c896b176"
    t.index ["scheduled_agent_task_id"], name: "index_scheduled_task_runs_on_scheduled_agent_task_id"
    t.index ["started_at"], name: "index_scheduled_task_runs_on_started_at"
    t.index ["status"], name: "index_scheduled_task_runs_on_status"
    t.index ["user_id"], name: "index_scheduled_task_runs_on_user_id"
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

  create_table "scout_learnings", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "learning_type", null: false
    t.string "context"
    t.text "learning", null: false
    t.text "example"
    t.float "success_rate", default: 0.0
    t.integer "apply_count", default: 0
    t.integer "success_count", default: 0
    t.string "source"
    t.float "confidence", default: 0.5
    t.boolean "active", default: true
    t.datetime "last_applied_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["confidence"], name: "index_scout_learnings_on_confidence"
    t.index ["entity_id", "context"], name: "index_scout_learnings_on_entity_id_and_context"
    t.index ["entity_id", "learning_type"], name: "index_scout_learnings_on_entity_id_and_learning_type"
    t.index ["entity_id"], name: "index_scout_learnings_on_entity_id"
    t.index ["success_rate"], name: "index_scout_learnings_on_success_rate"
  end

  create_table "scout_loadout_configurations", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.jsonb "tool_allowlist", default: []
    t.jsonb "canvas_allowlist", default: ["*"]
    t.jsonb "budgets", default: {}
    t.boolean "use_tiered_discovery", default: false
    t.integer "max_discovered_tools", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_scout_loadout_configurations_on_entity_id", unique: true
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
    t.string "memory_layer", default: "l1"
    t.boolean "summarized", default: false
    t.bigint "summary_id"
    t.float "importance_score", default: 0.5
    t.text "topics"
    t.string "embedding_id"
    t.index "session_id, role, md5(content), created_at", name: "index_scout_messages_duplicate_detection"
    t.index ["entity_id"], name: "index_scout_messages_on_entity_id"
    t.index ["importance_score"], name: "index_scout_messages_on_importance_score"
    t.index ["session_id", "created_at"], name: "index_scout_messages_on_session_and_created"
    t.index ["session_id", "created_at"], name: "index_scout_messages_on_session_id_and_created_at"
    t.index ["session_id", "role"], name: "index_scout_messages_on_session_and_role"
    t.index ["user_id", "entity_id", "created_at"], name: "index_scout_messages_on_user_id_and_entity_id_and_created_at"
    t.index ["user_id", "entity_id", "memory_layer"], name: "index_scout_messages_on_user_id_and_entity_id_and_memory_layer"
    t.index ["user_id", "entity_id", "summarized"], name: "index_scout_messages_on_user_id_and_entity_id_and_summarized"
    t.index ["user_id", "session_id"], name: "index_scout_messages_on_user_and_session"
    t.index ["user_id"], name: "index_scout_messages_on_user_id"
  end

  create_table "scout_personalities", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.integer "formality", default: 5
    t.integer "verbosity", default: 4
    t.integer "proactivity", default: 7
    t.integer "humor", default: 3
    t.integer "technicality", default: 5
    t.string "greeting_style", default: "warm"
    t.string "response_length", default: "concise"
    t.boolean "use_emojis", default: true
    t.boolean "show_thinking", default: false
    t.string "name", default: "Scout"
    t.text "custom_instructions"
    t.text "phrases"
    t.text "avoid_phrases"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_scout_personalities_on_entity_id", unique: true
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

  create_table "space_definitions", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.text "description"
    t.string "icon"
    t.text "context_prompt"
    t.jsonb "default_tool_loadout", default: []
    t.jsonb "default_menu_items", default: []
    t.integer "display_order", default: 0
    t.boolean "enabled", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_space_definitions_on_slug", unique: true
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

  create_table "support_tickets", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id"
    t.bigint "scout_conversation_id"
    t.string "ticket_number", null: false
    t.string "title", null: false
    t.text "description"
    t.string "source", default: "user_reported", null: false
    t.string "status", default: "open", null: false
    t.string "priority", default: "medium", null: false
    t.string "category"
    t.string "error_class"
    t.string "error_message"
    t.text "stack_trace"
    t.string "error_signature"
    t.string "error_file"
    t.integer "error_line"
    t.jsonb "error_context", default: {}
    t.string "assigned_to_type"
    t.string "assigned_to_id"
    t.text "resolution_notes"
    t.datetime "resolved_at"
    t.string "resolved_by"
    t.integer "time_to_first_response_minutes"
    t.integer "time_to_resolution_minutes"
    t.integer "debug_session_count", default: 0
    t.integer "code_fix_attempts", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin_approved", default: false
    t.bigint "admin_approved_by_id"
    t.datetime "admin_approved_at"
    t.index ["admin_approved"], name: "index_support_tickets_on_admin_approved"
    t.index ["category", "admin_approved"], name: "idx_tickets_feature_approval"
    t.index ["entity_id", "created_at"], name: "index_support_tickets_on_entity_id_and_created_at"
    t.index ["entity_id", "status"], name: "index_support_tickets_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_support_tickets_on_entity_id"
    t.index ["error_signature"], name: "index_support_tickets_on_error_signature"
    t.index ["priority"], name: "index_support_tickets_on_priority"
    t.index ["scout_conversation_id"], name: "index_support_tickets_on_scout_conversation_id"
    t.index ["source"], name: "index_support_tickets_on_source"
    t.index ["status"], name: "index_support_tickets_on_status"
    t.index ["ticket_number"], name: "index_support_tickets_on_ticket_number", unique: true
    t.index ["user_id"], name: "index_support_tickets_on_user_id"
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

  create_table "system_notifications", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id"
    t.string "category", null: false
    t.string "severity", default: "info", null: false
    t.string "title", null: false
    t.text "message"
    t.jsonb "metadata", default: {}
    t.boolean "actionable", default: false
    t.string "action_label"
    t.string "action_path"
    t.datetime "read_at"
    t.datetime "dismissed_at"
    t.string "dismissed_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "category"], name: "index_system_notifications_on_entity_id_and_category"
    t.index ["entity_id", "created_at"], name: "index_system_notifications_on_entity_id_and_created_at"
    t.index ["entity_id", "severity"], name: "index_system_notifications_on_entity_id_and_severity"
    t.index ["entity_id", "user_id", "read_at"], name: "idx_notifications_unread"
    t.index ["entity_id"], name: "index_system_notifications_on_entity_id"
    t.index ["user_id"], name: "index_system_notifications_on_user_id"
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

  create_table "task_experiences", force: :cascade do |t|
    t.bigint "entity_id"
    t.string "task_type", null: false
    t.text "content", null: false
    t.string "applies_when"
    t.string "source_type"
    t.bigint "evolution_cycle_id"
    t.float "utility_score", default: 0.5
    t.integer "apply_count", default: 0
    t.integer "positive_outcome_count", default: 0
    t.datetime "last_applied_at"
    t.boolean "active", default: true
    t.integer "generation", default: 1
    t.jsonb "source_context", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "active", "utility_score"], name: "idx_on_entity_id_active_utility_score_fa102c1e53"
    t.index ["entity_id", "task_type", "active"], name: "index_task_experiences_on_entity_id_and_task_type_and_active"
    t.index ["entity_id", "task_type"], name: "index_task_experiences_on_entity_id_and_task_type"
    t.index ["entity_id"], name: "index_task_experiences_on_entity_id"
    t.index ["evolution_cycle_id"], name: "index_task_experiences_on_evolution_cycle_id"
    t.index ["task_type"], name: "index_task_experiences_on_task_type", where: "(entity_id IS NULL)"
    t.index ["utility_score"], name: "index_task_experiences_on_utility_score"
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

  create_table "task_trackers", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "title", null: false
    t.date "due_date"
    t.string "priority", default: "medium"
    t.boolean "completed", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_task_trackers_on_entity_id"
  end

  create_table "team_channels", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "channel_type", default: "general"
    t.jsonb "settings", default: {}
    t.boolean "is_default", default: false
    t.boolean "archived", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "purpose"
    t.string "topic"
    t.boolean "is_private", default: false
    t.integer "member_count", default: 0
    t.datetime "last_activity_at"
    t.jsonb "agent_roster", default: []
    t.boolean "auto_invite_agents", default: true
    t.boolean "allow_agent_initiation", default: true
    t.boolean "require_human_approval", default: false
    t.index ["agent_roster"], name: "index_team_channels_on_agent_roster", using: :gin
    t.index ["archived"], name: "index_team_channels_on_archived"
    t.index ["channel_type"], name: "index_team_channels_on_channel_type"
    t.index ["entity_id", "name"], name: "index_team_channels_on_entity_id_and_name", unique: true
    t.index ["entity_id"], name: "index_team_channels_on_entity_id"
    t.index ["is_private"], name: "index_team_channels_on_is_private"
    t.index ["last_activity_at"], name: "index_team_channels_on_last_activity_at"
  end

  create_table "team_invites", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "invited_by_id", null: false
    t.string "email", null: false
    t.string "role", default: "member", null: false
    t.string "token", null: false
    t.string "status", default: "pending", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "declined_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "email"], name: "index_team_invites_on_entity_id_and_email", unique: true, where: "((status)::text = 'pending'::text)"
    t.index ["entity_id"], name: "index_team_invites_on_entity_id"
    t.index ["invited_by_id"], name: "index_team_invites_on_invited_by_id"
    t.index ["token"], name: "index_team_invites_on_token", unique: true
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

  create_table "token_buybacks", force: :cascade do |t|
    t.string "period", null: false
    t.decimal "usdc_amount", precision: 15, scale: 2, null: false
    t.decimal "estimated_tokens", precision: 20, scale: 4
    t.decimal "actual_tokens_bought", precision: 20, scale: 4
    t.decimal "token_price_at_buyback", precision: 15, scale: 6
    t.string "status", default: "pending", null: false
    t.string "swap_transaction_signature"
    t.string "burn_transaction_signature"
    t.datetime "executed_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["period"], name: "index_token_buybacks_on_period"
    t.index ["status"], name: "index_token_buybacks_on_status"
  end

  create_table "token_claims", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id"
    t.decimal "amount", precision: 18, scale: 9, null: false
    t.string "wallet_address", null: false
    t.string "status", default: "pending", null: false
    t.string "transaction_signature"
    t.string "blockhash"
    t.bigint "slot"
    t.datetime "confirmed_at"
    t.decimal "network_fee", precision: 18, scale: 9
    t.decimal "platform_fee", precision: 18, scale: 9
    t.text "error_message"
    t.integer "retry_count", default: 0
    t.datetime "last_retry_at"
    t.string "ip_address"
    t.string "user_agent"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "disbursement_currency", default: "amos"
    t.jsonb "swap_quote"
    t.string "swap_transaction_signature"
    t.decimal "final_amount", precision: 18, scale: 9
    t.decimal "swap_rate", precision: 18, scale: 9
    t.index ["created_at"], name: "index_token_claims_on_created_at"
    t.index ["disbursement_currency"], name: "index_token_claims_on_disbursement_currency"
    t.index ["entity_id"], name: "index_token_claims_on_entity_id"
    t.index ["status"], name: "index_token_claims_on_status"
    t.index ["transaction_signature"], name: "index_token_claims_on_transaction_signature", unique: true
    t.index ["user_id", "status"], name: "index_token_claims_on_user_id_and_status"
    t.index ["user_id"], name: "index_token_claims_on_user_id"
    t.index ["wallet_address"], name: "index_token_claims_on_wallet_address"
  end

  create_table "token_deposits", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id"
    t.bigint "token_stake_id"
    t.decimal "amount", precision: 18, scale: 9, null: false
    t.string "wallet_address", null: false
    t.string "status", default: "pending", null: false
    t.string "transaction_signature", null: false
    t.string "blockhash"
    t.bigint "slot"
    t.datetime "confirmed_at"
    t.boolean "verified", default: false
    t.datetime "verified_at"
    t.text "error_message"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_token_deposits_on_entity_id"
    t.index ["status"], name: "index_token_deposits_on_status"
    t.index ["token_stake_id"], name: "index_token_deposits_on_token_stake_id"
    t.index ["transaction_signature"], name: "index_token_deposits_on_transaction_signature", unique: true
    t.index ["user_id", "status"], name: "index_token_deposits_on_user_id_and_status"
    t.index ["user_id"], name: "index_token_deposits_on_user_id"
    t.index ["verified"], name: "index_token_deposits_on_verified"
    t.index ["wallet_address"], name: "index_token_deposits_on_wallet_address"
  end

  create_table "token_stake_transactions", force: :cascade do |t|
    t.bigint "token_stake_id", null: false
    t.bigint "user_id", null: false
    t.string "transaction_type", null: false
    t.decimal "amount", precision: 18, scale: 4, null: false
    t.decimal "balance_before", precision: 18, scale: 4, null: false
    t.decimal "balance_after", precision: 18, scale: 4, null: false
    t.string "description"
    t.string "external_reference"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_token_stake_transactions_on_created_at"
    t.index ["token_stake_id"], name: "index_token_stake_transactions_on_token_stake_id"
    t.index ["transaction_type"], name: "index_token_stake_transactions_on_transaction_type"
    t.index ["user_id", "transaction_type"], name: "index_token_stake_transactions_on_user_id_and_transaction_type"
    t.index ["user_id"], name: "index_token_stake_transactions_on_user_id"
  end

  create_table "token_stakes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id"
    t.string "source_type"
    t.bigint "source_id"
    t.string "stake_type", null: false
    t.string "category"
    t.decimal "initial_amount", precision: 18, scale: 4, null: false
    t.decimal "current_amount", precision: 18, scale: 4, null: false
    t.decimal "decay_rate", precision: 5, scale: 4, default: "0.5", null: false
    t.decimal "total_decayed", precision: 18, scale: 4, default: "0.0"
    t.datetime "earned_at", null: false
    t.datetime "last_decay_at"
    t.datetime "vested_at"
    t.boolean "is_transferable", default: false
    t.boolean "is_locked", default: false
    t.datetime "lock_until"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "staking_tier", default: "none"
    t.datetime "locked_until"
    t.bigint "beneficiary_id"
    t.bigint "transferred_to_id"
    t.datetime "transferred_at"
    t.decimal "permanent_floor", precision: 18, scale: 4
    t.string "clawback_status"
    t.index ["beneficiary_id"], name: "index_token_stakes_on_beneficiary_id"
    t.index ["category"], name: "index_token_stakes_on_category"
    t.index ["clawback_status"], name: "index_token_stakes_on_clawback_status"
    t.index ["current_amount"], name: "index_token_stakes_active", where: "(current_amount > (0)::numeric)"
    t.index ["earned_at"], name: "index_token_stakes_on_earned_at"
    t.index ["entity_id", "stake_type"], name: "index_token_stakes_on_entity_id_and_stake_type"
    t.index ["entity_id"], name: "index_token_stakes_on_entity_id"
    t.index ["locked_until"], name: "index_token_stakes_on_locked_until"
    t.index ["source_type", "source_id"], name: "index_token_stakes_on_source"
    t.index ["stake_type", "clawback_status"], name: "index_token_stakes_on_distribution_clawback"
    t.index ["stake_type"], name: "index_token_stakes_on_stake_type"
    t.index ["staking_tier"], name: "index_token_stakes_on_staking_tier"
    t.index ["transferred_to_id"], name: "index_token_stakes_on_transferred_to_id"
    t.index ["user_id", "stake_type"], name: "index_token_stakes_on_user_id_and_stake_type"
    t.index ["user_id"], name: "index_token_stakes_on_user_id"
  end

  create_table "tool_definitions", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.jsonb "parameters", default: {}
    t.string "execution_type", default: "ruby_code"
    t.text "code"
    t.jsonb "api_config", default: {}
    t.boolean "admin_only", default: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_public", default: false
    t.datetime "published_at"
    t.vector "embedding", limit: 1536
    t.string "security_rating"
    t.text "security_reason"
    t.bigint "entity_id"
    t.boolean "scout_accessible", default: false
    t.bigint "app_module_id"
    t.string "publish_status"
    t.index ["app_module_id"], name: "index_tool_definitions_on_app_module_id"
    t.index ["created_by_id"], name: "index_tool_definitions_on_created_by_id"
    t.index ["embedding"], name: "index_tool_definitions_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["entity_id", "name"], name: "index_tool_definitions_on_entity_and_name", unique: true
    t.index ["entity_id"], name: "index_tool_definitions_on_entity_id"
    t.index ["scout_accessible"], name: "index_tool_definitions_on_scout_accessible"
  end

  create_table "tool_usage_metrics", force: :cascade do |t|
    t.string "tool_name", null: false
    t.bigint "user_id"
    t.bigint "entity_id"
    t.bigint "tool_definition_id"
    t.string "tool_type"
    t.boolean "success", default: true
    t.integer "latency_ms"
    t.jsonb "metadata", default: {}
    t.string "context"
    t.string "agent_slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_tool_usage_metrics_on_created_at"
    t.index ["entity_id", "tool_name"], name: "index_tool_usage_metrics_on_entity_id_and_tool_name"
    t.index ["entity_id"], name: "index_tool_usage_metrics_on_entity_id"
    t.index ["tool_definition_id"], name: "index_tool_usage_metrics_on_tool_definition_id"
    t.index ["tool_name", "success"], name: "index_tool_usage_metrics_on_tool_name_and_success"
    t.index ["tool_name"], name: "index_tool_usage_metrics_on_tool_name"
    t.index ["user_id", "tool_name"], name: "index_tool_usage_metrics_on_user_id_and_tool_name"
    t.index ["user_id"], name: "index_tool_usage_metrics_on_user_id"
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

  create_table "user_billing_accounts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "stripe_customer_id"
    t.string "stripe_default_payment_method_id"
    t.boolean "has_payment_method", default: false
    t.bigint "work_token_balance", default: 0
    t.bigint "lifetime_tokens_purchased", default: 0
    t.bigint "lifetime_tokens_used", default: 0
    t.bigint "free_tokens_remaining", default: 200000
    t.integer "auto_replenish_amount_usd", default: 20
    t.integer "auto_replenish_threshold", default: 10000
    t.boolean "auto_replenish_enabled", default: true
    t.integer "monthly_limit_usd", default: 100
    t.decimal "current_month_spend_usd", precision: 10, scale: 2, default: "0.0"
    t.string "status", default: "active"
    t.datetime "suspended_at"
    t.string "suspension_reason"
    t.datetime "last_purchase_at"
    t.datetime "last_usage_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "last_threshold_notified"
    t.integer "free_tokens_granted"
    t.datetime "last_low_balance_notified_at"
    t.index ["status"], name: "index_user_billing_accounts_on_status"
    t.index ["stripe_customer_id"], name: "index_user_billing_accounts_on_stripe_customer_id", unique: true
    t.index ["user_id"], name: "index_user_billing_accounts_on_user_id", unique: true
    t.index ["work_token_balance"], name: "index_user_billing_accounts_on_work_token_balance"
  end

  create_table "user_communication_preferences", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "formality_level", default: 3
    t.integer "verbosity_level", default: 2
    t.boolean "humor_enabled", default: false
    t.integer "proactivity_level", default: 3
    t.jsonb "learned_patterns", default: {}
    t.datetime "last_learning_update"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_communication_preferences_on_user_id", unique: true
  end

  create_table "user_favorites", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "favoritable_type", null: false
    t.bigint "favoritable_id", null: false
    t.string "nickname"
    t.text "notes"
    t.integer "priority", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_user_favorites_on_entity_id"
    t.index ["favoritable_type", "favoritable_id"], name: "idx_user_favorites_favoritable"
    t.index ["priority"], name: "index_user_favorites_on_priority"
    t.index ["user_id", "favoritable_type", "favoritable_id"], name: "idx_user_favorites_unique", unique: true
    t.index ["user_id", "favoritable_type"], name: "idx_user_favorites_by_type"
    t.index ["user_id"], name: "index_user_favorites_on_user_id"
  end

  create_table "user_feedbacks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "feedbackable_type", null: false
    t.bigint "feedbackable_id", null: false
    t.integer "rating", null: false
    t.text "comment"
    t.string "feedback_type"
    t.string "session_id"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "created_at"], name: "index_user_feedbacks_on_entity_id_and_created_at"
    t.index ["entity_id"], name: "index_user_feedbacks_on_entity_id"
    t.index ["feedback_type"], name: "index_user_feedbacks_on_feedback_type"
    t.index ["feedbackable_type", "feedbackable_id"], name: "idx_user_feedbacks_feedbackable"
    t.index ["rating"], name: "index_user_feedbacks_on_rating"
    t.index ["session_id"], name: "index_user_feedbacks_on_session_id"
    t.index ["user_id", "created_at"], name: "index_user_feedbacks_on_user_id_and_created_at"
    t.index ["user_id", "feedbackable_type", "feedbackable_id", "session_id"], name: "idx_user_feedbacks_unique_per_session", unique: true, where: "(session_id IS NOT NULL)"
    t.index ["user_id"], name: "index_user_feedbacks_on_user_id"
  end

  create_table "user_memories", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "memory_type", null: false
    t.string "category"
    t.string "key"
    t.text "content", null: false
    t.string "source"
    t.float "confidence", default: 0.8
    t.integer "access_count", default: 0
    t.datetime "last_accessed_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["confidence"], name: "index_user_memories_on_confidence"
    t.index ["entity_id", "memory_type"], name: "index_user_memories_on_entity_id_and_memory_type"
    t.index ["entity_id"], name: "index_user_memories_on_entity_id"
    t.index ["user_id", "entity_id", "key"], name: "index_user_memories_on_user_id_and_entity_id_and_key", unique: true, where: "(key IS NOT NULL)"
    t.index ["user_id", "entity_id", "memory_type"], name: "index_user_memories_on_user_id_and_entity_id_and_memory_type"
    t.index ["user_id"], name: "index_user_memories_on_user_id"
  end

  create_table "user_menu_configurations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "space", null: false
    t.jsonb "visible_items", default: []
    t.jsonb "pinned_items", default: []
    t.jsonb "hidden_items", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["space"], name: "index_user_menu_configurations_on_space"
    t.index ["user_id", "space"], name: "index_user_menu_configurations_on_user_id_and_space", unique: true
  end

  create_table "user_notes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "content"
    t.string "color", default: "default"
    t.boolean "pinned", default: false
    t.boolean "archived", default: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "archived"], name: "index_user_notes_on_user_id_and_archived"
    t.index ["user_id", "pinned"], name: "index_user_notes_on_user_id_and_pinned"
    t.index ["user_id"], name: "index_user_notes_on_user_id"
  end

  create_table "user_notifications", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.bigint "agent_work_item_id"
    t.bigint "scheduled_task_run_id"
    t.string "notification_type", null: false
    t.string "title", null: false
    t.text "body"
    t.string "icon"
    t.string "channel", null: false
    t.boolean "email_sent", default: false
    t.datetime "email_sent_at"
    t.boolean "push_sent", default: false
    t.datetime "push_sent_at"
    t.boolean "read", default: false
    t.datetime "read_at"
    t.boolean "dismissed", default: false
    t.datetime "dismissed_at"
    t.string "action_url"
    t.string "action_type"
    t.jsonb "action_data", default: {}
    t.string "priority", default: "normal"
    t.datetime "expires_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_work_item_id"], name: "index_user_notifications_on_agent_work_item_id"
    t.index ["channel"], name: "index_user_notifications_on_channel"
    t.index ["created_at"], name: "index_user_notifications_on_created_at"
    t.index ["dismissed"], name: "index_user_notifications_on_dismissed"
    t.index ["entity_id", "user_id", "read"], name: "index_user_notifications_on_entity_id_and_user_id_and_read"
    t.index ["entity_id"], name: "index_user_notifications_on_entity_id"
    t.index ["notification_type"], name: "index_user_notifications_on_notification_type"
    t.index ["priority"], name: "index_user_notifications_on_priority"
    t.index ["read"], name: "index_user_notifications_on_read"
    t.index ["scheduled_task_run_id"], name: "index_user_notifications_on_scheduled_task_run_id"
    t.index ["user_id", "dismissed"], name: "index_user_notifications_on_user_id_and_dismissed"
    t.index ["user_id", "read"], name: "index_user_notifications_on_user_id_and_read"
    t.index ["user_id"], name: "index_user_notifications_on_user_id"
  end

  create_table "user_referrals", force: :cascade do |t|
    t.bigint "referrer_id", null: false
    t.bigint "referred_user_id"
    t.string "referred_email", null: false
    t.string "token", null: false
    t.integer "status", default: 0, null: false
    t.integer "tokens_awarded", default: 0
    t.datetime "email_sent_at"
    t.datetime "signed_up_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["referred_email"], name: "index_user_referrals_on_referred_email"
    t.index ["referred_user_id"], name: "index_user_referrals_on_referred_user_id"
    t.index ["referrer_id", "referred_email"], name: "index_user_referrals_on_referrer_id_and_referred_email", unique: true
    t.index ["referrer_id"], name: "index_user_referrals_on_referrer_id"
    t.index ["status"], name: "index_user_referrals_on_status"
    t.index ["token"], name: "index_user_referrals_on_token", unique: true
  end

  create_table "user_reminders", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.datetime "remind_at", null: false
    t.string "repeat_interval"
    t.boolean "completed", default: false
    t.datetime "completed_at"
    t.boolean "notified", default: false
    t.datetime "notified_at"
    t.string "priority", default: "normal"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "completed"], name: "index_user_reminders_on_user_id_and_completed"
    t.index ["user_id", "remind_at"], name: "index_user_reminders_on_user_id_and_remind_at"
    t.index ["user_id"], name: "index_user_reminders_on_user_id"
  end

  create_table "user_space_preferences", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "active_space", default: "work"
    t.jsonb "personal_settings", default: {}
    t.jsonb "work_settings", default: {}
    t.jsonb "team_settings", default: {}
    t.boolean "onboarding_completed", default: false
    t.jsonb "enabled_spaces", default: ["personal", "work", "team"]
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_space"], name: "index_user_space_preferences_on_active_space"
    t.index ["user_id"], name: "index_user_space_preferences_on_user_id", unique: true
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
    t.integer "agent_limit", default: 5
    t.integer "tool_limit", default: 5
    t.integer "integration_limit", default: 5
    t.integer "agents_limit", default: 5
    t.integer "tools_limit", default: 5
    t.integer "integrations_limit", default: 5
    t.string "stripe_customer_id"
    t.string "otp_secret"
    t.boolean "otp_required_for_login", default: false, null: false
    t.text "otp_backup_codes"
    t.boolean "otp_email_enabled", default: true, null: false
    t.string "otp_delivery_method", default: "totp"
    t.datetime "last_otp_at"
    t.integer "otp_failed_attempts", default: 0, null: false
    t.datetime "otp_locked_at"
    t.string "job_title"
    t.string "provider"
    t.string "uid"
    t.string "avatar_url"
    t.datetime "terms_accepted_at"
    t.string "terms_version"
    t.datetime "privacy_accepted_at"
    t.string "privacy_version"
    t.string "solana_wallet_address"
    t.datetime "wallet_verified_at"
    t.string "wallet_verification_message"
    t.string "wallet_verification_signature"
    t.string "preferred_disbursement_currency", default: "amos"
    t.boolean "auto_convert_to_stable", default: false
    t.index ["api_key"], name: "index_users_on_api_key"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["entity_id"], name: "index_users_on_entity_id"
    t.index ["otp_required_for_login"], name: "index_users_on_otp_required_for_login"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "(provider IS NOT NULL)"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["solana_wallet_address"], name: "index_users_on_solana_wallet_address", unique: true
    t.index ["stripe_customer_id"], name: "index_users_on_stripe_customer_id", unique: true
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

  create_table "web_app_modules", force: :cascade do |t|
    t.bigint "web_app_id", null: false
    t.bigint "app_module_id", null: false
    t.boolean "is_public", default: false
    t.boolean "allow_create", default: false
    t.boolean "allow_edit", default: false
    t.boolean "allow_delete", default: false
    t.jsonb "visible_fields", default: []
    t.jsonb "editable_fields", default: []
    t.jsonb "role_permissions", default: {}
    t.string "list_view_type", default: "table"
    t.integer "nav_order", default: 0
    t.string "nav_icon"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_module_id"], name: "index_web_app_modules_on_app_module_id"
    t.index ["web_app_id", "app_module_id"], name: "index_web_app_modules_on_web_app_id_and_app_module_id", unique: true
    t.index ["web_app_id"], name: "index_web_app_modules_on_web_app_id"
  end

  create_table "web_app_scripts", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "web_app_id"
    t.bigint "website_id"
    t.bigint "landing_page_id"
    t.string "name", null: false
    t.string "library_type", null: false
    t.string "library_name"
    t.string "cdn_url"
    t.text "inline_code"
    t.string "version"
    t.string "integrity_hash"
    t.boolean "is_module", default: false
    t.string "load_strategy", default: "defer"
    t.integer "load_order", default: 0
    t.string "status", default: "active"
    t.jsonb "config", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id", "library_name"], name: "index_web_app_scripts_on_entity_id_and_library_name"
    t.index ["entity_id"], name: "index_web_app_scripts_on_entity_id"
    t.index ["landing_page_id", "load_order"], name: "index_web_app_scripts_on_landing_page_id_and_load_order"
    t.index ["landing_page_id"], name: "index_web_app_scripts_on_landing_page_id"
    t.index ["web_app_id", "load_order"], name: "index_web_app_scripts_on_web_app_id_and_load_order"
    t.index ["web_app_id"], name: "index_web_app_scripts_on_web_app_id"
    t.index ["website_id", "load_order"], name: "index_web_app_scripts_on_website_id_and_load_order"
    t.index ["website_id"], name: "index_web_app_scripts_on_website_id"
  end

  create_table "web_apps", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "application_plan_id"
    t.bigint "website_id"
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "status", default: "draft", null: false
    t.boolean "requires_auth", default: true
    t.jsonb "auth_config", default: {}, null: false
    t.jsonb "roles", default: [], null: false
    t.jsonb "module_config", default: {}, null: false
    t.string "logo_url"
    t.string "primary_color"
    t.jsonb "branding", default: {}
    t.string "subdomain"
    t.string "custom_domain"
    t.jsonb "features", default: [], null: false
    t.integer "user_count", default: 0
    t.integer "monthly_active_users", default: 0
    t.datetime "last_activity_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["application_plan_id"], name: "index_web_apps_on_application_plan_id"
    t.index ["created_by_id"], name: "index_web_apps_on_created_by_id"
    t.index ["custom_domain"], name: "index_web_apps_on_custom_domain", unique: true
    t.index ["entity_id", "slug"], name: "index_web_apps_on_entity_id_and_slug", unique: true
    t.index ["entity_id"], name: "index_web_apps_on_entity_id"
    t.index ["status"], name: "index_web_apps_on_status"
    t.index ["subdomain"], name: "index_web_apps_on_subdomain", unique: true
    t.index ["website_id"], name: "index_web_apps_on_website_id"
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

  create_table "website_pages", force: :cascade do |t|
    t.bigint "website_id", null: false
    t.bigint "entity_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.text "html_content"
    t.jsonb "content_blocks", default: [], null: false
    t.string "template", default: "content"
    t.boolean "use_website_layout", default: true
    t.text "custom_header_html"
    t.text "custom_footer_html"
    t.boolean "is_homepage", default: false
    t.boolean "is_dynamic", default: false
    t.bigint "app_module_id"
    t.string "module_view_type"
    t.jsonb "module_config", default: {}
    t.string "meta_title"
    t.text "meta_description"
    t.string "og_image_url"
    t.boolean "show_in_nav", default: true
    t.integer "nav_order", default: 0
    t.string "nav_label"
    t.boolean "requires_auth", default: false
    t.jsonb "access_roles", default: []
    t.string "status", default: "draft", null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_module_id"], name: "index_website_pages_on_app_module_id"
    t.index ["entity_id"], name: "index_website_pages_on_entity_id"
    t.index ["status"], name: "index_website_pages_on_status"
    t.index ["template"], name: "index_website_pages_on_template"
    t.index ["website_id", "is_homepage"], name: "index_website_pages_on_website_id_and_is_homepage"
    t.index ["website_id", "slug"], name: "index_website_pages_on_website_id_and_slug", unique: true
    t.index ["website_id"], name: "index_website_pages_on_website_id"
  end

  create_table "websites", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "application_plan_id"
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "status", default: "draft", null: false
    t.string "theme", default: "modern"
    t.jsonb "theme_config", default: {}, null: false
    t.text "header_html"
    t.text "footer_html"
    t.text "custom_css"
    t.text "custom_js"
    t.string "meta_title"
    t.text "meta_description"
    t.string "favicon_url"
    t.string "og_image_url"
    t.string "subdomain"
    t.string "custom_domain"
    t.boolean "ssl_enabled", default: true
    t.jsonb "features", default: [], null: false
    t.string "google_analytics_id"
    t.jsonb "tracking_config", default: {}
    t.datetime "published_at"
    t.datetime "last_built_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "custom_domain_id"
    t.index ["application_plan_id"], name: "index_websites_on_application_plan_id"
    t.index ["created_by_id"], name: "index_websites_on_created_by_id"
    t.index ["custom_domain"], name: "index_websites_on_custom_domain", unique: true
    t.index ["custom_domain_id"], name: "index_websites_on_custom_domain_id"
    t.index ["entity_id", "slug"], name: "index_websites_on_entity_id_and_slug", unique: true
    t.index ["entity_id"], name: "index_websites_on_entity_id"
    t.index ["slug"], name: "index_websites_on_slug"
    t.index ["status"], name: "index_websites_on_status"
    t.index ["subdomain"], name: "index_websites_on_subdomain", unique: true
  end

  create_table "work_token_purchases", force: :cascade do |t|
    t.bigint "user_billing_account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "work_token_transaction_id"
    t.integer "amount_usd_cents", null: false
    t.bigint "tokens_purchased", null: false
    t.bigint "bonus_tokens", default: 0
    t.string "purchase_tier"
    t.string "stripe_payment_intent_id"
    t.string "stripe_charge_id"
    t.string "stripe_invoice_id"
    t.string "status", default: "pending"
    t.string "failure_reason"
    t.string "trigger", default: "manual"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_work_token_purchases_on_status"
    t.index ["stripe_payment_intent_id"], name: "index_work_token_purchases_on_stripe_payment_intent_id", unique: true
    t.index ["user_billing_account_id", "status"], name: "idx_on_user_billing_account_id_status_2c1b941220"
    t.index ["user_billing_account_id"], name: "index_work_token_purchases_on_user_billing_account_id"
    t.index ["user_id"], name: "index_work_token_purchases_on_user_id"
    t.index ["work_token_transaction_id"], name: "index_work_token_purchases_on_work_token_transaction_id"
  end

  create_table "work_token_transactions", force: :cascade do |t|
    t.bigint "user_billing_account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "entity_id"
    t.string "transaction_type", null: false
    t.string "category"
    t.bigint "token_amount", null: false
    t.bigint "balance_before", null: false
    t.bigint "balance_after", null: false
    t.integer "raw_cost_cents", default: 0
    t.integer "uplifted_cost_cents", default: 0
    t.decimal "uplift_percentage_applied", precision: 5, scale: 2
    t.string "source_type"
    t.bigint "source_id"
    t.string "stripe_payment_intent_id"
    t.string "stripe_charge_id"
    t.string "description"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_billing_account_id"
    t.index ["category", "created_at"], name: "index_work_token_transactions_on_category_and_created_at"
    t.index ["entity_billing_account_id"], name: "index_work_token_transactions_on_entity_billing_account_id"
    t.index ["entity_id"], name: "index_work_token_transactions_on_entity_id"
    t.index ["source_type", "source_id"], name: "index_work_token_transactions_on_source_type_and_source_id"
    t.index ["stripe_payment_intent_id"], name: "index_work_token_transactions_on_stripe_payment_intent_id"
    t.index ["transaction_type", "created_at"], name: "idx_on_transaction_type_created_at_3b1d1dd50c"
    t.index ["user_billing_account_id", "created_at"], name: "idx_on_user_billing_account_id_created_at_e1a02829d6"
    t.index ["user_billing_account_id"], name: "index_work_token_transactions_on_user_billing_account_id"
    t.index ["user_id"], name: "index_work_token_transactions_on_user_id"
  end

  create_table "work_token_usage_summaries", force: :cascade do |t|
    t.bigint "user_billing_account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "entity_id"
    t.date "summary_date", null: false
    t.string "category", null: false
    t.bigint "tokens_used", default: 0
    t.integer "transaction_count", default: 0
    t.integer "raw_cost_cents", default: 0
    t.integer "uplifted_cost_cents", default: 0
    t.jsonb "breakdown", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_billing_account_id"
    t.index ["entity_billing_account_id"], name: "index_work_token_usage_summaries_on_entity_billing_account_id"
    t.index ["entity_id"], name: "index_work_token_usage_summaries_on_entity_id"
    t.index ["summary_date", "category"], name: "index_work_token_usage_summaries_on_summary_date_and_category"
    t.index ["user_billing_account_id", "summary_date", "category"], name: "idx_usage_summary_unique", unique: true
    t.index ["user_billing_account_id"], name: "index_work_token_usage_summaries_on_user_billing_account_id"
    t.index ["user_id"], name: "index_work_token_usage_summaries_on_user_id"
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

  create_table "workflow_triggers", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "automation_code_id", null: false
    t.string "triggerable_type"
    t.bigint "triggerable_id"
    t.string "webhook_path"
    t.string "webhook_secret"
    t.string "trigger_type", null: false
    t.jsonb "trigger_config", default: {}
    t.string "cron_expression"
    t.datetime "next_trigger_at"
    t.datetime "last_triggered_at"
    t.string "status", default: "active"
    t.boolean "enabled", default: true
    t.integer "trigger_count", default: 0
    t.integer "success_count", default: 0
    t.integer "error_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["automation_code_id"], name: "index_workflow_triggers_on_automation_code_id"
    t.index ["entity_id", "status"], name: "index_workflow_triggers_on_entity_id_and_status"
    t.index ["entity_id"], name: "index_workflow_triggers_on_entity_id"
    t.index ["trigger_type", "status"], name: "index_workflow_triggers_on_trigger_type_and_status"
    t.index ["triggerable_type", "triggerable_id"], name: "index_workflow_triggers_on_triggerable"
    t.index ["triggerable_type", "triggerable_id"], name: "index_workflow_triggers_on_triggerable_type_and_triggerable_id"
    t.index ["webhook_path"], name: "index_workflow_triggers_on_webhook_path", unique: true, where: "(webhook_path IS NOT NULL)"
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
  add_foreign_key "activities", "agent_plugins", column: "assigned_agent_id"
  add_foreign_key "activities", "agent_plugins", column: "performed_by_agent_id"
  add_foreign_key "activities", "contacts"
  add_foreign_key "activities", "entities"
  add_foreign_key "activities", "opportunities"
  add_foreign_key "activities", "users"
  add_foreign_key "activities", "users", column: "assigned_user_id"
  add_foreign_key "admin_activities", "admin_users"
  add_foreign_key "affiliate_clicks", "affiliates"
  add_foreign_key "affiliates", "admin_users", column: "approved_by_id"
  add_foreign_key "affiliates", "users"
  add_foreign_key "agent_ab_tests", "agent_goals"
  add_foreign_key "agent_ab_tests", "agent_plugins", column: "control_agent_id"
  add_foreign_key "agent_ab_tests", "agent_plugins", column: "variant_agent_id"
  add_foreign_key "agent_ab_tests", "agent_school_enrollments", column: "enrollment_id"
  add_foreign_key "agent_ab_tests", "entities"
  add_foreign_key "agent_ab_tests", "evolution_cycles"
  add_foreign_key "agent_activities", "scout_conversations", column: "conversation_id"
  add_foreign_key "agent_capabilities", "agent_plugins"
  add_foreign_key "agent_capability_beliefs", "agent_plugins"
  add_foreign_key "agent_collaboration_requests", "agent_collaboration_requests", column: "parent_request_id"
  add_foreign_key "agent_collaboration_requests", "agent_plugin_executions"
  add_foreign_key "agent_collaboration_requests", "agent_plugins", column: "helper_agent_id"
  add_foreign_key "agent_collaboration_requests", "agent_plugins", column: "requesting_agent_id"
  add_foreign_key "agent_collaboration_requests", "entities"
  add_foreign_key "agent_decision_boundaries", "agent_plugins"
  add_foreign_key "agent_energy_states", "agent_plugins"
  add_foreign_key "agent_energy_states", "entities"
  add_foreign_key "agent_energy_transactions", "agent_collaboration_requests", column: "collaboration_request_id"
  add_foreign_key "agent_energy_transactions", "agent_plugin_executions"
  add_foreign_key "agent_energy_transactions", "agent_plugins"
  add_foreign_key "agent_energy_transactions", "entities"
  add_foreign_key "agent_executions", "pipeline_executions"
  add_foreign_key "agent_genomes", "agent_genomes", column: "parent_id"
  add_foreign_key "agent_goals", "agent_plugins"
  add_foreign_key "agent_goals", "agent_plugins", column: "created_by_agent_id"
  add_foreign_key "agent_goals", "agent_school_enrollments", column: "school_enrollment_id"
  add_foreign_key "agent_goals", "entities"
  add_foreign_key "agent_goals", "scheduled_agent_tasks", column: "execution_task_id"
  add_foreign_key "agent_input_requests", "agent_plugin_executions"
  add_foreign_key "agent_knowledge_shares", "agent_plugins", column: "source_agent_id"
  add_foreign_key "agent_knowledge_shares", "agent_plugins", column: "target_agent_id"
  add_foreign_key "agent_knowledge_shares", "agent_relationships"
  add_foreign_key "agent_knowledge_shares", "entities"
  add_foreign_key "agent_lifecycle_events", "agent_goals", column: "triggered_by_goal_id"
  add_foreign_key "agent_lifecycle_events", "agent_plugins"
  add_foreign_key "agent_lifecycle_events", "agent_school_enrollments", column: "school_enrollment_id"
  add_foreign_key "agent_lifecycle_events", "entities"
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
  add_foreign_key "agent_plugin_executions", "agent_ab_tests", column: "evolution_experiment_id"
  add_foreign_key "agent_plugin_executions", "agent_plugins"
  add_foreign_key "agent_plugin_executions", "users"
  add_foreign_key "agent_plugin_executions", "workflow_executions"
  add_foreign_key "agent_plugins", "agent_plugins", column: "parent_agent_id"
  add_foreign_key "agent_plugins", "agent_school_enrollments", column: "school_enrollment_id"
  add_foreign_key "agent_plugins", "app_modules"
  add_foreign_key "agent_plugins", "apps"
  add_foreign_key "agent_plugins", "entities"
  add_foreign_key "agent_plugins", "users"
  add_foreign_key "agent_plugins", "users", column: "reviewed_by_id", on_delete: :nullify
  add_foreign_key "agent_reflections", "agent_plugin_executions"
  add_foreign_key "agent_reflections", "agent_plugins"
  add_foreign_key "agent_reflections", "agent_school_enrollments", column: "triggered_enrollment_id"
  add_foreign_key "agent_reflections", "entities"
  add_foreign_key "agent_relationships", "agent_plugins", column: "helper_id"
  add_foreign_key "agent_relationships", "agent_plugins", column: "requester_id"
  add_foreign_key "agent_relationships", "agent_relationships", column: "inherited_from_id"
  add_foreign_key "agent_relationships", "entities"
  add_foreign_key "agent_rewards", "agent_lightning_traces"
  add_foreign_key "agent_rewards", "entities"
  add_foreign_key "agent_rewards", "users"
  add_foreign_key "agent_school_enrollments", "agent_goals", column: "triggered_by_goal_id"
  add_foreign_key "agent_school_enrollments", "agent_plugins"
  add_foreign_key "agent_school_enrollments", "agent_plugins", column: "student_agent_id"
  add_foreign_key "agent_school_enrollments", "entities"
  add_foreign_key "agent_school_enrollments", "evolution_cycles"
  add_foreign_key "agent_scratchpads", "agent_plugin_executions", column: "source_execution_id"
  add_foreign_key "agent_scratchpads", "agent_plugins", column: "source_agent_plugin_id"
  add_foreign_key "agent_scratchpads", "entities"
  add_foreign_key "agent_scratchpads", "users"
  add_foreign_key "agent_simulations", "agent_genomes"
  add_foreign_key "agent_simulations", "agent_plugins"
  add_foreign_key "agent_task_proposals", "agent_plugin_executions"
  add_foreign_key "agent_task_proposals", "agent_plugins", column: "proposing_agent_id"
  add_foreign_key "agent_task_proposals", "agent_plugins", column: "receiving_agent_id"
  add_foreign_key "agent_task_proposals", "agent_work_items"
  add_foreign_key "agent_task_proposals", "entities"
  add_foreign_key "agent_task_proposals", "users"
  add_foreign_key "agent_template_bindings", "agent_plugins"
  add_foreign_key "agent_template_bindings", "workflow_templates"
  add_foreign_key "agent_tool_executions", "agent_lightning_traces"
  add_foreign_key "agent_tool_executions", "agent_llm_calls"
  add_foreign_key "agent_tool_executions", "entities"
  add_foreign_key "agent_tools", "agent_plugins"
  add_foreign_key "agent_training_jobs", "entities"
  add_foreign_key "agent_work_items", "agent_plugin_executions"
  add_foreign_key "agent_work_items", "agent_plugins"
  add_foreign_key "agent_work_items", "entities"
  add_foreign_key "agent_work_items", "scheduled_task_runs"
  add_foreign_key "agent_work_items", "scout_conversations"
  add_foreign_key "agent_work_items", "users"
  add_foreign_key "ai_rulesets", "entities"
  add_foreign_key "ai_usage_logs", "entities"
  add_foreign_key "ai_usage_logs", "scout_messages"
  add_foreign_key "ai_usage_logs", "users"
  add_foreign_key "amos_thinking_sessions", "entities"
  add_foreign_key "analytics_connections", "entities"
  add_foreign_key "analytics_query_logs", "entities"
  add_foreign_key "analytics_query_logs", "metric_definitions"
  add_foreign_key "analytics_query_logs", "users"
  add_foreign_key "app_modules", "apps"
  add_foreign_key "app_modules", "entities"
  add_foreign_key "app_modules", "users", column: "created_by_id"
  add_foreign_key "application_plans", "entities"
  add_foreign_key "application_plans", "users", column: "created_by_id"
  add_foreign_key "apps", "entities"
  add_foreign_key "apps", "users", column: "created_by_id"
  add_foreign_key "artifacts", "entities"
  add_foreign_key "artifacts", "users"
  add_foreign_key "auth_configs", "oauth_configurations"
  add_foreign_key "automation_codes", "app_modules"
  add_foreign_key "automation_codes", "entities"
  add_foreign_key "automation_codes", "users", column: "created_by_id"
  add_foreign_key "automation_codes", "web_apps"
  add_foreign_key "automation_executions", "automation_codes"
  add_foreign_key "automation_executions", "entities"
  add_foreign_key "automation_executions", "users", column: "triggered_by_id"
  add_foreign_key "benchmark_runs", "entities"
  add_foreign_key "benchmark_task_results", "agent_plugin_executions"
  add_foreign_key "benchmark_task_results", "agent_plugins"
  add_foreign_key "benchmark_task_results", "benchmark_runs"
  add_foreign_key "bounties", "entities"
  add_foreign_key "bounties", "pull_request_submissions"
  add_foreign_key "bounties", "support_tickets"
  add_foreign_key "bounties", "users", column: "claimed_by_id"
  add_foreign_key "bounties", "users", column: "created_by_id"
  add_foreign_key "bounties", "users", column: "reviewed_by_id"
  add_foreign_key "business_insights", "entities"
  add_foreign_key "business_insights", "scout_conversations", column: "source_conversation_id"
  add_foreign_key "business_profiles", "entities"
  add_foreign_key "business_profiles", "users"
  add_foreign_key "campaign_groups", "campaigns"
  add_foreign_key "campaign_groups", "contact_groups"
  add_foreign_key "campaigns", "email_templates"
  add_foreign_key "campaigns", "entities"
  add_foreign_key "campaigns", "users"
  add_foreign_key "code_fixes", "debug_sessions"
  add_foreign_key "code_fixes", "entities"
  add_foreign_key "code_fixes", "support_tickets"
  add_foreign_key "commissions", "admin_users", column: "approved_by_id"
  add_foreign_key "commissions", "affiliates"
  add_foreign_key "commissions", "entities"
  add_foreign_key "commissions", "referrals"
  add_foreign_key "commissions", "subscription_events"
  add_foreign_key "community_energy_pools", "entities"
  add_foreign_key "connections", "entities"
  add_foreign_key "connections", "integrations"
  add_foreign_key "connections", "users"
  add_foreign_key "contact_groups", "entities"
  add_foreign_key "contact_groups", "users"
  add_foreign_key "contact_groups_contacts", "contact_groups"
  add_foreign_key "contact_groups_contacts", "contacts"
  add_foreign_key "contacts", "agent_plugins", column: "assigned_agent_id"
  add_foreign_key "contacts", "entities"
  add_foreign_key "contacts", "users"
  add_foreign_key "contacts", "users", column: "assigned_user_id"
  add_foreign_key "context_graph_stats", "entities"
  add_foreign_key "contributions", "entities"
  add_foreign_key "contributions", "users"
  add_foreign_key "contributions", "users", column: "reviewed_by_id"
  add_foreign_key "conversation_embeddings", "entities"
  add_foreign_key "conversation_embeddings", "scout_messages"
  add_foreign_key "conversation_summaries", "entities"
  add_foreign_key "conversation_summaries", "users"
  add_foreign_key "crawler_conversations", "crawler_jobs"
  add_foreign_key "crawler_job_logs", "crawler_jobs"
  add_foreign_key "crawler_jobs", "entities"
  add_foreign_key "crawler_jobs", "users"
  add_foreign_key "custom_domains", "connections"
  add_foreign_key "custom_domains", "entities"
  add_foreign_key "custom_domains", "users"
  add_foreign_key "custom_field_definitions", "app_modules"
  add_foreign_key "custom_field_definitions", "entities"
  add_foreign_key "custom_models", "entities"
  add_foreign_key "custom_models", "users"
  add_foreign_key "custom_plugins", "entities"
  add_foreign_key "custom_plugins", "users"
  add_foreign_key "debug_sessions", "entities"
  add_foreign_key "debug_sessions", "support_tickets"
  add_foreign_key "debug_sessions", "users"
  add_foreign_key "decision_precedents", "decision_traces"
  add_foreign_key "decision_precedents", "decision_traces", column: "precedent_decision_id"
  add_foreign_key "decision_traces", "agent_lightning_traces"
  add_foreign_key "decision_traces", "agent_plugins"
  add_foreign_key "decision_traces", "decision_traces", column: "parent_decision_id"
  add_foreign_key "decision_traces", "entities"
  add_foreign_key "decision_traces", "users"
  add_foreign_key "design_plans", "apps"
  add_foreign_key "design_plans", "entities"
  add_foreign_key "design_plans", "landing_pages"
  add_foreign_key "design_plans", "module_canvases", column: "module_canvas_id"
  add_foreign_key "design_plans", "users"
  add_foreign_key "design_plans", "websites"
  add_foreign_key "device_tokens", "users"
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
  add_foreign_key "dynamic_contents", "agent_plugin_executions"
  add_foreign_key "dynamic_contents", "entities"
  add_foreign_key "dynamic_contents", "scheduled_task_runs"
  add_foreign_key "dynamic_contents", "scout_conversations"
  add_foreign_key "dynamic_contents", "users"
  add_foreign_key "email_deliveries", "campaigns"
  add_foreign_key "email_deliveries", "contacts"
  add_foreign_key "email_deliveries", "email_templates"
  add_foreign_key "email_sequences", "contact_groups"
  add_foreign_key "email_sequences", "entities"
  add_foreign_key "email_templates", "entities"
  add_foreign_key "email_templates", "users"
  add_foreign_key "entity_billing_accounts", "entities"
  add_foreign_key "entity_cost_reports", "entities"
  add_foreign_key "entity_cost_summaries", "entities"
  add_foreign_key "entity_usage_metrics", "entities"
  add_foreign_key "entity_users", "entities"
  add_foreign_key "entity_users", "users"
  add_foreign_key "error_log_entries", "entities"
  add_foreign_key "error_log_entries", "support_tickets"
  add_foreign_key "evolution_cycles", "entities"
  add_foreign_key "execution_plans", "agent_plugins", column: "created_by_agent_id"
  add_foreign_key "execution_plans", "entities"
  add_foreign_key "execution_plans", "users"
  add_foreign_key "factory_test_criteria", "entities"
  add_foreign_key "factory_test_criteria", "users"
  add_foreign_key "factory_test_runs", "entities"
  add_foreign_key "factory_test_runs", "factory_test_criteria", column: "factory_test_criteria_id"
  add_foreign_key "factory_test_runs", "factory_test_sessions"
  add_foreign_key "factory_test_runs", "users"
  add_foreign_key "factory_test_sessions", "entities"
  add_foreign_key "factory_test_sessions", "users"
  add_foreign_key "global_knowledge_archives", "entities"
  add_foreign_key "governance_proposals", "entities"
  add_foreign_key "governance_proposals", "users", column: "proposer_id"
  add_foreign_key "governance_votes", "governance_proposals"
  add_foreign_key "governance_votes", "users"
  add_foreign_key "hub_messages", "agent_input_requests"
  add_foreign_key "hub_messages", "agent_plugin_executions"
  add_foreign_key "hub_messages", "hub_messages", column: "reply_to_id"
  add_foreign_key "hub_messages", "hub_threads"
  add_foreign_key "hub_participants", "hub_threads"
  add_foreign_key "hub_presences", "agent_plugin_executions", column: "active_execution_id"
  add_foreign_key "hub_presences", "entities"
  add_foreign_key "hub_threads", "agent_plugin_executions"
  add_foreign_key "hub_threads", "agent_work_items"
  add_foreign_key "hub_threads", "entities"
  add_foreign_key "hub_threads", "team_channels"
  add_foreign_key "image_assets", "entities"
  add_foreign_key "image_assets", "users"
  add_foreign_key "integration_action_executions", "connections"
  add_foreign_key "integration_action_executions", "entities"
  add_foreign_key "integration_action_executions", "integration_actions"
  add_foreign_key "integration_action_executions", "users"
  add_foreign_key "integration_actions", "entities"
  add_foreign_key "integration_actions", "integration_operations"
  add_foreign_key "integration_actions", "integrations"
  add_foreign_key "integration_actions", "users", column: "created_by_id"
  add_foreign_key "integration_credentials", "connections"
  add_foreign_key "integration_embeddings", "entities"
  add_foreign_key "integration_embeddings", "integrations"
  add_foreign_key "integration_logs", "connections"
  add_foreign_key "integration_logs", "integration_operations"
  add_foreign_key "integration_logs", "scout_messages"
  add_foreign_key "integration_logs", "users"
  add_foreign_key "integration_operations", "integrations"
  add_foreign_key "integration_staging_records", "connections"
  add_foreign_key "integration_staging_records", "entities"
  add_foreign_key "integration_staging_records", "scheduled_agent_tasks"
  add_foreign_key "integration_staging_records", "users", column: "reviewed_by_id"
  add_foreign_key "integration_sync_configs", "connections"
  add_foreign_key "integration_sync_configs", "entities"
  add_foreign_key "integration_sync_configs", "scheduled_agent_tasks"
  add_foreign_key "integration_sync_cursors", "connections"
  add_foreign_key "integration_sync_cursors", "entities"
  add_foreign_key "integration_sync_records", "connections"
  add_foreign_key "integration_sync_records", "entities"
  add_foreign_key "integrations", "entities"
  add_foreign_key "integrations", "users", column: "created_by_id"
  add_foreign_key "integrations", "users", column: "reviewed_by_id", on_delete: :nullify
  add_foreign_key "knowledge_documents", "entities"
  add_foreign_key "landing_page_chat_messages", "landing_pages"
  add_foreign_key "landing_page_chat_messages", "users"
  add_foreign_key "landing_page_submissions", "contacts"
  add_foreign_key "landing_page_submissions", "landing_pages"
  add_foreign_key "landing_page_versions", "landing_pages"
  add_foreign_key "landing_pages", "campaigns"
  add_foreign_key "landing_pages", "custom_domains"
  add_foreign_key "landing_pages", "entities"
  add_foreign_key "landing_pages", "users"
  add_foreign_key "loadout_metrics", "entities"
  add_foreign_key "loadout_metrics", "users"
  add_foreign_key "loadout_versions", "agent_plugins"
  add_foreign_key "mcp_connections", "entities"
  add_foreign_key "memory_bookmarks", "entities"
  add_foreign_key "memory_bookmarks", "scout_messages"
  add_foreign_key "memory_bookmarks", "users"
  add_foreign_key "memory_preferences", "entities"
  add_foreign_key "memory_preferences", "users"
  add_foreign_key "memory_segments", "entities"
  add_foreign_key "memory_segments", "users"
  add_foreign_key "model_permissions", "custom_models"
  add_foreign_key "model_permissions", "entities"
  add_foreign_key "model_quality_logs", "entities"
  add_foreign_key "model_quality_logs", "users"
  add_foreign_key "module_actions", "app_modules"
  add_foreign_key "module_actions", "entities"
  add_foreign_key "module_canvases", "app_modules"
  add_foreign_key "module_canvases", "custom_domains"
  add_foreign_key "module_canvases", "entities"
  add_foreign_key "module_codes", "app_modules"
  add_foreign_key "module_codes", "entities"
  add_foreign_key "module_design_sessions", "app_modules"
  add_foreign_key "module_design_sessions", "entities"
  add_foreign_key "module_integrations", "app_modules"
  add_foreign_key "module_integrations", "integrations"
  add_foreign_key "module_webhooks", "app_modules"
  add_foreign_key "module_webhooks", "entities"
  add_foreign_key "o_auth_configurations", "entities"
  add_foreign_key "o_auth_configurations", "integrations"
  add_foreign_key "oauth_configurations", "integrations"
  add_foreign_key "observability_events", "entities"
  add_foreign_key "observability_events", "users"
  add_foreign_key "ocr_metrics", "entities"
  add_foreign_key "ocr_metrics", "rag_documents"
  add_foreign_key "opportunities", "agent_plugins", column: "assigned_agent_id"
  add_foreign_key "opportunities", "contacts"
  add_foreign_key "opportunities", "entities"
  add_foreign_key "opportunities", "users"
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
  add_foreign_key "platform_anomalies", "agent_goals", column: "triggered_goal_id"
  add_foreign_key "platform_anomalies", "entities"
  add_foreign_key "platform_anomalies", "platform_perceptions"
  add_foreign_key "platform_evolution_tickets", "entities"
  add_foreign_key "platform_perceptions", "entities"
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
  add_foreign_key "pull_request_submissions", "code_fixes"
  add_foreign_key "pull_request_submissions", "entities"
  add_foreign_key "pull_request_submissions", "support_tickets"
  add_foreign_key "rag_chunks", "rag_documents"
  add_foreign_key "rag_documents", "rag_documents", column: "parent_document_id"
  add_foreign_key "rag_documents", "rag_stores"
  add_foreign_key "rag_documents", "users", column: "last_accessed_by_id"
  add_foreign_key "rag_processing_jobs", "rag_stores"
  add_foreign_key "rag_queries", "entities"
  add_foreign_key "rag_queries", "rag_stores"
  add_foreign_key "rag_stores", "agent_plugins"
  add_foreign_key "rag_stores", "entities"
  add_foreign_key "rag_stores", "users"
  add_foreign_key "referrals", "affiliates"
  add_foreign_key "referrals", "entities", column: "referred_entity_id"
  add_foreign_key "referrals", "users", column: "referred_user_id"
  add_foreign_key "revenue_payments", "revenue_distributions"
  add_foreign_key "revenue_payments", "users"
  add_foreign_key "rich_text_sections", "landing_pages"
  add_foreign_key "saved_searches", "entities"
  add_foreign_key "saved_searches", "users"
  add_foreign_key "saved_visualizations", "agent_plugin_executions"
  add_foreign_key "saved_visualizations", "agent_work_items"
  add_foreign_key "saved_visualizations", "dynamic_contents"
  add_foreign_key "saved_visualizations", "entities"
  add_foreign_key "saved_visualizations", "scout_conversations"
  add_foreign_key "saved_visualizations", "scout_messages"
  add_foreign_key "saved_visualizations", "users"
  add_foreign_key "scheduled_agent_tasks", "agent_plugins"
  add_foreign_key "scheduled_agent_tasks", "app_modules"
  add_foreign_key "scheduled_agent_tasks", "entities"
  add_foreign_key "scheduled_agent_tasks", "users"
  add_foreign_key "scheduled_task_runs", "agent_plugin_executions"
  add_foreign_key "scheduled_task_runs", "scheduled_agent_tasks"
  add_foreign_key "scheduled_task_runs", "users"
  add_foreign_key "scout_conversations", "entities"
  add_foreign_key "scout_conversations", "users"
  add_foreign_key "scout_learnings", "entities"
  add_foreign_key "scout_loadout_configurations", "entities"
  add_foreign_key "scout_messages", "entities"
  add_foreign_key "scout_messages", "users"
  add_foreign_key "scout_personalities", "entities"
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
  add_foreign_key "support_tickets", "entities"
  add_foreign_key "support_tickets", "scout_conversations"
  add_foreign_key "support_tickets", "users"
  add_foreign_key "system_documents", "rag_stores"
  add_foreign_key "system_documents", "users", column: "uploaded_by_id"
  add_foreign_key "system_notifications", "entities"
  add_foreign_key "system_notifications", "users"
  add_foreign_key "task_dependencies", "task_sessions"
  add_foreign_key "task_dependencies", "task_sessions", column: "depends_on_task_id"
  add_foreign_key "task_events", "task_sessions"
  add_foreign_key "task_experiences", "entities"
  add_foreign_key "task_experiences", "evolution_cycles"
  add_foreign_key "task_sessions", "users"
  add_foreign_key "task_trackers", "entities"
  add_foreign_key "team_channels", "entities"
  add_foreign_key "team_invites", "entities"
  add_foreign_key "team_invites", "users", column: "invited_by_id"
  add_foreign_key "tenant_quotas", "entities"
  add_foreign_key "token_claims", "entities"
  add_foreign_key "token_claims", "users"
  add_foreign_key "token_deposits", "entities"
  add_foreign_key "token_deposits", "token_stakes"
  add_foreign_key "token_deposits", "users"
  add_foreign_key "token_stake_transactions", "token_stakes"
  add_foreign_key "token_stake_transactions", "users"
  add_foreign_key "token_stakes", "entities"
  add_foreign_key "token_stakes", "users"
  add_foreign_key "token_stakes", "users", column: "beneficiary_id"
  add_foreign_key "token_stakes", "users", column: "transferred_to_id"
  add_foreign_key "tool_definitions", "app_modules"
  add_foreign_key "tool_definitions", "entities"
  add_foreign_key "tool_definitions", "users", column: "created_by_id"
  add_foreign_key "tool_usage_metrics", "entities"
  add_foreign_key "tool_usage_metrics", "tool_definitions"
  add_foreign_key "tool_usage_metrics", "users"
  add_foreign_key "tts_usage_logs", "entities"
  add_foreign_key "tts_usage_logs", "users"
  add_foreign_key "user_billing_accounts", "users"
  add_foreign_key "user_communication_preferences", "users"
  add_foreign_key "user_favorites", "entities"
  add_foreign_key "user_favorites", "users"
  add_foreign_key "user_feedbacks", "entities"
  add_foreign_key "user_feedbacks", "users"
  add_foreign_key "user_memories", "entities"
  add_foreign_key "user_memories", "users"
  add_foreign_key "user_menu_configurations", "users"
  add_foreign_key "user_notes", "users"
  add_foreign_key "user_notifications", "agent_work_items"
  add_foreign_key "user_notifications", "entities"
  add_foreign_key "user_notifications", "scheduled_task_runs"
  add_foreign_key "user_notifications", "users"
  add_foreign_key "user_referrals", "users", column: "referred_user_id"
  add_foreign_key "user_referrals", "users", column: "referrer_id"
  add_foreign_key "user_reminders", "users"
  add_foreign_key "user_space_preferences", "users"
  add_foreign_key "users", "entities"
  add_foreign_key "voice_sessions", "entities"
  add_foreign_key "voice_sessions", "users"
  add_foreign_key "web_app_modules", "app_modules"
  add_foreign_key "web_app_modules", "web_apps"
  add_foreign_key "web_app_scripts", "entities"
  add_foreign_key "web_app_scripts", "landing_pages"
  add_foreign_key "web_app_scripts", "web_apps"
  add_foreign_key "web_app_scripts", "websites"
  add_foreign_key "web_apps", "application_plans"
  add_foreign_key "web_apps", "entities"
  add_foreign_key "web_apps", "users", column: "created_by_id"
  add_foreign_key "web_apps", "websites"
  add_foreign_key "webhook_events", "webhook_subscriptions"
  add_foreign_key "webhook_subscriptions", "connections"
  add_foreign_key "website_pages", "app_modules"
  add_foreign_key "website_pages", "entities"
  add_foreign_key "website_pages", "websites"
  add_foreign_key "websites", "application_plans"
  add_foreign_key "websites", "custom_domains"
  add_foreign_key "websites", "entities"
  add_foreign_key "websites", "users", column: "created_by_id"
  add_foreign_key "work_token_purchases", "user_billing_accounts"
  add_foreign_key "work_token_purchases", "users"
  add_foreign_key "work_token_purchases", "work_token_transactions"
  add_foreign_key "work_token_transactions", "entities"
  add_foreign_key "work_token_transactions", "entity_billing_accounts"
  add_foreign_key "work_token_transactions", "user_billing_accounts"
  add_foreign_key "work_token_transactions", "users"
  add_foreign_key "work_token_usage_summaries", "entities"
  add_foreign_key "work_token_usage_summaries", "entity_billing_accounts"
  add_foreign_key "work_token_usage_summaries", "user_billing_accounts"
  add_foreign_key "work_token_usage_summaries", "users"
  add_foreign_key "workflow_contexts", "task_sessions"
  add_foreign_key "workflow_contexts", "workflow_executions"
  add_foreign_key "workflow_executions", "entities"
  add_foreign_key "workflow_executions", "task_sessions"
  add_foreign_key "workflow_executions", "users"
  add_foreign_key "workflow_step_executions", "workflow_executions"
  add_foreign_key "workflow_triggers", "automation_codes"
  add_foreign_key "workflow_triggers", "entities"
  add_foreign_key "workflow_variables", "workflow_executions"
end
