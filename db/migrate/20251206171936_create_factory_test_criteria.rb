class CreateFactoryTestCriteria < ActiveRecord::Migration[8.0]
  def change
    create_table :factory_test_criteria do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      
      # Polymorphic association - what is being tested?
      t.string :testable_type, null: false
      t.bigint :testable_id, null: false
      
      # Test definition
      t.string :name, null: false
      t.text :description
      t.string :test_type, null: false, default: 'semantic'  # semantic, programmatic, http_status, json_schema, regex
      t.integer :weight, default: 1  # Importance weight for scoring
      t.integer :position, default: 0  # Order of execution
      
      # Test inputs
      t.text :input_prompt  # What to send to the agent/tool
      t.jsonb :input_data, default: {}  # Structured input data
      
      # Expected outputs
      t.text :expected_output  # For semantic comparison
      t.jsonb :expected_values, default: {}  # For programmatic checks
      t.jsonb :validation_rules, default: {}  # Rules like { min_length: 10, max_length: 500, must_contain: ["keyword"] }
      
      # HTTP-specific (for integrations)
      t.integer :expected_status_code  # 200, 201, etc.
      t.jsonb :expected_headers, default: {}
      
      # Metadata
      t.boolean :is_required, default: true  # Must pass for overall success
      t.boolean :is_active, default: true
      t.string :category  # setup, functionality, edge_case, security
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :factory_test_criteria, [:testable_type, :testable_id], name: 'idx_test_criteria_testable'
    add_index :factory_test_criteria, [:testable_type, :testable_id, :is_active], name: 'idx_test_criteria_active'
    add_index :factory_test_criteria, :test_type
    add_index :factory_test_criteria, :category
  end
end

