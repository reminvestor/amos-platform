# frozen_string_literal: true

# == Schema Information
#
# Table name: factory_test_criteria
#
#  id                   :bigint           not null, primary key
#  entity_id            :bigint           not null
#  user_id              :bigint           not null
#  testable_type        :string           not null
#  testable_id          :bigint           not null
#  name                 :string           not null
#  description          :text
#  test_type            :string           default("semantic")
#  weight               :integer          default(1)
#  position             :integer          default(0)
#  input_prompt         :text
#  input_data           :jsonb            default({})
#  expected_output      :text
#  expected_values      :jsonb            default({})
#  validation_rules     :jsonb            default({})
#  expected_status_code :integer
#  expected_headers     :jsonb            default({})
#  is_required          :boolean          default(TRUE)
#  is_active            :boolean          default(TRUE)
#  category             :string
#  metadata             :jsonb            default({})
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
class FactoryTestCriteria < ApplicationRecord
  # ============================================
  # ASSOCIATIONS
  # ============================================
  
  belongs_to :entity
  belongs_to :user
  belongs_to :testable, polymorphic: true
  
  has_many :factory_test_runs, dependent: :destroy

  # ============================================
  # VALIDATIONS
  # ============================================
  
  VALID_TEST_TYPES = %w[semantic programmatic http_status json_schema regex contains].freeze
  VALID_CATEGORIES = %w[setup functionality edge_case security performance].freeze
  VALID_TESTABLE_TYPES = %w[AgentPlugin ToolDefinition Integration].freeze

  validates :name, presence: true, length: { maximum: 255 }
  validates :test_type, presence: true, inclusion: { in: VALID_TEST_TYPES }
  validates :testable_type, presence: true, inclusion: { in: VALID_TESTABLE_TYPES }
  validates :category, inclusion: { in: VALID_CATEGORIES }, allow_blank: true
  validates :weight, numericality: { greater_than: 0, less_than_or_equal_to: 10 }

  # ============================================
  # SCOPES
  # ============================================
  
  scope :active, -> { where(is_active: true) }
  scope :required, -> { where(is_required: true) }
  scope :optional, -> { where(is_required: false) }
  scope :by_position, -> { order(position: :asc, created_at: :asc) }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :for_testable, ->(testable) { where(testable: testable) }
  
  scope :semantic, -> { where(test_type: 'semantic') }
  scope :programmatic, -> { where(test_type: %w[programmatic http_status json_schema regex contains]) }

  # ============================================
  # CALLBACKS
  # ============================================
  
  before_validation :set_defaults

  # ============================================
  # CLASS METHODS
  # ============================================
  
  # Generate test criteria for a testable item using AI
  def self.generate_for(testable, user:, entity:)
    generator = Factories::TestCriteriaGenerator.new(user: user, entity: entity)
    generator.generate_tests_for(testable)
  end

  # ============================================
  # INSTANCE METHODS
  # ============================================
  
  # Run this test and return a FactoryTestRun
  def run!(session:, attempt_number: 1)
    runner = Factories::FactoryTestRunner.new(session: session)
    runner.run_single_test(self, attempt_number: attempt_number)
  end

  # Check if this test can be run programmatically
  def programmatic?
    test_type.in?(%w[programmatic http_status json_schema regex contains])
  end

  # Check if this test requires AI evaluation
  def semantic?
    test_type == 'semantic'
  end

  # Get a human-readable description of what this test checks
  def human_description
    case test_type
    when 'semantic'
      "AI evaluates if output matches expected behavior: #{expected_output.to_s.truncate(100)}"
    when 'http_status'
      "HTTP response returns status #{expected_status_code}"
    when 'json_schema'
      "Response matches JSON schema: #{validation_rules['schema']&.to_s&.truncate(100)}"
    when 'regex'
      "Output matches pattern: #{validation_rules['pattern']}"
    when 'contains'
      "Output contains: #{validation_rules['must_contain']&.join(', ')}"
    when 'programmatic'
      "Programmatic check: #{description || name}"
    else
      description || name
    end
  end

  # Calculate max score this test can contribute
  def max_score
    weight * (is_required ? 2 : 1)  # Required tests worth double
  end

  private

  def set_defaults
    self.position ||= FactoryTestCriteria.where(testable: testable).maximum(:position).to_i + 1
    self.category ||= 'functionality'
  end
end

