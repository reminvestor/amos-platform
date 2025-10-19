# AMOS Code Patterns Reference

## Entity Scoping (Multi-Tenant)

All data must be scoped to entities for proper multi-tenant isolation.

### Model Pattern

```ruby
class Feature < ApplicationRecord
  belongs_to :entity

  validates :name, presence: true
  validates :name, uniqueness: { scope: :entity_id }

  scope :for_entity, ->(entity) { where(entity_id: entity.id) }
  scope :accessible_by, ->(user) { where(entity_id: user.entity_id) }
end
```

### Migration Pattern

```ruby
class CreateFeatures < ActiveRecord::Migration[8.0]
  def change
    create_table :features do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    add_index :features, [:entity_id, :name], unique: true
  end
end
```

### Controller Pattern

```ruby
class FeaturesController < ApplicationController
  include EntityScoped  # Provides current_entity
  before_action :authenticate_user!

  def index
    @features = Feature.accessible_by(current_user)
  end

  def create
    @feature = current_entity.features.create!(feature_params)
    redirect_to @feature
  end
end
```

## Scout AI Tool Pattern

Tools extend BaseTool and are auto-discovered by ToolCatalog.

```ruby
module Tools
  class FeatureTool < BaseTool
    def self.definition
      {
        name: 'create_feature',
        description: 'Creates a new feature for the entity',
        category: 'features',
        input_schema: {
          type: 'object',
          properties: {
            name: { type: 'string', description: 'Feature name' },
            description: { type: 'string', description: 'Description' }
          },
          required: ['name']
        }
      }
    end

    def execute(args)
      # @user, @entity, @workflow_execution available
      feature = Feature.create!(
        entity: @entity,
        name: args['name'],
        description: args['description']
      )

      success_response(
        message: "Feature '#{feature.name}' created!",
        data: { id: feature.id, name: feature.name }
      )
    rescue => e
      error_response("Failed to create feature: #{e.message}")
    end
  end
end
```

## Service Pattern

```ruby
class FeatureService
  def initialize(user, entity)
    @user = user
    @entity = entity
  end

  def create_feature(params)
    Feature.create!(
      entity: @entity,
      **params
    )
  end

  def list_features
    Feature.accessible_by(@user)
  end
end
```

## Testing Patterns

### Model Test

```ruby
require "test_helper"

class FeatureTest < ActiveSupport::TestCase
  def setup
    @entity = entities(:one)
  end

  test "validates presence of name" do
    feature = Feature.new(entity: @entity)
    assert_not feature.valid?
    assert_includes feature.errors[:name], "can't be blank"
  end

  test "accessible_by scope filters by user entity" do
    user = users(:one)
    features = Feature.accessible_by(user)
    assert features.all? { |f| f.entity_id == user.entity_id }
  end
end
```

### Tool Test

```ruby
require "test_helper"

class FeatureToolTest < ActiveSupport::TestCase
  def setup
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::FeatureTool.new(
      entity: @entity,
      user: @user
    )
  end

  test "creates feature successfully" do
    result = @tool.execute({ 'name' => 'Test Feature' })

    assert result[:success]
    assert_includes result[:message], 'created'
    assert result[:data][:id]
  end
end
```

## Database Best Practices

- Always add `entity_id` foreign key with `null: false`
- Add indexes on `entity_id` and uniqueness constraints
- Use `jsonb` for flexible metadata
- Add timestamps with `t.timestamps`

## Error Handling

```ruby
def create_feature(params)
  Feature.create!(params)
rescue ActiveRecord::RecordInvalid => e
  error_response("Validation failed: #{e.message}")
rescue => e
  error_response("Unexpected error: #{e.message}")
end
```
